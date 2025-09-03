import Foundation
import Logging

final class JSONRPCConnection: Sendable {
    private let queue: DispatchQueue
    private let source: DispatchSourceRead
    private let stdin: FileHandle
    private let stdout: FileHandle

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private let separator: Data

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
        queue = DispatchQueue(label: "local.sourcekit.bsp")
        stdin = FileHandle.standardInput
        stdout = FileHandle.standardOutput
        source = DispatchSource.makeReadSource(fileDescriptor: stdin.fileDescriptor, queue: queue)
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        separator = "\r\n\r\n".data(using: .utf8)!
    }
}

extension JSONRPCConnection {
    struct Message: Decodable {
        let method: String
    }
}

extension JSONRPCConnection {
    func start(messageHandler: @escaping @Sendable (_ msg: Message, _ body: Data) async -> Void) {
        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            do {
                let (msg, body) = try self.receiveMessage()
                Task<Void, Never> {
                    await messageHandler(msg, body)
                }
            } catch is NothingToReadError {
                // skip
            } catch {
                self.logger.error("\(error)")
            }
        }
        source.resume()
    }

    private func receiveMessage() throws -> (message: Message, body: Data) {
        let data = stdin.availableData
        guard data.isEmpty == false else {
            throw NothingToReadError()
        }

        let parts = data.split(separator: separator)
        guard parts.count == 2 else {
            throw InvalidMessageError(reason: .failedToSplit(separator: separator), data: data)
        }

        let body = parts[1]
        do {
            let msg = try decoder.decode(Message.self, from: body)
            return (msg, body)
        } catch let error as DecodingError {
            throw InvalidMessageError(reason: .failedToDecode(decodingError: error), data: data)
        }
    }

    func send(message: some Encodable) throws {
        let data = try encoder.encode(message)
        let header = "Content-Length: \(data.count)".data(using: .utf8)!
        stdout.write(header + separator + data)
    }
}

extension JSONRPCConnection {
    private struct NothingToReadError: Error {
    }

    struct InvalidMessageError: Error {
        let reason: Reason
        let data: Data
    }
}

extension JSONRPCConnection.InvalidMessageError {
    enum Reason {
        case failedToSplit(separator: Data)
        case failedToDecode(decodingError: DecodingError)
    }
}

extension JSONRPCConnection.InvalidMessageError: CustomStringConvertible {
    var description: String {
        return "Invalid message (reason=\(reason)): \(String(data: data, encoding: .utf8) ?? "")"
    }
}

extension JSONRPCConnection.InvalidMessageError.Reason: CustomStringConvertible {
    var description: String {
        switch self {
        case let .failedToSplit(separator):
            return "failed to split with separator \(String(data: separator, encoding: .utf8) ?? "")"
        case let .failedToDecode(decoderError):
            return "failed to decode error \(decoderError)"
        }
    }
}

