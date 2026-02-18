import Foundation

struct WorkspaceBuildTargets {
    let graph: BuildGraphService

    init(graph: BuildGraphService) {
        self.graph = graph
    }
}

extension WorkspaceBuildTargets: MethodHandler {
    typealias Params = EmptyParams

    var method: String {
        return "workspace/buildTargets"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result {
        let snapshot = try await graph.snapshot(decoder: decoder)

        let targets = snapshot.targets.map { target in
            Result.Target(
                id: TargetID(uri: target.uri),
                displayName: target.displayName,
                dependencies: target.dependencies.map { TargetID(uri: $0) }
            )
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
