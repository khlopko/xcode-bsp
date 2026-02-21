import Foundation
import XCTest
@testable import XcodeBSP

final class ProtocolModelsTests: XCTestCase {
    func testRequestDecodesIntegerID() throws {
        let data = Data("{".utf8)
            + Data("\"id\":1,".utf8)
            + Data("\"method\":\"build/shutdown\",".utf8)
            + Data("\"params\":{}".utf8)
            + Data("}".utf8)

        let request = try JSONDecoder().decode(Request<EmptyParams>.self, from: data)

        XCTAssertEqual(request.id, .int(1))
        XCTAssertEqual(request.method, "build/shutdown")
    }

    func testResponseEncodesIntegerIDAsInteger() throws {
        let response = Response(id: .int(42), result: EmptyResult())
        let data = try JSONEncoder().encode(response)
        let payload = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(payload.contains("\"id\":42"))
    }

    func testResponseEncodesStringIDAsString() throws {
        let response = Response(id: .string("req-42"), result: EmptyResult())
        let data = try JSONEncoder().encode(response)
        let payload = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(payload.contains("\"id\":\"req-42\""))
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
