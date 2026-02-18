import Foundation

struct BuildTargetInverseSources {
    let graph: BuildGraphService

    init(graph: BuildGraphService) {
        self.graph = graph
    }
}

extension BuildTargetInverseSources: MethodHandler {
    var method: String {
        return "buildTarget/inverseSources"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result {
        guard let filePath = filePath(fromURI: request.params.textDocument.uri) else {
            return Result(targets: [])
        }

        let snapshot = try await graph.snapshot(decoder: decoder)
        let resolved = URL(filePath: filePath).resolvingSymlinksInPath().path()

        let targets = snapshot.targetsByFilePath[filePath]
            ?? snapshot.targetsByFilePath[resolved]
            ?? []

        return Result(targets: targets.map { TargetID(uri: $0) })
    }
}

extension BuildTargetInverseSources {
    private func filePath(fromURI uri: String) -> String? {
        guard let url = URL(string: uri), url.isFileURL else {
            return nil
        }

        return URL(filePath: url.path()).standardizedFileURL.path()
    }
}

extension BuildTargetInverseSources {
    struct Params: Decodable {
        let textDocument: TextDocument
    }
}

extension BuildTargetInverseSources.Params {
    struct TextDocument: Decodable {
        let uri: String
    }
}

extension BuildTargetInverseSources {
    struct Result: Encodable {
        let targets: [TargetID]
    }
}
