import Foundation

struct WorkspaceBuildTargets {
    let xcodebuild: XcodeBuild
}

extension WorkspaceBuildTargets: MethodHandler {
    typealias Params = EmptyParams

    var method: String {
        return "workspace/buildTargets"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        var targets: [Result.Target] = []

        let config = try decoder.decode(Config.self, from: Data(contentsOf: Config.configURL()))
        let schemes: [String]
        if config.activeSchemes.isEmpty {
            let list = try xcodebuild.list()
            schemes = list.project.schemes
        } else {
            schemes = config.activeSchemes
        }

        let projectName = URL(filePath: FileManager.default.currentDirectoryPath).lastPathComponent
        for scheme in schemes {
            var components = URLComponents()
            components.scheme = "xcode"
            components.host = projectName
            components.queryItems = [URLQueryItem(name: "scheme", value: scheme)]

            let target = Result.Target(
                id: TargetID(uri: components.string ?? "xcode://\(projectName)?scheme=\(scheme)"),
                displayName: scheme
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
