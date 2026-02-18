import Foundation

struct TextDocumentRegisterForChanges {
    let state: BuildSystemState

    init(state: BuildSystemState) {
        self.state = state
    }
}

extension TextDocumentRegisterForChanges: MethodHandler {
    typealias Result = EmptyResult

    var method: String {
        return "textDocument/registerForChanges"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result {
        await state.updateRegistration(action: request.params.action, uri: request.params.uri)
        return Result()
    }
}

extension TextDocumentRegisterForChanges {
    struct Params: Decodable {
        let action: String?
        let uri: String?
    }
}
