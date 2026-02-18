import Foundation
import XCTest
@testable import XcodeBSP

final class BuildTargetPrepareTests: XCTestCase {
    func testPrepareStoresSanitizedArgumentsForScheme() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.swift").standardizedFileURL.path()
        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexByScheme: [
                "App": [
                    "App": [
                        filePath: XcodeBuild.FileSettings(
                            swiftASTCommandArguments: [
                                "swiftc",
                                "-use-frontend-parseable-output",
                                "-emit-localized-strings",
                                "-sdk",
                                "/definitely/missing/sdk",
                            ],
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
            configProvider: StaticConfigProvider(config: makeConfig(activeSchemes: ["App"]))
        )
        let db = InMemoryArgumentsStore()
        let handler = BuildTargetPrepare(
            graph: graph,
            db: db,
            logger: makeTestLogger(),
            state: BuildSystemState()
        )

        _ = try await handler.handle(
            request: Request(
                id: "1",
                method: handler.method,
                params: BuildTargetPrepare.Params(
                    targets: [TargetID(uri: "xcode://Project?scheme=App")]
                )
            ),
            decoder: JSONDecoder()
        )

        let stored = await db.args(filePath: filePath, scheme: "App")
        XCTAssertEqual(stored, ["swiftc"])
    }

    func testPrepareUsesSchemeTargetScopeWhenTargetIsPresent() async throws {
        let filePath = URL(filePath: "/tmp/Project/File.swift").standardizedFileURL.path()
        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
            ),
            settingsForIndexByScheme: [
                "App": [
                    "UnitTests": [
                        filePath: XcodeBuild.FileSettings(
                            swiftASTCommandArguments: ["swiftc"],
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
            configProvider: StaticConfigProvider(config: makeConfig(activeSchemes: ["App"]))
        )
        let db = InMemoryArgumentsStore()
        let handler = BuildTargetPrepare(
            graph: graph,
            db: db,
            logger: makeTestLogger(),
            state: BuildSystemState()
        )

        _ = try await handler.handle(
            request: Request(
                id: "1",
                method: handler.method,
                params: BuildTargetPrepare.Params(
                    targets: [TargetID(uri: "xcode://Project?scheme=App&target=UnitTests")]
                )
            ),
            decoder: JSONDecoder()
        )

        let stored = await db.args(filePath: filePath, scheme: "App::UnitTests")
        XCTAssertEqual(stored, ["swiftc"])
    }
}

private func makeConfig(activeSchemes: [String]) -> Config {
    return Config(
        name: "xcode-bsp",
        argv: ["/usr/local/bin/xcode-bsp"],
        version: "0.1.0",
        bspVersion: "2.0.0",
        languages: ["swift"],
        activeSchemes: activeSchemes
    )
}
