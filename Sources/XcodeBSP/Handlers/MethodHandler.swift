import Foundation

protocol MethodHandler: Sendable {
    associatedtype Params: Decodable & Sendable
    associatedtype Result: Encodable

    var method: String { get }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result
}

extension MethodHandler {
    func handle(data: Data, decoder: JSONDecoder) throws -> Response<Result> {
        let request = try decoder.decode(Request<Params>.self, from: data)
        let result = try handle(request: request, decoder: decoder)
        let response = Response(id: request.id, result: result)
        return response
    }
}

struct EmptyParams: Decodable {
}

struct EmptyResult: Encodable {
}

struct HandlersRegistry: Sendable {
    private let handlersByMethod: [String: any MethodHandler]

    init(handlers: [any MethodHandler]) {
        var handlersByMethod: [String: any MethodHandler] = [:]
        for handler in handlers {
            assert(handlersByMethod[handler.method] == nil, "duplicated handler for \(handler.method)")
            handlersByMethod[handler.method] = handler
        }
        self.handlersByMethod = handlersByMethod
    }

    func handler(for message: JSONRPCConnection.Message) -> (any MethodHandler)? {
        return handlersByMethod[message.method]
    }
}

