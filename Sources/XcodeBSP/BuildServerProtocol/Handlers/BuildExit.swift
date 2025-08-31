import Foundation

struct BuildExit {
}

extension BuildExit: MethodHandler {
    typealias Params = EmptyParams
    typealias Result = Never

    var method: String {
        return "build/exit"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        exit(0)
    }
}

