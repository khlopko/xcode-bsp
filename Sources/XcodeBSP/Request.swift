import Foundation

struct Request<Params>: Decodable where Params: Decodable {
    let id: String
    let method: String
    let params: Params
}

extension Request: CustomStringConvertible {
    var description: String {
        return "{\"id\":\"\(id)\",\"method\":\"\(method)\",\"params\":\"\(params)\"}"
    }
}
