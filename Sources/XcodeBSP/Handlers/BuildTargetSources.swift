import Foundation
import Logging

struct BuildTargetSources {
    let logger: Logger
}

extension BuildTargetSources: MethodHandler {
    var method: String {
        return "buildTarget/sources"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        var items: [Result.SourcesItem] = []
        for target in request.params.targets {
            guard let scheme = target.uri.split(separator: "://").last else {
                logger.error("invalid target id: \(target)")
                continue
            }

            let output = shell("xcodebuild -showBuildSettings -json")
            guard let outputData = output.text?.data(using: .utf8) else {
                logger.error("no scheme for target: \(target)")
                continue
            }

            do {
                let xcodeBuildSettings = try decoder.decode(
                    [XcodeBuildSettings].self, from: outputData)
                guard let xcodeTarget = xcodeBuildSettings.first(where: { $0.target == scheme })
                else {
                    logger.error("no settings for scheme: \(scheme)")
                    continue
                }

                let item = Result.SourcesItem(
                    target: TargetID(uri: target.uri),
                    sources: [
                        Result.SourcesItem.SourceItem(
                            uri: "file://" + xcodeTarget.buildSettings.SOURCE_ROOT + "/",
                            kind: .dir,
                            generated: false
                        )
                    ]
                )
                items.append(item)
            } catch {
                logger.error("settings decoding failed: \(error)")
                continue
            }
        }

        logger.debug("sources: \(items)")
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

