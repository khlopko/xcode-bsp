import Foundation
import XCTest
@testable import XcodeBSP

final class BuildTargetSourcesTests: XCTestCase {
    func testReturnsEmptySourcesAndRootsForTargetWithoutKnownFiles() async throws {
        let graph = BuildGraphService(
            xcodebuild: StubXcodeBuildClient(
                listResult: XcodeBuild.List(
                    project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
                ),
                settingsForIndexByScheme: ["App": [:]]
            ),
            logger: makeTestLogger(),
            configProvider: StaticConfigProvider(config: makeSourcesConfig())
        )

        let targetsHandler = WorkspaceBuildTargets(graph: graph)
        let targetsResult = try await targetsHandler.handle(
            request: Request(id: "1", method: targetsHandler.method, params: EmptyParams()),
            decoder: JSONDecoder()
        )
        let target = try XCTUnwrap(targetsResult.targets.first)

        let handler = BuildTargetSources(graph: graph)
        let result = try await handler.handle(
            request: Request(
                id: "2",
                method: handler.method,
                params: BuildTargetSources.Params(targets: [target.id])
            ),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].sources.count, 0)
        XCTAssertEqual(result.items[0].roots.count, 0)
    }

    func testReturnsFileSourcesAndPerDirectoryRoots() async throws {
        let filePath = URL(filePath: "/tmp/Project/Sources/File.swift").standardizedFileURL.path()
        let graph = BuildGraphService(
            xcodebuild: StubXcodeBuildClient(
                listResult: XcodeBuild.List(
                    project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
                ),
                settingsForIndexByScheme: [
                    "App": [
                        "App": [
                            filePath: XcodeBuild.FileSettings(
                                swiftASTCommandArguments: ["swiftc", filePath],
                                clangASTCommandArguments: nil,
                                clangPCHCommandArguments: nil
                            )
                        ]
                    ]
                ]
            ),
            logger: makeTestLogger(),
            configProvider: StaticConfigProvider(config: makeSourcesConfig())
        )

        let targetsHandler = WorkspaceBuildTargets(graph: graph)
        let targetsResult = try await targetsHandler.handle(
            request: Request(id: "1", method: targetsHandler.method, params: EmptyParams()),
            decoder: JSONDecoder()
        )
        let target = try XCTUnwrap(targetsResult.targets.first)

        let handler = BuildTargetSources(graph: graph)
        let result = try await handler.handle(
            request: Request(
                id: "2",
                method: handler.method,
                params: BuildTargetSources.Params(targets: [target.id])
            ),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].sources.map(\.uri), [URL(filePath: filePath).absoluteString])
        XCTAssertEqual(
            result.items[0].roots,
            [URL(filePath: "/tmp/Project/Sources").appending(path: "/").absoluteString]
        )
    }
}

private func makeSourcesConfig() -> Config {
    return Config(
        name: "xcode-bsp",
        argv: ["/usr/local/bin/xcode-bsp"],
        version: "0.2.0",
        bspVersion: "2.0.0",
        languages: ["swift"],
        activeSchemes: ["App"]
    )
}
