import Foundation
import XCTest
@testable import XcodeBSP

final class BuildInitializeTests: XCTestCase {
    func testHandleReturnsIndexPathsWhenBuildSettingsResolve() throws {
        let config = Config(
            name: "xcode-bsp",
            argv: ["/usr/local/bin/xcode-bsp"],
            version: "0.1.0",
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
            ]
        )
        let cacheDir = URL(filePath: "/tmp/xcode-bsp-tests")
        let handler = BuildInitialize(
            xcodebuild: xcodebuild,
            cacheDir: cacheDir,
            logger: makeTestLogger(),
            configProvider: StaticConfigProvider(config: config)
        )

        let result = try handler.handle(
            request: Request(id: "1", method: handler.method, params: BuildInitialize.Params()),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.displayName, "xcode-bsp")
        XCTAssertEqual(result.bspVersion, "2.0.0")
        XCTAssertEqual(result.dataKind, "sourceKit")
        XCTAssertEqual(result.capabilities.languageIds, ["swift", "objective-c", "objective-cpp", "c", "cpp"])
        XCTAssertEqual(result.capabilities.inverseSourcesProvider, true)
        XCTAssertEqual(result.data?.indexStorePath, "/tmp/DerivedData/Index.noindex/DataStore")
        XCTAssertNotNil(result.data?.indexDatabasePath)
        XCTAssertEqual(result.data?.prepareProvider, true)
        XCTAssertEqual(result.data?.sourceKitOptionsProvider, true)
        XCTAssertEqual(result.data?.waitForBuildSystemUpdatesProvider, true)
        XCTAssertTrue((result.data?.watches.isEmpty) == false)
    }

    func testHandleReturnsNilIndexPathsWhenNoBuildSettingsFound() throws {
        let config = Config(
            name: "xcode-bsp",
            argv: ["/usr/local/bin/xcode-bsp"],
            version: "0.1.0",
            bspVersion: "2.0.0",
            languages: ["swift"],
            activeSchemes: ["App"]
        )
        let handler = BuildInitialize(
            xcodebuild: StubXcodeBuildClient(
                listResult: XcodeBuild.List(
                    project: XcodeBuild.List.Project(name: "Project", schemes: ["App"], targets: [])
                )
            ),
            cacheDir: URL(filePath: "/tmp/xcode-bsp-tests"),
            logger: makeTestLogger(),
            configProvider: StaticConfigProvider(config: config)
        )

        let result = try handler.handle(
            request: Request(id: "1", method: handler.method, params: BuildInitialize.Params()),
            decoder: JSONDecoder()
        )

        XCTAssertNil(result.data?.indexStorePath)
        XCTAssertNil(result.data?.indexDatabasePath)
    }

    func testHandleThrowsWhenConfigLoadingFails() {
        let handler = BuildInitialize(configProvider: FailingConfigProvider())

        XCTAssertThrowsError(
            try handler.handle(
                request: Request(id: "1", method: handler.method, params: BuildInitialize.Params()),
                decoder: JSONDecoder()
            )
        )
    }
}
