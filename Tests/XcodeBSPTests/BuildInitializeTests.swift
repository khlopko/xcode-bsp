import Foundation
import XCTest
@testable import XcodeBSP

final class BuildInitializeTests: XCTestCase {
    func testHandleReturnsIndexPathsWhenBuildSettingsResolve() async throws {
        let config = Config(
            name: "xcode-bsp",
            argv: ["/usr/local/bin/xcode-bsp"],
            version: "0.2.0",
            bspVersion: "2.0.0",
            languages: ["swift"],
            activeSchemes: ["App"]
        )
        let buildRoot = "/tmp/DerivedData/Build/Products"
        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: ["App"], targets: [])
            ),
            settingsForSchemeByScheme: [
                "App": [
                    XcodeBuild.Settings(
                        target: "App",
                        action: "build",
                        buildSettings: XcodeBuild.Settings.BuildSettings(
                            BUILD_DIR: "/tmp/DerivedData/Build",
                            BUILD_ROOT: buildRoot,
                            PROJECT: "Project",
                            SOURCE_ROOT: "/tmp/Project",
                            TARGET_NAME: "App"
                        )
                    )
                ]
            ],
            settingsForIndexByScheme: [
                "App": [
                    "App": [
                        "/tmp/Project/File.swift": XcodeBuild.FileSettings(
                            swiftASTCommandArguments: ["swiftc", "-index-store-path", "/tmp/CustomIndex/DataStore"],
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
            configProvider: StaticConfigProvider(config: config)
        )
        let cacheDir = URL(filePath: "/tmp/xcode-bsp-tests")
        let handler = BuildInitialize(graph: graph, cacheDir: cacheDir)

        let result = try await handler.handle(
            request: Request(id: "1", method: handler.method, params: BuildInitialize.Params()),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.displayName, "xcode-bsp")
        XCTAssertEqual(result.bspVersion, "2.0.0")
        XCTAssertEqual(result.dataKind, "sourceKit")
        XCTAssertEqual(result.capabilities.languageIds, ["swift", "objective-c", "objective-cpp", "c", "cpp"])
        XCTAssertEqual(result.data?.indexStorePath, "/tmp/CustomIndex/DataStore")
        XCTAssertNotNil(result.data?.indexDatabasePath)
    }

    func testHandleReturnsNilIndexPathsWhenNoBuildSettingsFound() async throws {
        let config = Config(
            name: "xcode-bsp",
            argv: ["/usr/local/bin/xcode-bsp"],
            version: "0.2.0",
            bspVersion: "2.0.0",
            languages: ["swift"],
            activeSchemes: ["App"]
        )
        let graph = BuildGraphService(
            xcodebuild: StubXcodeBuildClient(
                listResult: XcodeBuild.List(
                    project: XcodeBuild.List.Project(name: "Project", schemes: ["App"], targets: [])
                )
            ),
            logger: makeTestLogger(),
            configProvider: StaticConfigProvider(config: config)
        )
        let handler = BuildInitialize(graph: graph, cacheDir: URL(filePath: "/tmp/xcode-bsp-tests"))

        let result = try await handler.handle(
            request: Request(id: "1", method: handler.method, params: BuildInitialize.Params()),
            decoder: JSONDecoder()
        )

        XCTAssertNil(result.data?.indexStorePath)
        XCTAssertNil(result.data?.indexDatabasePath)
    }

    func testHandleThrowsWhenConfigLoadingFails() async {
        let graph = BuildGraphService(
            xcodebuild: StubXcodeBuildClient(
                listResult: XcodeBuild.List(
                    project: XcodeBuild.List.Project(name: "Project", schemes: [], targets: [])
                )
            ),
            logger: makeTestLogger(),
            configProvider: FailingConfigProvider()
        )
        let handler = BuildInitialize(graph: graph, cacheDir: URL(filePath: "/tmp/xcode-bsp-tests"))

        await XCTAssertThrowsErrorAsync(
            try await handler.handle(
                request: Request(id: "1", method: handler.method, params: BuildInitialize.Params()),
                decoder: JSONDecoder()
            )
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
    }
}
