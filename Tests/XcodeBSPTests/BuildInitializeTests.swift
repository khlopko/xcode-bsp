import Foundation
import XCTest
@testable import XcodeBSP

final class BuildInitializeTests: XCTestCase {
    func testHandleReturnsCapabilitiesWhenConfigLoads() throws {
        let config = Config(
            name: "xcode-bsp",
            argv: ["/usr/local/bin/xcode-bsp"],
            version: "0.1.0",
            bspVersion: "2.0.0",
            languages: ["swift"],
            activeSchemes: []
        )
        let handler = BuildInitialize(configProvider: StaticConfigProvider(config: config))

        let result = try handler.handle(
            request: Request(id: "1", method: handler.method, params: BuildInitialize.Params()),
            decoder: JSONDecoder()
        )

        XCTAssertEqual(result.displayName, "xcode-bsp")
        XCTAssertEqual(result.bspVersion, "2.0.0")
        XCTAssertEqual(result.dataKind, "sourceKit")
        XCTAssertEqual(result.capabilities.languageIds, ["swift", "objective-c", "objective-cpp", "c", "cpp"])
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
