import Foundation
import XCTest
@testable import XcodeBSP

final class BuildTargetInverseSourcesTests: XCTestCase {
    func testReturnsTargetsContainingFile() throws {
        let filePath = URL(filePath: "/tmp/Project/File.swift").standardizedFileURL.path()
        let xcodebuild = StubXcodeBuildClient(
            listResult: XcodeBuild.List(
                project: XcodeBuild.List.Project(name: "Project", schemes: ["App"], targets: [])
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
        let config = Config(
            name: "xcode-bsp",
            argv: ["/usr/local/bin/xcode-bsp"],
            version: "0.1.0",
            bspVersion: "2.0.0",
            languages: ["swift"],
            activeSchemes: ["App"]
        )
        let handler = BuildTargetInverseSources(
            xcodebuild: xcodebuild,
            configProvider: StaticConfigProvider(config: config)
        )

        let result = try handler.handle(
            request: Request(
                id: "1",
                method: handler.method,
                params: BuildTargetInverseSources.Params(
                    textDocument: BuildTargetInverseSources.Params.TextDocument(uri: "file://\(filePath)")
                )
            ),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.targets.count, 1)
        XCTAssertEqual(result.targets.first?.uri.contains("scheme=App"), true)
        XCTAssertEqual(result.targets.first?.uri.contains("target=UnitTests"), true)
    }

    func testReturnsEmptyForNonFileURI() throws {
        let handler = BuildTargetInverseSources(
            xcodebuild: StubXcodeBuildClient(
                listResult: XcodeBuild.List(
                    project: XcodeBuild.List.Project(name: "Project", schemes: ["App"], targets: [])
                )
            ),
            configProvider: StaticConfigProvider(
                config: Config(
                    name: "xcode-bsp",
                    argv: ["/usr/local/bin/xcode-bsp"],
                    version: "0.1.0",
                    bspVersion: "2.0.0",
                    languages: ["swift"],
                    activeSchemes: ["App"]
                )
            )
        )

        let result = try handler.handle(
            request: Request(
                id: "1",
                method: handler.method,
                params: BuildTargetInverseSources.Params(
                    textDocument: BuildTargetInverseSources.Params.TextDocument(uri: "https://example.com/file.swift")
                )
            ),
            decoder: JSONDecoder()
        )

        XCTAssertTrue(result.targets.isEmpty)
    }
}
