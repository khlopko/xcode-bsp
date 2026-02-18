import Foundation

struct BuildTargetSources {
    let xcodebuild: any XcodeBuildClient

    init(xcodebuild: any XcodeBuildClient) {
        self.xcodebuild = xcodebuild
    }
}

extension BuildTargetSources: MethodHandler {
    var method: String {
        return "buildTarget/sources"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        var items: [Result.SourcesItem] = []
        let sourceRoot = URL(filePath: FileManager.default.currentDirectoryPath)

        for target in request.params.targets {
            let sourcePaths = sourcePaths(forTargetURI: target.uri)

            let sources: [Result.SourcesItem.SourceItem]
            if sourcePaths.isEmpty {
                sources = [
                    Result.SourcesItem.SourceItem(
                        uri: sourceRoot.appending(path: "/").absoluteString,
                        kind: .dir,
                        generated: false
                    )
                ]
            } else {
                sources = sourcePaths.map { filePath in
                    Result.SourcesItem.SourceItem(
                        uri: URL(filePath: filePath).absoluteString,
                        kind: .file,
                        generated: false
                    )
                }
            }

            let item = Result.SourcesItem(
                target: TargetID(uri: target.uri),
                sources: sources,
                roots: [sourceRoot.appending(path: "/").absoluteString]
            )
            items.append(item)
        }

        return Result(items: items)
    }
}

extension BuildTargetSources {
    private struct ParsedTarget {
        let scheme: String
        let target: String?
    }

    private func sourcePaths(forTargetURI targetURI: String) -> [String] {
        guard let parsed = parseTarget(fromURI: targetURI) else {
            return []
        }

        let settingsForIndex = (try? xcodebuild.settingsForIndex(forScheme: parsed.scheme, checkCache: true)) ?? [:]
        let fileSettings = fileSettingsByPath(from: settingsForIndex, scheme: parsed.scheme, target: parsed.target)

        return fileSettings
            .map { filePath, _ in normalizeFilePath(filePath) }
            .sorted()
    }

    private func parseTarget(fromURI uri: String) -> ParsedTarget? {
        guard let components = URLComponents(string: uri) else {
            return nil
        }

        guard let scheme = components.queryItems?.first(where: { $0.name == "scheme" })?.value else {
            return nil
        }

        let target = components.queryItems?.first(where: { $0.name == "target" })?.value
        return ParsedTarget(scheme: scheme, target: target)
    }

    private func fileSettingsByPath(
        from settingsForIndex: XcodeBuild.SettingsForIndex,
        scheme: String,
        target: String?
    ) -> [String: XcodeBuild.FileSettings] {
        var keyCandidates: [String] = []
        if let target, target.isEmpty == false {
            keyCandidates.append(target)
        }
        keyCandidates.append(scheme)

        for key in keyCandidates {
            if let exact = settingsForIndex[key], exact.isEmpty == false {
                return exact
            }
        }

        if settingsForIndex.count == 1, let single = settingsForIndex.values.first {
            return single
        }

        var merged: [String: XcodeBuild.FileSettings] = [:]
        for (_, value) in settingsForIndex {
            for (filePath, fileSettings) in value {
                merged[filePath] = fileSettings
            }
        }

        return merged
    }

    private func normalizeFilePath(_ path: String) -> String {
        return URL(filePath: path).standardizedFileURL.path()
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
