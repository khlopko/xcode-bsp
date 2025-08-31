import Foundation

struct Request<Params> where Params: Decodable & Sendable {
    let id: String
    let method: String
    let params: Params
}

extension Request: Decodable {
}

extension Request: Sendable {
}

extension Request: CustomStringConvertible {
    var description: String {
        return "{\"id\":\"\(id)\",\"method\":\"\(method)\",\"params\":\"\(params)\"}"
    }
}
