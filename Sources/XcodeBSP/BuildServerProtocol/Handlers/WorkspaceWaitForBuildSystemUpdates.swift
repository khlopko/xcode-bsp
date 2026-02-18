import Foundation

struct WorkspaceWaitForBuildSystemUpdates {
    let state: BuildSystemState

    init(state: BuildSystemState) {
        self.state = state
    }
}

extension WorkspaceWaitForBuildSystemUpdates: MethodHandler {
    typealias Result = EmptyResult

    var method: String {
        return "workspace/waitForBuildSystemUpdates"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result {
        await state.waitForIdle()
        return Result()
    }
}

extension WorkspaceWaitForBuildSystemUpdates {
    struct Params: Decodable {
    }
}
