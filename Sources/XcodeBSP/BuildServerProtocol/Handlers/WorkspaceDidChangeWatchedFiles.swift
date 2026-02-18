import Foundation
import Logging

struct WorkspaceDidChangeWatchedFiles {
    let logger: Logger
    let state: BuildSystemState

    init(logger: Logger, state: BuildSystemState) {
        self.logger = logger
        self.state = state
    }
}

extension WorkspaceDidChangeWatchedFiles: NotificationMethodHandler {
    var method: String {
        return "workspace/didChangeWatchedFiles"
    }

    func handle(notification: Notification<Params>, decoder: JSONDecoder) async throws {
        await state.beginUpdate()
        let changedFilesCount = notification.params?.changes.count ?? 0
        logger.trace("workspace/didChangeWatchedFiles with \(changedFilesCount) changes")
        await state.endUpdate()
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
