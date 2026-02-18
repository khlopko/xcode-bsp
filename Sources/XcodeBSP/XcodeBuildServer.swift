import Foundation
import Logging

final class XcodeBuildServer: Sendable {
    private let conn: JSONRPCConnection
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger
    private let registry: HandlersRegistry
    private let state: BuildSystemState

    init(cacheDir: URL) throws {
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        logger = try makeLogger(label: "xcode-bsp")
        conn = JSONRPCConnection(logger: logger)
        state = BuildSystemState()

        let xcodebuild = XcodeBuild(cacheDir: cacheDir, decoder: decoder, logger: logger)
        let db = try Database(cacheDir: cacheDir)
        registry = HandlersRegistry(
            requestHandlers: [
                BuildInitialize(xcodebuild: xcodebuild, cacheDir: cacheDir, logger: logger),
                BuildShutdown(state: state),
                TextDocumentRegisterForChanges(state: state),
                WorkspaceBuildTargets(xcodebuild: xcodebuild),
                BuildTargetPrepare(xcodebuild: xcodebuild, db: db, logger: logger, state: state),
                BuildTargetSources(xcodebuild: xcodebuild),
                BuildTargetInverseSources(xcodebuild: xcodebuild),
                WorkspaceWaitForBuildSystemUpdates(state: state),
                TextDocumentSourceKitOptions(xcodebuild: xcodebuild, db: db, logger: logger),
            ],
            notificationHandlers: [
                BuildInitialized(),
                WorkspaceDidChangeWatchedFiles(logger: logger, state: state),
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

                try await self.maybeSendBuildTargetDidChange(afterMethod: msg.method)
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

    private func maybeSendBuildTargetDidChange(afterMethod method: String) async throws {
        guard method == "workspace/didChangeWatchedFiles" else {
            return
        }

        guard await state.hasRegisteredDocuments() else {
            return
        }

        try conn.send(
            message: JSONRPCNotificationMessage(
                method: "buildTarget/didChange",
                params: BuildTargetDidChangeParams(changes: nil)
            )
        )
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
}

private struct JSONRPCErrorResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: String?
    let error: JSONRPCErrorPayload
}

private struct JSONRPCErrorPayload: Encodable {
    let code: Int
    let message: String
}

private struct JSONRPCNotificationMessage<Params>: Encodable where Params: Encodable {
    let jsonrpc: String = "2.0"
    let method: String
    let params: Params
}

private struct BuildTargetDidChangeParams: Encodable {
    let changes: [BuildTargetDidChange]?
}

private struct BuildTargetDidChange: Encodable {
    let target: TargetID
    let kind: Kind

    enum Kind: Int, Encodable {
        case changed = 1
        case deleted = 2
    }
}
