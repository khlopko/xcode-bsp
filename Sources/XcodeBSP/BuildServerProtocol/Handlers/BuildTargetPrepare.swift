import Foundation
import Logging

struct BuildTargetPrepare {
    let logger: Logger
}

extension BuildTargetPrepare: MethodHandler {
    typealias Result = EmptyResult

    var method: String {
        return "buildTarget/prepare"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        Task.detached {
            for target in request.params.targets {
                guard let scheme = target.uri.split(separator: "://").last else {
                    logger.error("failed to extract scheme: \(target.uri)")
                    continue
                }

                logger.trace("starting build for \(scheme)")
                let command = "xcodebuild -scheme \(scheme)"
                do {
                    try shell(command)
                    logger.trace("command=\(command) succeeded")
                } catch {
                    logger.error("\(error)")
                }
            }
        }

        return Result()
    }
}

extension BuildTargetPrepare {
    struct Params: Decodable {
        let targets: [TargetID]
    }
}
