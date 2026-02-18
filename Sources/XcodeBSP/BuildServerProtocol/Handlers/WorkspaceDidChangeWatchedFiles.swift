import Foundation
import Logging

struct WorkspaceDidChangeWatchedFiles {
    let logger: Logger
    let state: BuildSystemState
    let graph: BuildGraphService

    init(logger: Logger, state: BuildSystemState, graph: BuildGraphService) {
        self.logger = logger
        self.state = state
        self.graph = graph
    }
}

extension WorkspaceDidChangeWatchedFiles: NotificationMethodHandler {
    var method: String {
        return "workspace/didChangeWatchedFiles"
    }

    func handle(notification: Notification<Params>, decoder: JSONDecoder) async throws {
        await state.beginUpdate()
        do {
            let changedFilesCount = notification.params?.changes.count ?? 0
            logger.trace("workspace/didChangeWatchedFiles with \(changedFilesCount) changes")

            await graph.invalidate()
            let refresh = try await graph.refresh(decoder: decoder, checkCache: false)
            await state.recordRefreshChanges(refresh)
            await state.endUpdate()
        } catch {
            await state.endUpdate()
            throw error
        }
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
