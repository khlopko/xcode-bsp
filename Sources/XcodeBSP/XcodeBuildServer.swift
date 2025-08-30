import Foundation
import Logging

final class XcodeBuildServer {
    private let queue: DispatchQueue
    private let source: DispatchSourceRead
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger

    init() throws {
        queue = DispatchQueue(label: "local.sourcekit.bsp")
        source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: queue)
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        logger = try makeLogger(label: "xcode-bsp")
    }
}

extension XcodeBuildServer {
    func run() throws {
        source.setEventHandler { [weak self] in
            self?.receiveMessage()
        }
        source.resume()

        RunLoop.current.run()
    }

    private func receiveMessage() {
        do {
            let data = FileHandle.standardInput.availableData
            guard data.isEmpty == false, let sep = "\r\n\r\n".data(using: .utf8) else {
                return
            }

            let parts = data.split(separator: sep)
            guard parts.count == 2 else {
                logger.error("expected 2 parts of message, got \(parts.count)")
                return
            }

            let baseReq = try decoder.decode(BaseRequest.self, from: parts[1])
            try dispatch(baseReq: baseReq, contents: parts[1])
        } catch {
            logger.error("\(error)")
        }
    }
}

extension XcodeBuildServer {
    struct BaseRequest: Decodable {
        let method: String
    }
}

extension XcodeBuildServer {
    struct Request<Params>: Decodable, CustomStringConvertible where Params: Decodable {
        var description: String {
            return "{\"id\":\"\(id)\",\"method\":\"\(method)\",\"params\":\"\(params)\"}"
        }

        struct InvalidJSONError: Error {
            let data: Data
        }

        struct InvlidFieldError: Error {
            let key: String
            let value: any Sendable
            let expectedType: Any.Type
        }

        let id: String
        let method: String
        let params: Params
    }
}

extension XcodeBuildServer {
    private var routes: [String: (Data) throws -> Void] {
        [
            "build/initialize": buildInitialize(data:),
        ]
    }

    struct UnhandledMethodError: Error {
        let method: String
        let data: Data
    }

    func dispatch(baseReq: BaseRequest, contents: Data) throws {
        guard let route = routes[baseReq.method] else {
            logger.error("unhandled method: \(baseReq.method)")
            return
        }

        try route(contents)
    }

    struct InitializeParams: Decodable {
    }

    struct Response<Result>: Encodable where Result: Encodable {
        let jsonrpc: String = "2.0"
        let id: String
        let result: Result
    }

    struct InitializeResult: Encodable {
        let displayName: String = "xcode-bsp"
        let version: String = "0.1.0"
        let bspVersion: String = "2.0.0"
        let capabilities: Capabilities

        struct Capabilities: Encodable {
            let languageIds: [String] = ["swift", "objective-c", "objective-cpp", "c", "cpp"]
        }
    }

    private func buildInitialize(data: Data) throws {
        let req = try decoder.decode(Request<InitializeParams>.self, from: data)
        logger.debug("\(#function): \(req)")
        let resp = Response(id: req.id, result: InitializeResult(capabilities: InitializeResult.Capabilities()))
        try send(resp)
    }

    struct ShutdownParams: Decodable {
    }

    private func buildShutdown(req: Request<ShutdownParams>) {
        source.suspend()
    }

    struct ExitParams: Decodable {
    }

    private func buildExit(req: Request<ExitParams>) {
        exit(0)
    }

    private func send(_ resp: some Encodable) throws {
        let data = try encoder.encode(resp)
        let header = "Content-Length: \(data.count)\r\n\r\n".data(using: .utf8)!
        FileHandle.standardOutput.write(header + data)
    }
}
