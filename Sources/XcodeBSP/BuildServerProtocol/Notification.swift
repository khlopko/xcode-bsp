struct Notification<Params> where Params: Decodable & Sendable {
    let method: String
    let params: Params?
}

extension Notification: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(Params.self, forKey: .params)
    }

    private enum CodingKeys: CodingKey {
        case method
        case params
    }
}

extension Notification: Sendable {
}
