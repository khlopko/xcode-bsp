import Foundation
import Logging

struct BuildTargetSources {
    let xcodebuild: XcodeBuild
    let logger: Logger
}

extension BuildTargetSources: MethodHandler {
    var method: String {
        return "buildTarget/sources"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        var items: [Result.SourcesItem] = []
        for target in request.params.targets {
            let components = URLComponents(string: target.uri)
            guard
                let schemeItem = components?.queryItems?.first(where: { $0.name == "scheme" }),
                let scheme = schemeItem.value 
            else {
                logger.error("missing scheme in \(target.uri)")
                continue
            }

            guard let settings = try? xcodebuild.settingsForScheme(scheme).first(where: { $0.action == "build" }) else {
                continue
            }

            let item = Result.SourcesItem(
                target: TargetID(uri: target.uri),
                sources: [
                    Result.SourcesItem.SourceItem(
                        uri: "file://" + settings.buildSettings.SOURCE_ROOT + "/",
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

