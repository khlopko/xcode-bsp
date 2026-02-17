import Foundation

struct BuildTargetSources {
}

extension BuildTargetSources: MethodHandler {
    var method: String {
        return "buildTarget/sources"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        var items: [Result.SourcesItem] = []
        let sourceRoot = FileManager.default.currentDirectoryPath
        for target in request.params.targets {
            let item = Result.SourcesItem(
                target: TargetID(uri: target.uri),
                sources: [
                    Result.SourcesItem.SourceItem(
                        uri: "file://" + sourceRoot + "/",
                        kind: .dir,
                        generated: false
                    )
                ]
            )
            items.append(item)
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
