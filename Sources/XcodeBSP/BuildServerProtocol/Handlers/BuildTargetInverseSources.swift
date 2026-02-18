import Foundation

struct BuildTargetInverseSources {
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

extension BuildTargetInverseSources: MethodHandler {
    var method: String {
        return "buildTarget/inverseSources"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        guard let filePath = filePath(fromURI: request.params.textDocument.uri) else {
            return Result(targets: [])
        }

        let config = try configProvider.load(decoder: decoder)
        let schemes: [String]
        if config.activeSchemes.isEmpty {
            let list = try xcodebuild.list(checkCache: true)
            schemes = config.resolvedSchemes(from: list.project.schemes)
        } else {
            schemes = config.activeSchemes
        }

        let projectName = URL(filePath: FileManager.default.currentDirectoryPath).lastPathComponent
        let resolvedFilePath = URL(filePath: filePath).resolvingSymlinksInPath().path()

        var targetURIs: Set<String> = []
        for scheme in schemes {
            let settingsForIndex = (try? xcodebuild.settingsForIndex(forScheme: scheme, checkCache: true)) ?? [:]
            for (targetName, fileSettingsByPath) in settingsForIndex {
                if fileMatches(filePath: filePath, resolvedFilePath: resolvedFilePath, in: fileSettingsByPath) {
                    let normalizedTargetName: String?
                    if targetName == scheme {
                        normalizedTargetName = nil
                    } else {
                        normalizedTargetName = targetName
                    }

                    let targetID = makeTargetID(
                        projectName: projectName,
                        scheme: scheme,
                        target: normalizedTargetName
                    )
                    targetURIs.insert(targetID.uri)
                }
            }
        }

        let targets = targetURIs.sorted().map { TargetID(uri: $0) }
        return Result(targets: targets)
    }
}

extension BuildTargetInverseSources {
    private func fileMatches(
        filePath: String,
        resolvedFilePath: String,
        in fileSettingsByPath: [String: XcodeBuild.FileSettings]
    ) -> Bool {
        for (candidate, _) in fileSettingsByPath {
            let normalizedCandidate = normalizeFilePath(candidate)
            if normalizedCandidate == filePath {
                return true
            }

            let resolvedCandidate = URL(filePath: normalizedCandidate).resolvingSymlinksInPath().path()
            if resolvedCandidate == resolvedFilePath {
                return true
            }
        }

        return false
    }

    private func filePath(fromURI uri: String) -> String? {
        guard let url = URL(string: uri), url.isFileURL else {
            return nil
        }

        return normalizeFilePath(url.path())
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

    private func normalizeFilePath(_ path: String) -> String {
        return URL(filePath: path).standardizedFileURL.path()
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
