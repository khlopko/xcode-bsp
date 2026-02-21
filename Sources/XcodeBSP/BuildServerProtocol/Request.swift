import Foundation

enum JSONRPCID: Sendable, Equatable {
    case string(String)
    case int(Int)
}

extension JSONRPCID: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        self = .int(try container.decode(Int.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        }
    }
}

extension JSONRPCID: CustomStringConvertible {
    var description: String {
        switch self {
        case let .string(value):
            return value
        case let .int(value):
            return String(value)
        }
    }
}

struct Request<Params> where Params: Decodable & Sendable {
    let id: JSONRPCID
    let method: String
    let params: Params
}

extension Request: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(JSONRPCID.self, forKey: .id)

        method = try container.decode(String.self, forKey: .method)
        params = try container.decode(Params.self, forKey: .params)
    }

    private enum CodingKeys: CodingKey {
        case id
        case method
        case params
    }
}

extension Request: Sendable {
}

extension Request: CustomStringConvertible {
    var description: String {
        return "{\"id\":\"\(id)\",\"method\":\"\(method)\",\"params\":\"\(params)\"}"
    }
}

extension Request {
    init(id: String, method: String, params: Params) {
        self.init(id: .string(id), method: method, params: params)
    }

    init(id: Int, method: String, params: Params) {
        self.init(id: .int(id), method: method, params: params)
    }
}
