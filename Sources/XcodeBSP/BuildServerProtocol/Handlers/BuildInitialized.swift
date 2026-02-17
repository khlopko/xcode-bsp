import Foundation

struct BuildInitialized {
}

extension BuildInitialized: NotificationMethodHandler {
    typealias Params = EmptyParams

    var method: String {
        return "build/initialized"
    }

    func handle(notification: Notification<Params>, decoder: JSONDecoder) async throws {
    }
}
