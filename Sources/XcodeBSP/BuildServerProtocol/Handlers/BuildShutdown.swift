import Foundation

struct BuildShutdown {
}

extension BuildShutdown: MethodHandler {
    typealias Params = EmptyParams
    typealias Result = EmptyResult

    var method: String {
        return "build/shutdown"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        return Result()
    }
}

