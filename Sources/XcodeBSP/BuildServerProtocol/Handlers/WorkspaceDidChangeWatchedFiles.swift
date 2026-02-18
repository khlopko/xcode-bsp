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
        let changes = notification.params?.changes ?? []
        guard Self.hasRelevantChanges(changes) else {
            logger.debug("workspace/didChangeWatchedFiles ignored \(changes.count) non-source changes")
            return
        }

        await state.beginUpdate()
        do {
            let changedFilesCount = changes.count
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
    static func hasRelevantChanges(_ changes: [Params.ChangedFile]) -> Bool {
        return changes.contains { isRelevant(change: $0) }
    }

    private static func isRelevant(change: Params.ChangedFile) -> Bool {
        guard let url = URL(string: change.uri), url.isFileURL else {
            return true
        }

        let path = url.standardizedFileURL.path().lowercased()
        if path.contains("/.build/") || path.contains("/deriveddata/") || path.contains("/modulecache/") || path.contains("/index.noindex/") {
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
