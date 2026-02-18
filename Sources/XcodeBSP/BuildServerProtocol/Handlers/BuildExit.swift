import Foundation

struct BuildExit {
    let state: BuildSystemState

    init(state: BuildSystemState) {
        self.state = state
    }
}

extension BuildExit: NotificationMethodHandler {
    typealias Params = EmptyParams

    var method: String {
        return "build/exit"
    }

    func handle(notification: Notification<Params>, decoder: JSONDecoder) async throws {
        let exitCode = await state.hasReceivedShutdown() ? 0 : 1
        exit(Int32(exitCode))
    }
}
