import Foundation

struct TextDocumentRegisterForChanges {
}

extension TextDocumentRegisterForChanges: MethodHandler {
    typealias Params = EmptyParams
    typealias Result = EmptyResult

    var method: String {
        return "textDocument/registerForChanges"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        return Result()
    }
}

