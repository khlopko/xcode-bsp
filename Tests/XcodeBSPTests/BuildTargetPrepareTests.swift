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
        XCTAssertEqual(stored, [])
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
        XCTAssertEqual(stored, [])
    }

    func testPrepareTriggersWarmupBuildWhenModuleMapPathIsMissing() async throws {
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
                            clangASTCommandArguments: ["clang", "-fmodule-map-file=\(missingModuleMapPath)", filePath],
                            clangPCHCommandArguments: nil
                        )
                    ],
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
        XCTAssertEqual(stored, ["-fmodule-map-file=\(missingModuleMapPath)", filePath])
        XCTAssertEqual(xcodebuild.warmupBuildCalls, ["App"])
        XCTAssertFalse(xcodebuild.settingsForIndexCalls.contains(where: { $0.checkCache == false }))
    }
}

private func makeConfig(activeSchemes: [String]) -> Config {
    return Config(
        name: "xcode-bsp",
        argv: ["/usr/local/bin/xcode-bsp"],
        version: "0.2.0",
        bspVersion: "2.0.0",
        languages: ["swift"],
        activeSchemes: activeSchemes
    )
}
