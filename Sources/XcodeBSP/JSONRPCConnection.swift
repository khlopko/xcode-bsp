import Foundation
import Logging

final class JSONRPCConnection: @unchecked Sendable {
    private let queue: DispatchQueue
    private let source: DispatchSourceRead
    private let stdin: FileHandle
    private let stdout: FileHandle

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private let separator: Data
    private let contentLengthHeader = "content-length:"
    private var inputBuffer: Data
    private let sendLock: NSLock

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
        inputBuffer = Data()
        sendLock = NSLock()
    }
}

extension JSONRPCConnection {
    struct Message: Decodable {
        let method: String

        let id: JSONRPCID?

        var isNotification: Bool {
            return id == nil
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            method = try container.decode(String.self, forKey: .method)
            id = try container.decodeIfPresent(JSONRPCID.self, forKey: .id)
        }

        private enum CodingKeys: CodingKey {
            case method
            case id
        }
    }
}

extension JSONRPCConnection {
    func start(messageHandler: @escaping @Sendable (_ msg: Message, _ body: Data) async -> Void) {
        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            do {
                let messages = try self.receiveMessages()
                guard messages.isEmpty == false else {
                    return
                }

                Task<Void, Never> {
                    for (msg, body) in messages {
                        await messageHandler(msg, body)
                    }
                }
            } catch is NothingToReadError {
                // skip
            } catch {
                self.logger.error("\(error)")
            }
        }
        source.resume()
    }

    private func receiveMessages() throws -> [(message: Message, body: Data)] {
        let data = stdin.availableData
        guard data.isEmpty == false else {
            throw NothingToReadError()
        }

        inputBuffer.append(data)

        var result: [(message: Message, body: Data)] = []
        while let body = try readSingleMessageBody() {
            do {
                let msg = try decoder.decode(Message.self, from: body)
                result.append((msg, body))
            } catch let error as DecodingError {
                throw InvalidMessageError(reason: .failedToDecode(decodingError: error), data: body)
            }
        }

        return result
    }

    private func readSingleMessageBody() throws -> Data? {
        guard let separatorRange = inputBuffer.range(of: separator) else {
            return nil
        }

        let headerData = Data(inputBuffer[inputBuffer.startIndex..<separatorRange.lowerBound])
        let contentLength = try parseContentLength(header: headerData)

        let bodyStartOffset = inputBuffer.distance(from: inputBuffer.startIndex, to: separatorRange.upperBound)
        let messageEndOffset = bodyStartOffset + contentLength
        guard inputBuffer.count >= messageEndOffset else {
            return nil
        }

        let messageEnd = inputBuffer.index(inputBuffer.startIndex, offsetBy: messageEndOffset)
        let body = Data(inputBuffer[separatorRange.upperBound..<messageEnd])

        inputBuffer.removeSubrange(inputBuffer.startIndex..<messageEnd)
        return body
    }

    private func parseContentLength(header: Data) throws -> Int {
        guard let headerString = String(data: header, encoding: .utf8) else {
            throw InvalidMessageError(reason: .failedToDecodeHeader, data: header)
        }

        let lines = headerString.components(separatedBy: "\r\n")
        for line in lines {
            let lowercased = line.lowercased()
            guard lowercased.hasPrefix(contentLengthHeader) else {
                continue
            }

            let value = line.dropFirst(contentLengthHeader.count).trimmingCharacters(in: .whitespaces)
            guard let length = Int(value), length >= 0 else {
                throw InvalidMessageError(reason: .failedToReadContentLength, data: header)
            }

            return length
        }

        throw InvalidMessageError(reason: .failedToReadContentLength, data: header)
    }

    func send(message: some Encodable) throws {
        let data = try encoder.encode(message)
        let header = "Content-Length: \(data.count)".data(using: .utf8)!
        sendLock.lock()
        defer {
            sendLock.unlock()
        }
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
        case failedToDecodeHeader
        case failedToReadContentLength
        case failedToDecode(decodingError: DecodingError)
    }
}

extension JSONRPCConnection.InvalidMessageError: CustomStringConvertible {
    var description: String {
        let previewLimit = 2048
        let text = String(data: data, encoding: .utf8) ?? ""
        let preview = text.count > previewLimit
            ? "\(text.prefix(previewLimit))...(truncated \(text.count - previewLimit) chars)"
            : text
        return "Invalid message (reason=\(reason)): \(preview)"
    }
}

extension JSONRPCConnection.InvalidMessageError.Reason: CustomStringConvertible {
    var description: String {
        switch self {
        case .failedToDecodeHeader:
            return "failed to decode message headers"
        case .failedToReadContentLength:
            return "failed to read Content-Length header"
        case let .failedToDecode(decoderError):
            return "failed to decode error \(decoderError)"
        }
    }
}
