import CryptoKit
import Foundation
import Logging

final class XcodeBuildServer: Sendable {
    private let conn: JSONRPCConnection
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger
    private let registry: HandlersRegistry

    init(cacheDir: URL) throws {
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        logger = try makeLogger(label: "xcode-bsp")
        conn = JSONRPCConnection(logger: logger)
        let xcodebuild = XcodeBuild(cacheDir: cacheDir, decoder: decoder, logger: logger)
        let db = try Database(cacheDir: cacheDir)
        registry = HandlersRegistry(
            requestHandlers: [
                BuildInitialize(xcodebuild: xcodebuild, cacheDir: cacheDir, logger: logger),
                BuildShutdown(),
                TextDocumentRegisterForChanges(),
                WorkspaceBuildTargets(xcodebuild: xcodebuild, logger: logger),
                BuildTargetPrepare(logger: logger),
                BuildTargetSources(xcodebuild: xcodebuild, logger: logger),
                TextDocumentSourceKitOptions(xcodebuild: xcodebuild, db: db, logger: logger),
            ],
            notificationHandlers: [
                BuildInitialized(),
                WorkspaceDidChangeWatchedFiles(logger: logger),
                BuildExit(),
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
            } catch let error as UnhandledMethodError { 
                switch error.kind {
                case .request:
                    self.logger.error("unhandled method: \(error.method)")
                    self.logger.debug("unhandled message: \(String(data: error.data, encoding: .utf8) ?? "")")
                case .notification:
                    self.logger.debug("unhandled notification method: \(error.method)")
                    self.logger.debug("unhandled notification message: \(String(data: error.data, encoding: .utf8) ?? "")")
                }
            } catch {
                self.logger.error("\(error)") 
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
}
