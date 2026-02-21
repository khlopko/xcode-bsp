import Foundation

struct BuildTargetSources {
    let graph: BuildGraphService

    init(graph: BuildGraphService) {
        self.graph = graph
    }
}

extension BuildTargetSources: MethodHandler {
    var method: String {
        return "buildTarget/sources"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result {
        let snapshot = try await graph.snapshot(decoder: decoder)

        var items: [Result.SourcesItem] = []

        for target in request.params.targets {
            let sourcePaths = snapshot.filesByTargetURI[target.uri] ?? []
            let sources = sourcePaths.map { filePath in
                Result.SourcesItem.SourceItem(
                    uri: URL(filePath: filePath).absoluteString,
                    kind: .file,
                    generated: false
                )
            }

            items.append(
                Result.SourcesItem(
                    target: TargetID(uri: target.uri),
                    sources: sources,
                    roots: roots(from: sourcePaths)
                )
            )
        }

        return Result(items: items)
    }
}

extension BuildTargetSources {
    struct Params: Decodable {
        let targets: [TargetID]
    }
}

extension BuildTargetSources {
    struct Result: Encodable {
        let items: [SourcesItem]
    }
}

extension BuildTargetSources.Result {
    struct SourcesItem: Encodable {
        let target: TargetID
        let sources: [SourceItem]
        let roots: [String]
    }
}

extension BuildTargetSources.Result.SourcesItem {
    struct SourceItem: Encodable {
        let uri: String
        let kind: Kind
        let generated: Bool
    }
}

extension BuildTargetSources.Result.SourcesItem.SourceItem {
    enum Kind: Int, Encodable {
        case file = 1
        case dir = 2
    }
}

extension BuildTargetSources {
    private func roots(from sourcePaths: [String]) -> [String] {
        guard sourcePaths.isEmpty == false else {
            return []
        }

        let directories = Set(sourcePaths.map { URL(filePath: $0).deletingLastPathComponent().path() })
        return directories
            .sorted()
            .map { URL(filePath: $0).appending(path: "/").absoluteString }
    }
}
