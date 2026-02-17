import Foundation
import XCTest
@testable import XcodeBSP

final class WorkspaceBuildTargetsTests: XCTestCase {
    func testUsesActiveSchemesFromConfigWithoutCallingXcodebuildList() throws {
        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: ["Ignored"], targets: [])
            )
        )
        let config = Config(
            name: "xcode-bsp",
            argv: ["/usr/local/bin/xcode-bsp"],
            version: "0.1.0",
            bspVersion: "2.0.0",
            languages: ["swift"],
            activeSchemes: ["App", "Library"]
        )
        let handler = WorkspaceBuildTargets(
            xcodebuild: xcodebuild,
            configProvider: StaticConfigProvider(config: config)
        )

        let result = try handler.handle(
            request: Request(id: "1", method: handler.method, params: EmptyParams()),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.targets.map(\.displayName), ["App", "Library"])
        XCTAssertEqual(xcodebuild.listCallCount, 0)
    }

    func testFallsBackToXcodebuildListWhenNoActiveSchemes() throws {
        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: ["App", "Library"], targets: [])
            )
        )
        let config = Config(
            name: "xcode-bsp",
            argv: ["/usr/local/bin/xcode-bsp"],
            version: "0.1.0",
            bspVersion: "2.0.0",
            languages: ["swift"],
            activeSchemes: []
        )
        let handler = WorkspaceBuildTargets(
            xcodebuild: xcodebuild,
            configProvider: StaticConfigProvider(config: config)
        )

        let result = try handler.handle(
            request: Request(id: "1", method: handler.method, params: EmptyParams()),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.targets.map(\.displayName), ["App", "Library"])
        XCTAssertEqual(xcodebuild.listCallCount, 1)
    }
}
