import Foundation
import Logging

final class XcodeBuildServer: Sendable {
    private let conn: JSONRPCConnection
    private let decoder: JSONDecoder
    private let logger: Logger
    private let registry: HandlersRegistry
    private let state: BuildSystemState
    private let notificationEmitter: PendingNotificationsEmitter

    init(cacheDir: URL) throws {
        decoder = JSONDecoder()
        var logger = try makeLogger(label: "xcode-bsp")
        logger.logLevel = .trace
        self.logger = logger
        conn = JSONRPCConnection(logger: logger)
        state = BuildSystemState()
        let enableLegacySourceKitOptionsChanged = Self.legacySourceKitOptionsChangedEnabled()
        notificationEmitter = PendingNotificationsEmitter(
            conn: conn,
            state: state,
            enableLegacySourceKitOptionsChanged: enableLegacySourceKitOptionsChanged
        )

        let xcodebuild = XcodeBuild(cacheDir: cacheDir, decoder: decoder, logger: logger)
        let db = try Database(cacheDir: cacheDir)
        let graph = BuildGraphService(xcodebuild: xcodebuild, logger: logger)
        let refreshCoordinator = BackgroundRefreshCoordinator(
            logger: logger,
            refreshAction: { [decoder, graph, state, notificationEmitter, logger] reason in
                await state.beginUpdate()
                do {
                    let refresh = try await graph.refresh(decoder: decoder, checkCache: true)
                    await state.recordRefreshChanges(refresh)
                    await state.endUpdate()
                    try await notificationEmitter.emit()
                } catch {
                    await state.endUpdate()
                    logger.error("background refresh failed (reason=\(reason)): \(error)")
                }
            }
        )

        registry = HandlersRegistry(
            requestHandlers: [
                BuildInitialize(graph: graph, cacheDir: cacheDir),
                BuildShutdown(state: state),
                TextDocumentRegisterForChanges(state: state),
                WorkspaceBuildTargets(graph: graph),
                BuildTargetPrepare(graph: graph, db: db, logger: logger, state: state),
                BuildTargetSources(graph: graph),
                BuildTargetInverseSources(graph: graph),
                WorkspaceWaitForBuildSystemUpdates(state: state),
                TextDocumentSourceKitOptions(graph: graph, logger: logger, refreshTrigger: refreshCoordinator),
            ],
            notificationHandlers: [
                BuildInitialized(),
                WorkspaceDidChangeWatchedFiles(logger: logger),
                BuildExit(state: state),
            ]
        )
    }
}

extension XcodeBuildServer {
    func run() {
        conn.start { [weak self] msg, body in
            guard let self else {
                return
            }

            self.logger.debug("new message for \(msg.method)")
            do {
                let outcome = try await self.dispatch(message: msg, body: body)
                switch outcome {
                case .responseSent:
                    self.logger.debug("response for \(msg.method) sent")
                case .notificationHandled:
                    self.logger.debug("notification for \(msg.method) handled")
                }

                try await self.notificationEmitter.emit()
            } catch let error as UnhandledMethodError {
                switch error.kind {
                case .request:
                    self.logger.error("unhandled method: \(error.method)")
                    self.logger.debug("unhandled message: \(String(data: error.data, encoding: .utf8) ?? "")")
                    try? self.conn.send(
                        message: JSONRPCErrorResponse(
                            id: msg.id,
                            error: JSONRPCErrorPayload(code: -32601, message: "method not found: \(error.method)")
                        )
                    )
                case .notification:
                    self.logger.debug("unhandled notification method: \(error.method)")
                    self.logger.debug("unhandled notification message: \(String(data: error.data, encoding: .utf8) ?? "")")
                }
            } catch {
                self.logger.error("\(error)")
                if msg.isNotification == false {
                    try? self.conn.send(
                        message: JSONRPCErrorResponse(
                            id: msg.id,
                            error: JSONRPCErrorPayload(code: -32603, message: "internal error")
                        )
                    )
                }
            }
        }

        RunLoop.current.run()
    }

    private func dispatch(message: JSONRPCConnection.Message, body: Data) async throws -> DispatchOutcome {
        if message.isNotification {
            guard let handler = registry.notificationHandler(for: message) else {
                throw UnhandledMethodError(method: message.method, data: body, kind: .notification)
            }

            // hack to open existential and be able to call handle on it
            func handle(with handler: some NotificationMethodHandler) async throws {
                try await handler.handle(data: body, decoder: decoder)
            }

            try await handle(with: handler)
            return .notificationHandled
        }

        guard let handler = registry.requestHandler(for: message) else {
            throw UnhandledMethodError(method: message.method, data: body, kind: .request)
        }

        // hack to open existential and be able to call handle on it
        func handle(with handler: some MethodHandler) async throws -> some Encodable {
            return try await handler.handle(data: body, decoder: decoder)
        }

        let response = try await handle(with: handler)
        try conn.send(message: response)
        return .responseSent
    }

    private enum DispatchOutcome {
        case responseSent
        case notificationHandled
    }

    private enum MessageKind {
        case request
        case notification
    }

    private struct UnhandledMethodError: Error {
        let method: String
        let data: Data
        let kind: MessageKind
    }

    static func legacySourceKitOptionsChangedEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let value = environment["XCODE_BSP_ENABLE_LEGACY_SOURCEKITOPTIONS_CHANGED"]?.lowercased()
        switch value {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

struct JSONRPCErrorResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: JSONRPCID?
    let error: JSONRPCErrorPayload
}

struct JSONRPCErrorPayload: Encodable {
    let code: Int
    let message: String
}

struct JSONRPCNotificationMessage<Params>: Encodable where Params: Encodable {
    let jsonrpc: String = "2.0"
    let method: String
    let params: Params
}

struct BuildTargetDidChangeParams: Encodable {
    let changes: [BuildTargetDidChange]?
}

struct BuildTargetDidChange: Encodable {
    let target: TargetID
    let kind: Kind

    enum Kind: Int, Encodable {
        case changed = 1
        case deleted = 2
    }
}

struct BuildSourceKitOptionsChangedParams: Encodable {
    let uri: String
    let updatedOptions: UpdatedOptions
}

extension BuildSourceKitOptionsChangedParams {
    struct UpdatedOptions: Encodable {
        let options: [String]
        let workingDirectory: String?
    }
}
