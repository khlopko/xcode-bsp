import Foundation
import XCTest
@testable import XcodeBSP

final class ProtocolModelsTests: XCTestCase {
    func testRequestDecodesIntegerIDAsString() throws {
        let data = Data("{".utf8)
            + Data("\"id\":1,".utf8)
            + Data("\"method\":\"build/shutdown\",".utf8)
            + Data("\"params\":{}".utf8)
            + Data("}".utf8)

        let request = try JSONDecoder().decode(Request<EmptyParams>.self, from: data)

        XCTAssertEqual(request.id, "1")
        XCTAssertEqual(request.method, "build/shutdown")
    }

    func testJSONRPCMessageDetectsNotificationFromMissingID() throws {
        let data = Data("{".utf8)
            + Data("\"method\":\"build/initialized\"".utf8)
            + Data("}".utf8)

        let message = try JSONDecoder().decode(JSONRPCConnection.Message.self, from: data)

        XCTAssertTrue(message.isNotification)
        XCTAssertNil(message.id)
    }
}
