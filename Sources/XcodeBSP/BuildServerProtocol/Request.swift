struct Request<Params> where Params: Decodable & Sendable {
    let id: String
    let method: String
    let params: Params
}

extension Request: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // latest sourcekit-lsp started to send string in "id",
        // while previous versions did send integer
        do {
            id = try container.decode(String.self, forKey: .id)
        } catch {
            id = try container.decode(Int.self, forKey: .id).description
        }

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
