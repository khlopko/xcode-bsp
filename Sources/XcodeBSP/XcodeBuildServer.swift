import CryptoKit
import Foundation
import Logging

final class XcodeBuildServer: Sendable {
    private let conn: JSONRPCConn
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger
    private let registry: HandlersRegistry

    init() throws {
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        logger = try makeLogger(label: "xcode-bsp")
        conn = JSONRPCConn(logger: logger)
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

    private func dispatch(message: JSONRPCConn.Message, body: Data) throws {
        guard let handler = registry.handler(for: message) else {
            logger.error("unhandled method: \(message.method)")
            logger.debug("unhandled message: \(String(data: body, encoding: .utf8) ?? "")")
            return
        }

        func _open(_ handler: some MethodHandler) throws {
            let response = try handler.handle(data: body, decoder: decoder)
            try send(response)
        }

        try _open(handler)
    }

    private struct UnhandledMethodError: Error {
        let method: String
        let data: Data
    }

    private func send(_ resp: some Encodable) throws {
        let data = try encoder.encode(resp)
        let header = "Content-Length: \(data.count)\r\n\r\n".data(using: .utf8)!
        FileHandle.standardOutput.write(header + data)
    }
}
