import XCTest
@testable import XcodeBSP

final class XcodeBuildServerTests: XCTestCase {
    func testLegacySourceKitOptionsChangedFlagDefaultsToDisabled() {
        XCTAssertFalse(XcodeBuildServer.legacySourceKitOptionsChangedEnabled(environment: [:]))
    }

    func testLegacySourceKitOptionsChangedFlagParsesEnabledValues() {
        XCTAssertTrue(
            XcodeBuildServer.legacySourceKitOptionsChangedEnabled(
                environment: ["XCODE_BSP_ENABLE_LEGACY_SOURCEKITOPTIONS_CHANGED": "1"]
            )
        )
        XCTAssertTrue(
            XcodeBuildServer.legacySourceKitOptionsChangedEnabled(
                environment: ["XCODE_BSP_ENABLE_LEGACY_SOURCEKITOPTIONS_CHANGED": "true"]
            )
        )
    }
}
