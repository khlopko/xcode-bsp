import Foundation
import Logging

struct WorkspaceBuildTargets {
    let logger: Logger
}

extension WorkspaceBuildTargets: MethodHandler {
    typealias Params = EmptyParams

    var method: String {
        return "workspace/buildTargets"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        var targets: [Result.Target] = []

        let output = shell("xcodebuild -showBuildSettings -json")
        if let outputData = output.text?.data(using: .utf8) {
            let xcodeBuildSettings = try decoder.decode([XcodeBuildSettings].self, from: outputData)
            // just taking first target with action: "build"
            if let buildableTarget = xcodeBuildSettings.first(where: { $0.action == "build" }) {
                let target = Result.Target(
                    id: TargetID(uri: "\(buildableTarget.buildSettings.PROJECT)://\(buildableTarget.target)"),
                    displayName: buildableTarget.target
                )
                targets.append(target)
            }
        }

        return Result(targets: targets)
    }
}

extension WorkspaceBuildTargets {
    struct Result: Encodable {
        let targets: [Target]
    }
}

extension WorkspaceBuildTargets.Result {
    struct Target: Encodable {
        let id: TargetID
        let displayName: String
        let tags: [String] = []
        let languageIds: [String] = ["swift", "objective-c", "objective-cpp", "c", "cpp"]
        let dependencies: [TargetID] = []
        let capabilities: Capabilities = Capabilities()
    }
}

extension WorkspaceBuildTargets.Result {
    struct Capabilities: Encodable {
    }
}

