import Foundation
import Logging

struct WorkspaceDidChangeWatchedFiles {
    let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }
}

extension WorkspaceDidChangeWatchedFiles: NotificationMethodHandler {
    var method: String {
        return "workspace/didChangeWatchedFiles"
    }

    func handle(notification: Notification<Params>, decoder: JSONDecoder) async throws {
        _ = decoder
        let changes = notification.params?.changes ?? []
        guard Self.hasRelevantChanges(changes) else {
            logger.debug(
                "workspace/didChangeWatchedFiles ignored \(changes.count) non-source changes")
            return
        }

        logger.trace("workspace/didChangeWatchedFiles ignored by design (\(changes.count) relevant changes)")
    }
}

extension WorkspaceDidChangeWatchedFiles {
    static func hasRelevantChanges(_ changes: [Params.ChangedFile]) -> Bool {
        return changes.contains { isRelevant(change: $0) }
    }

    private static func isRelevant(change: Params.ChangedFile) -> Bool {
        guard let url = URL(string: change.uri), url.isFileURL else {
            return true
        }

        let path = url.standardizedFileURL.path().lowercased()
        if path.contains("/.build/") || path.contains("/deriveddata/")
            || path.contains("/modulecache/") || path.contains("/index.noindex/")
        {
            return false
        }

        let fileExtension = URL(filePath: path).pathExtension
        if fileExtension.isEmpty {
            return true
        }

        return relevantExtensions.contains(fileExtension)
    }

    private static let relevantExtensions: Set<String> = [
        "swift",
        "h",
        "hh",
        "hpp",
        "m",
        "mm",
        "c",
        "cc",
        "cpp",
        "cxx",
        "pch",
        "modulemap",
        "metal",
        "swiftinterface",
        "swiftmodule",
        "swiftpm",
        "xcodeproj",
        "pbxproj",
        "xcscheme",
        "xcconfig",
        "plist",
        "resolved",
    ]
}

extension WorkspaceDidChangeWatchedFiles {
    struct Params: Decodable, Sendable {
        let changes: [ChangedFile]
    }
}

extension WorkspaceDidChangeWatchedFiles.Params {
    struct ChangedFile: Decodable, Sendable {
        let uri: String
        let type: Int
    }
}
