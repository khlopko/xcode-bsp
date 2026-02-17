import Foundation
import Logging

struct WorkspaceDidChangeWatchedFiles {
    let logger: Logger
}

extension WorkspaceDidChangeWatchedFiles: NotificationMethodHandler {
    var method: String {
        return "workspace/didChangeWatchedFiles"
    }

    func handle(notification: Notification<Params>, decoder: JSONDecoder) async throws {
        let changedFilesCount = notification.params?.changes.count ?? 0
        logger.trace("workspace/didChangeWatchedFiles with \(changedFilesCount) changes")
    }
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
