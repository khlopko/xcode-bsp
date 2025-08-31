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

                logger.debug("starting build for \(scheme)")
                let command = "xcodebuild -scheme \(scheme)"
                let output = shell(command)
                guard output.exitCode == 0 else {
                    logger.error(
                        "command=\(command) failed with code=\(output.exitCode) and output=\(output.text ?? "")"
                    )
                    continue
                }

                logger.debug("command=\(command) succeeded")
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
