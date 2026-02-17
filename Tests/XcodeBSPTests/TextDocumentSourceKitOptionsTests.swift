import Foundation
import XCTest
@testable import XcodeBSP

final class TextDocumentSourceKitOptionsTests: XCTestCase {
    func testReturnsCachedArgumentsAndWorkingDirectory() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.swift").standardizedFileURL.path()
        let arguments = ["swiftc", "-working-directory", "/tmp/Project"]

        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            )
        )
        let db = InMemoryArgumentsStore()
        await db.seed(filePath: filePath, scheme: "App", arguments: arguments)

        let handler = TextDocumentSourceKitOptions(
            xcodebuild: xcodebuild,
            db: db,
            logger: makeTestLogger()
        )

        let result = try await handler.handle(
            request: Request(
                id: "1",
                method: handler.method,
                params: TextDocumentSourceKitOptions.Params(
                    language: "swift",
                    textDocument: TextDocumentSourceKitOptions.Params.TextDocument(uri: "file://\(filePath)"),
                    target: TargetID(uri: "xcode://Project?scheme=App")
                )
            ),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.compilerArguments, arguments)
        XCTAssertEqual(result.workingDirectory, "/tmp/Project")
        XCTAssertTrue(xcodebuild.settingsForIndexCalls.isEmpty)
    }

    func testCacheMissLoadsFromXcodebuildAndPersistsArguments() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.swift").standardizedFileURL.path()
        let expected = ["swiftc", "-working-directory", "/tmp/Project"]

        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexByScheme: [
                "App": [
                    "App": [
                        filePath: XcodeBuild.FileSettings(
                            swiftASTCommandArguments: expected,
                            clangASTCommandArguments: nil,
                            clangPCHCommandArguments: nil
                        )
                    ]
                ]
            ]
        )
        let db = InMemoryArgumentsStore()

        let handler = TextDocumentSourceKitOptions(
            xcodebuild: xcodebuild,
            db: db,
            logger: makeTestLogger()
        )

        let result = try await handler.handle(
            request: Request(
                id: "1",
                method: handler.method,
                params: TextDocumentSourceKitOptions.Params(
                    language: "swift",
                    textDocument: TextDocumentSourceKitOptions.Params.TextDocument(uri: "file://\(filePath)"),
                    target: TargetID(uri: "xcode://Project?scheme=App")
                )
            ),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.compilerArguments, expected)
        let stored = await db.args(filePath: filePath, scheme: "App")
        XCTAssertEqual(stored, expected)
        XCTAssertEqual(xcodebuild.settingsForIndexCalls.first?.checkCache, true)
    }

    func testMissingSDKInCacheRefreshesWithBypassCacheLookup() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.swift").standardizedFileURL.path()
        let cached = ["swiftc", "-sdk", "/definitely/missing/sdk"]
        let refreshed = ["swiftc", "-working-directory", "/tmp/Project"]

        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexByScheme: [
                "App": [
                    "App": [
                        filePath: XcodeBuild.FileSettings(
                            swiftASTCommandArguments: refreshed,
                            clangASTCommandArguments: nil,
                            clangPCHCommandArguments: nil
                        )
                    ]
                ]
            ]
        )
        let db = InMemoryArgumentsStore()
        await db.seed(filePath: filePath, scheme: "App", arguments: cached)

        let handler = TextDocumentSourceKitOptions(
            xcodebuild: xcodebuild,
            db: db,
            logger: makeTestLogger()
        )

        let result = try await handler.handle(
            request: Request(
                id: "1",
                method: handler.method,
                params: TextDocumentSourceKitOptions.Params(
                    language: "swift",
                    textDocument: TextDocumentSourceKitOptions.Params.TextDocument(uri: "file://\(filePath)"),
                    target: TargetID(uri: "xcode://Project?scheme=App")
                )
            ),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.compilerArguments, refreshed)
        XCTAssertTrue(xcodebuild.settingsForIndexCalls.contains(where: { $0.checkCache == false }))
    }
}
