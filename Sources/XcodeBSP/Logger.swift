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
    private let fileHandle: FileHandle

    enum InitializationError: Error {
        case noFileHandle
        case failedSeekToEnd(any Error)
    }

    init() throws {
        let tmpDirPath = "/tmp/xcode-bsp"
        try FileManager.default.createDirectory(atPath: tmpDirPath, withIntermediateDirectories: false)
        let logPath = tmpDirPath + "/default.log"
        if FileManager.default.fileExists(atPath: logPath) == false {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        guard let fileHandle = FileHandle(forUpdatingAtPath: logPath) else {
            throw InitializationError.noFileHandle
        }

        self.fileHandle = fileHandle
        do {
            try fileHandle.seekToEnd()
        } catch {
            throw InitializationError.failedSeekToEnd(error)
        }
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            metadata[key]
        }
        set {
            metadata[key] = newValue
        }
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
        fileHandle.write(
            "{\"at\":\"\(Date().ISO8601Format())\",\"level\":\"\(level)\",\"message\":\"\(message)\"}\n"
                .data(using: .utf8)!)
    }
}
