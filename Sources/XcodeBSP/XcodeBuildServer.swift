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
        registry = HandlersRegistry(handlers: [
            BuildInitialize(xcodebuild: xcodebuild, cacheDir: cacheDir, logger: logger),
            BuildShutdown(),
            BuildExit(),
            TextDocumentRegisterForChanges(),
            WorkspaceBuildTargets(xcodebuild: xcodebuild, logger: logger),
            BuildTargetPrepare(logger: logger),
            BuildTargetSources(xcodebuild: xcodebuild, logger: logger),
            TextDocumentSourceKitOptions(xcodebuild: xcodebuild, db: db, logger: logger),
        ])
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
                try await self.dispatch(message: msg, body: body)
                self.logger.debug("response for \(msg.method) sent")
            } catch let error as UnhandledMethodError { 
                self.logger.error("unhandled method: \(error.method)")
                self.logger.debug("unhandled message: \(String(data: error.data, encoding: .utf8) ?? "")")
            } catch {
                self.logger.error("\(error)") 
            }
        }

        RunLoop.current.run()
    }

    private func dispatch(message: JSONRPCConnection.Message, body: Data) async throws {
        guard let handler = registry.handler(for: message) else {
            throw UnhandledMethodError(method: message.method, data: body)
        }

        // hack to open existential and be able to call handle on it
        func handle(with handler: some MethodHandler) async throws -> some Encodable {
            return try await handler.handle(data: body, decoder: decoder)
        }

        let response = try await handle(with: handler)
        try conn.send(message: response)
    }

    private struct UnhandledMethodError: Error {
        let method: String
        let data: Data
    }
}
