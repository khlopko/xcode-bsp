import Foundation
import Logging

struct WorkspaceBuildTargets {
    let xcodebuild: XcodeBuild
    let logger: Logger
}

extension WorkspaceBuildTargets: MethodHandler {
    typealias Params = EmptyParams

    var method: String {
        return "workspace/buildTargets"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        var targets: [Result.Target] = []

        let list = try xcodebuild.list()
        let config = try decoder.decode(Config.self, from: Data(contentsOf: Config.configURL()))
        for scheme in config.activeSchemes {
            // just taking first target with action: "build"
            guard let settings = try? xcodebuild.settingsForScheme(scheme).first(where: { $0.action == "build" }) else {
                continue
            }

            let target = Result.Target(
                id: TargetID(uri: "xcode://\(list.project.name)?scheme=\(scheme)&target=\(settings.target)"),
                displayName: settings.target
            )
            targets.append(target)
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

