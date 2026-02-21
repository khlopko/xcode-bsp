import Foundation
import XCTest
@testable import XcodeBSP

final class TextDocumentSourceKitOptionsTests: XCTestCase {
    func testReturnsArgumentsAndWorkingDirectoryFromGraph() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.swift").standardizedFileURL.path()
        let expected = ["-working-directory", "/tmp/Project"]

        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexByScheme: [
                "App": [
                    "App": [
                        filePath: XcodeBuild.FileSettings(
                            swiftASTCommandArguments: ["swiftc"] + expected,
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
        let refreshTrigger = CountingRefreshTrigger()

        let handler = TextDocumentSourceKitOptions(
            graph: graph,
            logger: makeTestLogger(),
            refreshTrigger: refreshTrigger
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

    func testCacheMissSchedulesBackgroundRefreshAndReturnsEmpty() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.swift").standardizedFileURL.path()
        let refreshTrigger = CountingRefreshTrigger()

        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexBySchemeAndCache: [
                "App": [
                    true: [:],
                    false: [:],
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
            logger: makeTestLogger(),
            refreshTrigger: refreshTrigger
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

        XCTAssertEqual(result.compilerArguments, [])
        XCTAssertEqual(result.workingDirectory, nil)
        let reasons = await refreshTrigger.reasonsSnapshot()
        XCTAssertEqual(reasons.count, 1)
        XCTAssertTrue(reasons[0].contains("sourceKitOptions-miss"))
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
        let refreshTrigger = CountingRefreshTrigger()

        let handler = TextDocumentSourceKitOptions(
            graph: graph,
            logger: makeTestLogger(),
            refreshTrigger: refreshTrigger
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
        let reasons = await refreshTrigger.reasonsSnapshot()
        XCTAssertEqual(reasons.count, 1)
    }

    func testAcceptsMissingLanguageField() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.swift").standardizedFileURL.path()

        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexByScheme: [
                "App": [
                    "App": [
                        filePath: XcodeBuild.FileSettings(
                            swiftASTCommandArguments: ["swiftc", "-working-directory", "/tmp/Project"],
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
        let refreshTrigger = CountingRefreshTrigger()
        let handler = TextDocumentSourceKitOptions(
            graph: graph,
            logger: makeTestLogger(),
            refreshTrigger: refreshTrigger
        )

        let request = Request(
            id: "1",
            method: handler.method,
            params: TextDocumentSourceKitOptions.Params(
                language: nil,
                textDocument: TextDocumentSourceKitOptions.Params.TextDocument(uri: "file://\(filePath)"),
                target: TargetID(uri: "xcode://Project?scheme=App")
            )
        )

        let result = try await handler.handle(request: request, decoder: JSONDecoder())
        XCTAssertEqual(result.compilerArguments, ["-working-directory", "/tmp/Project"])
        let reasons = await refreshTrigger.reasonsSnapshot()
        XCTAssertEqual(reasons.count, 0)
    }

    func testStripsXcrunCompilerPrefixFromClangArguments() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.mm").standardizedFileURL.path()

        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexByScheme: [
                "App": [
                    "App": [
                        filePath: XcodeBuild.FileSettings(
                            swiftASTCommandArguments: nil,
                            clangASTCommandArguments: ["xcrun", "clang", "-x", "objective-c++", filePath],
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
        let refreshTrigger = CountingRefreshTrigger()
        let handler = TextDocumentSourceKitOptions(
            graph: graph,
            logger: makeTestLogger(),
            refreshTrigger: refreshTrigger
        )

        let result = try await handler.handle(
            request: Request(
                id: "1",
                method: handler.method,
                params: TextDocumentSourceKitOptions.Params(
                    language: "objective-cpp",
                    textDocument: TextDocumentSourceKitOptions.Params.TextDocument(uri: "file://\(filePath)"),
                    target: TargetID(uri: "xcode://Project?scheme=App")
                )
            ),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.compilerArguments, ["-x", "objective-c++", filePath])
        let reasons = await refreshTrigger.reasonsSnapshot()
        XCTAssertEqual(reasons.count, 0)
    }

    func testSchedulesRefreshWhenCachedArgsContainMissingModuleMap() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.m").standardizedFileURL.path()
        let missingModuleMapPath = "/tmp/Project/Derived/Generated.modulemap"

        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexByScheme: [
                "App": [
                    "App": [
                        filePath: XcodeBuild.FileSettings(
                            swiftASTCommandArguments: nil,
                            clangASTCommandArguments: [
                                "clang",
                                "-fmodule-map-file=\(missingModuleMapPath)",
                                "-x",
                                "objective-c",
                                filePath,
                            ],
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
        let refreshTrigger = CountingRefreshTrigger()
        let handler = TextDocumentSourceKitOptions(
            graph: graph,
            logger: makeTestLogger(),
            refreshTrigger: refreshTrigger
        )

        let result = try await handler.handle(
            request: Request(
                id: "1",
                method: handler.method,
                params: TextDocumentSourceKitOptions.Params(
                    language: "objective-c",
                    textDocument: TextDocumentSourceKitOptions.Params.TextDocument(uri: "file://\(filePath)"),
                    target: TargetID(uri: "xcode://Project?scheme=App")
                )
            ),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.compilerArguments, [])
        XCTAssertNil(result.workingDirectory)
        let reasons = await refreshTrigger.reasonsSnapshot()
        XCTAssertEqual(reasons.count, 1)
        XCTAssertTrue(reasons[0].contains("sourceKitOptions-stale-paths"))
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
