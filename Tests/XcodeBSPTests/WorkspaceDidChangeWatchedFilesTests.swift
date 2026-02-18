import XCTest
@testable import XcodeBSP

final class WorkspaceDidChangeWatchedFilesTests: XCTestCase {
    func testHasRelevantChangesReturnsFalseForBuildArtifacts() {
        let changes = [
            WorkspaceDidChangeWatchedFiles.Params.ChangedFile(
                uri: "file:///tmp/project/.build/index-build/arm64-apple-macosx/debug/Foo.build/output-file-map.json",
                type: 1
            ),
            WorkspaceDidChangeWatchedFiles.Params.ChangedFile(
                uri: "file:///Users/me/Library/Developer/Xcode/DerivedData/App/ModuleCache/nope.pcm.timestamp",
                type: 2
            ),
        ]

        XCTAssertFalse(WorkspaceDidChangeWatchedFiles.hasRelevantChanges(changes))
    }

    func testHasRelevantChangesReturnsTrueForSwiftSources() {
        let changes = [
            WorkspaceDidChangeWatchedFiles.Params.ChangedFile(
                uri: "file:///tmp/project/Dependencies/Lib/Sources/Thing.swift",
                type: 1
            ),
        ]

        XCTAssertTrue(WorkspaceDidChangeWatchedFiles.hasRelevantChanges(changes))
    }
}
