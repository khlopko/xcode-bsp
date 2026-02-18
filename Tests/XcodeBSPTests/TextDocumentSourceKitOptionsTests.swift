import Foundation
import XCTest
@testable import XcodeBSP

final class TextDocumentSourceKitOptionsTests: XCTestCase {
    func testReturnsArgumentsAndWorkingDirectoryFromGraph() async throws {
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
        let graph = BuildGraphService(
            xcodebuild: xcodebuild,
            logger: makeTestLogger(),
            configProvider: StaticConfigProvider(config: makeTextDocumentConfig())
        )

        let handler = TextDocumentSourceKitOptions(
            graph: graph,
            state: BuildSystemState(),
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
        XCTAssertEqual(result.workingDirectory, "/tmp/Project")
        XCTAssertEqual(xcodebuild.settingsForIndexCalls.first?.checkCache, true)
    }

    func testCacheMissRefreshesWithBypassCacheLookup() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.swift").standardizedFileURL.path()
        let refreshed = ["swiftc", "-working-directory", "/tmp/Project"]

        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexBySchemeAndCache: [
                "App": [
                    true: [:],
                    false: [
                        "App": [
                            filePath: XcodeBuild.FileSettings(
                                swiftASTCommandArguments: refreshed,
                                clangASTCommandArguments: nil,
                                clangPCHCommandArguments: nil
                            )
                        ]
                    ],
                ]
            ]
        )
        let graph = BuildGraphService(
            xcodebuild: xcodebuild,
            logger: makeTestLogger(),
            configProvider: StaticConfigProvider(config: makeTextDocumentConfig())
        )

        let handler = TextDocumentSourceKitOptions(
            graph: graph,
            state: BuildSystemState(),
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

    func testReturnsEmptyWhenFileIsUnknown() async throws {
        let filePath = URL(filePath: "/tmp/Project/Unknown.swift").standardizedFileURL.path()

        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexByScheme: ["App": [:]]
        )
        let graph = BuildGraphService(
            xcodebuild: xcodebuild,
            logger: makeTestLogger(),
            configProvider: StaticConfigProvider(config: makeTextDocumentConfig())
        )

        let handler = TextDocumentSourceKitOptions(
            graph: graph,
            state: BuildSystemState(),
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

        XCTAssertTrue(result.compilerArguments.isEmpty)
        XCTAssertNil(result.workingDirectory)
    }
}

private func makeTextDocumentConfig() -> Config {
    return Config(
        name: "xcode-bsp",
        argv: ["/usr/local/bin/xcode-bsp"],
        version: "0.2.0",
        bspVersion: "2.0.0",
        languages: ["swift"],
        activeSchemes: ["App"]
    )
}
