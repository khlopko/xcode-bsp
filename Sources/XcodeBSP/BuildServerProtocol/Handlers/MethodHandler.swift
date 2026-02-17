import Foundation

protocol MethodHandler: Sendable {
    associatedtype Params: Decodable & Sendable
    associatedtype Result: Encodable

    var method: String { get }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result
}

extension MethodHandler {
    func handle(data: Data, decoder: JSONDecoder) async throws -> Response<Result> {
        let request = try decoder.decode(Request<Params>.self, from: data)
        let result = try await handle(request: request, decoder: decoder)
        let response = Response(id: request.id, result: result)
        return response
    }
}

protocol NotificationMethodHandler: Sendable {
    associatedtype Params: Decodable & Sendable

    var method: String { get }

    func handle(notification: Notification<Params>, decoder: JSONDecoder) async throws
}

extension NotificationMethodHandler {
    func handle(data: Data, decoder: JSONDecoder) async throws {
        let notification = try decoder.decode(Notification<Params>.self, from: data)
        try await handle(notification: notification, decoder: decoder)
    }
}

struct EmptyParams: Decodable, Sendable {
}

struct EmptyResult: Encodable {
}

struct HandlersRegistry: Sendable {
    private let requestHandlersByMethod: [String: any MethodHandler]
    private let notificationHandlersByMethod: [String: any NotificationMethodHandler]

    init(
        requestHandlers: [any MethodHandler],
        notificationHandlers: [any NotificationMethodHandler] = []
    ) {
        var requestHandlersByMethod: [String: any MethodHandler] = [:]
        for handler in requestHandlers {
            assert(requestHandlersByMethod[handler.method] == nil, "duplicated request handler for \(handler.method)")
            requestHandlersByMethod[handler.method] = handler
        }

        var notificationHandlersByMethod: [String: any NotificationMethodHandler] = [:]
        for handler in notificationHandlers {
            assert(requestHandlersByMethod[handler.method] == nil, "handler for \(handler.method) cannot be both request and notification")
            assert(notificationHandlersByMethod[handler.method] == nil, "duplicated notification handler for \(handler.method)")
            notificationHandlersByMethod[handler.method] = handler
        }

        self.requestHandlersByMethod = requestHandlersByMethod
        self.notificationHandlersByMethod = notificationHandlersByMethod
    }

    func requestHandler(for message: JSONRPCConnection.Message) -> (any MethodHandler)? {
        return requestHandlersByMethod[message.method]
    }

    func notificationHandler(for message: JSONRPCConnection.Message) -> (any NotificationMethodHandler)? {
        return notificationHandlersByMethod[message.method]
    }
}
