import Foundation

struct WorkspaceBuildTargets {
    let xcodebuild: any XcodeBuildClient
    let configProvider: any ConfigProvider

    init(
        xcodebuild: any XcodeBuildClient,
        configProvider: any ConfigProvider = FileConfigProvider()
    ) {
        self.xcodebuild = xcodebuild
        self.configProvider = configProvider
    }
}

extension WorkspaceBuildTargets: MethodHandler {
    typealias Params = EmptyParams

    var method: String {
        return "workspace/buildTargets"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        let config = try configProvider.load(decoder: decoder)

        let schemes: [String]
        if config.activeSchemes.isEmpty {
            let list = try xcodebuild.list(checkCache: true)
            schemes = config.resolvedSchemes(from: list.project.schemes)
        } else {
            schemes = config.activeSchemes
        }

        let projectName = URL(filePath: FileManager.default.currentDirectoryPath).lastPathComponent
        var targets: [Result.Target] = []

        for scheme in schemes {
            let settingsForIndex = (try? xcodebuild.settingsForIndex(forScheme: scheme, checkCache: true)) ?? [:]
            let nestedTargets = nestedTargets(from: settingsForIndex, scheme: scheme)
            let nestedIDs = nestedTargets.map { makeTargetID(projectName: projectName, scheme: scheme, target: $0) }

            targets.append(
                Result.Target(
                    id: makeTargetID(projectName: projectName, scheme: scheme, target: nil),
                    displayName: scheme,
                    dependencies: nestedIDs
                )
            )

            for nestedTarget in nestedTargets {
                targets.append(
                    Result.Target(
                        id: makeTargetID(projectName: projectName, scheme: scheme, target: nestedTarget),
                        displayName: "\(scheme) (\(nestedTarget))",
                        dependencies: []
                    )
                )
            }
        }

        return Result(targets: targets)
    }
}

extension WorkspaceBuildTargets {
    private func nestedTargets(from settingsForIndex: XcodeBuild.SettingsForIndex, scheme: String) -> [String] {
        return settingsForIndex
            .filter { key, value in
                return key != scheme && value.isEmpty == false
            }
            .map { key, _ in key }
            .sorted()
    }

    private func makeTargetID(projectName: String, scheme: String, target: String?) -> TargetID {
        var components = URLComponents()
        components.scheme = "xcode"
        components.host = projectName

        var queryItems = [URLQueryItem(name: "scheme", value: scheme)]
        if let target, target.isEmpty == false {
            queryItems.append(URLQueryItem(name: "target", value: target))
        }
        components.queryItems = queryItems

        let fallbackTarget = target.map { "&target=\($0)" } ?? ""
        let fallback = "xcode://\(projectName)?scheme=\(scheme)\(fallbackTarget)"
        return TargetID(uri: components.string ?? fallback)
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
        let dependencies: [TargetID]
        let capabilities: Capabilities = Capabilities()
    }
}

extension WorkspaceBuildTargets.Result {
    struct Capabilities: Encodable {
        let canCompile: Bool = true
        let canTest: Bool = false
        let canRun: Bool = false
        let canDebug: Bool = false
    }
}
