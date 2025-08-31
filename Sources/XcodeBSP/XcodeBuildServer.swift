import CryptoKit
import Foundation
import Logging

final class XcodeBuildServer: Sendable {
    private let conn: JSONRPCConnection
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger
    private let registry: HandlersRegistry

    init() throws {
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        logger = try makeLogger(label: "xcode-bsp")
        conn = JSONRPCConnection(logger: logger)
        registry = HandlersRegistry(handlers: [
            BuildInitialize(logger: logger),
            BuildShutdown(),
            BuildExit(),
            TextDocumentRegisterForChanges(),
            WorkspaceBuildTargets(logger: logger),
            BuildTargetPrepare(logger: logger),
            BuildTargetSources(logger: logger),
        ])
    }
}

extension XcodeBuildServer {
    func run() {
        conn.start { [weak self] msg, body in
            guard let self else {
                return
            }
    
            logger.debug("new message for \(msg.method)")
            do {
                try self.dispatch(message: msg, body: body)
            } catch {
                self.logger.error("\(error)") 
            }
        }

        RunLoop.current.run()
    }

    private func dispatch(message: JSONRPCConnection.Message, body: Data) throws {
        guard let handler = registry.handler(for: message) else {
            logger.error("unhandled method: \(message.method)")
            logger.debug("unhandled message: \(String(data: body, encoding: .utf8) ?? "")")
            return
        }

        // hack to open existential and be able to call handle on it
        func handle(with handler: some MethodHandler) throws -> some Encodable {
            return try handler.handle(data: body, decoder: decoder)
        }

        let response = try handle(with: handler)
        try conn.send(message: response)
    }

    private struct UnhandledMethodError: Error {
        let method: String
        let data: Data
    }
}
