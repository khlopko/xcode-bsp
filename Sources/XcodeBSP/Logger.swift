import Foundation
import Logging

func makeLogger(label: String) throws -> Logger {
    var logger = Logger(label: label)
    let logHandler = try FileLogHandler()
    logger.handler = logHandler
    return logger
}

private struct FileLogHandler: LogHandler {
    var metadata: Logger.Metadata = [:]
    var metadataProvider: Logger.MetadataProvider?
    var logLevel: Logger.Level = .debug
    private let encoder: JSONEncoder
    private let fileHandle: FileHandle

    enum InitializationError: Error {
        case noFileHandle
        case failedSeekToEnd(any Error)
    }

    init() throws {
        let tmpDirPath = "/tmp/xcode-bsp"
        if FileManager.default.fileExists(atPath: tmpDirPath) == false {
            try FileManager.default.createDirectory(
                atPath: tmpDirPath, withIntermediateDirectories: false)
        }
        let logPath = tmpDirPath + "/default.log"
        if FileManager.default.fileExists(atPath: logPath) == false {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        guard let fileHandle = FileHandle(forUpdatingAtPath: logPath) else {
            throw InitializationError.noFileHandle
        }

        do {
            try fileHandle.seekToEnd()
        } catch {
            throw InitializationError.failedSeekToEnd(error)
        }

        self.fileHandle = fileHandle
        encoder = JSONEncoder()
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            metadata[key]
        }
        set {
            metadata[key] = newValue
        }
    }

    private struct LogMsg: Encodable {
        let at: String
        let level: Logger.Level
        let origin: String
        let message: String
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let msg = LogMsg(
            at: Date().ISO8601Format(),
            level: level,
            origin: "\(file.split(separator: ".").first.map { String($0) } ?? file).\(function):\(line)",
            message: "\(message)"
        )
        do {
            let data = try encoder.encode(msg)
            fileHandle.write(data + "\r\n".data(using: .utf8)!)
        } catch {
            // we lost log
        }
    }
}
