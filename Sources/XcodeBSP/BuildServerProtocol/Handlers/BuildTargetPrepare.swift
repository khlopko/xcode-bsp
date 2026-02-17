import Foundation
import Logging

struct BuildTargetPrepare {
    let xcodebuild: any XcodeBuildClient
    let db: any ArgumentsStore
    let logger: Logger
}

extension BuildTargetPrepare: MethodHandler {
    typealias Result = EmptyResult

    var method: String {
        return "buildTarget/prepare"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result {
        await prepareTargets(request.params.targets)
        return Result()
    }
}

extension BuildTargetPrepare {
    private struct PreparedTarget {
        let scheme: String
        let target: String?
    }

    private func prepareTargets(_ targets: [TargetID]) async {
        for target in targets {
            guard let preparedTarget = parseTarget(fromURI: target.uri) else {
                logger.error("failed to extract scheme from target uri: \(target.uri)")
                continue
            }

            do {
                var argsByFilePaths = compilerArgumentsByFilePath(
                    forScheme: preparedTarget.scheme,
                    target: preparedTarget.target,
                    checkCache: true
                )
                if argsByFilePaths.isEmpty {
                    argsByFilePaths = compilerArgumentsByFilePath(
                        forScheme: preparedTarget.scheme,
                        target: preparedTarget.target,
                        checkCache: false
                    )
                }

                if argsByFilePaths.isEmpty {
                    logger.debug("buildTarget/prepare produced no compiler arguments for \(target.uri)")
                    continue
                }

                let sanitizedArgsByFilePath = sanitizeMissingSDK(argumentsByFilePath: argsByFilePaths)
                try await db.updateArgs(
                    argsByFilePaths: sanitizedArgsByFilePath,
                    scheme: cacheScope(scheme: preparedTarget.scheme, target: preparedTarget.target)
                )
                logger.debug("buildTarget/prepare cached compiler arguments for \(target.uri)")
            } catch {
                logger.error("buildTarget/prepare failed for \(target.uri): \(error)")
            }
        }
    }

    private func parseTarget(fromURI uri: String) -> PreparedTarget? {
        guard let components = URLComponents(string: uri) else {
            return nil
        }

        guard let scheme = components.queryItems?.first(where: { $0.name == "scheme" })?.value else {
            return nil
        }

        let target = components.queryItems?.first(where: { $0.name == "target" })?.value
        return PreparedTarget(scheme: scheme, target: target)
    }

    private func compilerArgumentsByFilePath(
        forScheme scheme: String,
        target: String?,
        checkCache: Bool
    ) -> [String: [String]] {
        var argsByFilePaths: [String: [String]] = [:]
        let settingsForIndex = try? xcodebuild.settingsForIndex(forScheme: scheme, checkCache: checkCache)
        let fileSettingsByPath = fileSettingsByPath(
            from: settingsForIndex ?? [:],
            scheme: scheme,
            target: target
        )

        for (path, value) in fileSettingsByPath {
            let normalizedPath = normalizeFilePath(path)
            var arguments = value.swiftASTCommandArguments ?? []
            arguments.append(contentsOf: value.clangASTCommandArguments ?? [])
            arguments.append(contentsOf: value.clangPCHCommandArguments ?? [])

            arguments = arguments.filter { $0 != "-use-frontend-parseable-output" }
            for (i, arg) in arguments.enumerated().reversed() {
                if arg == "-emit-localized-strings-path", i > 0 {
                    arguments.remove(at: i)
                    arguments.remove(at: i - 1)
                } else if arg == "-emit-localized-strings" {
                    arguments.remove(at: i)
                }
            }

            argsByFilePaths[normalizedPath] = arguments
        }

        return argsByFilePaths
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

    private func sanitizeMissingSDK(argumentsByFilePath: [String: [String]]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (filePath, arguments) in argumentsByFilePath {
            result[filePath] = removeMissingSDK(arguments: arguments)
        }
        return result
    }

    private func removeMissingSDK(arguments: [String]) -> [String] {
        var sanitizedArguments = arguments
        for (i, arg) in arguments.enumerated().reversed() {
            guard arg == "-sdk", i + 1 < arguments.count else {
                continue
            }

            let path = arguments[i + 1]
            if FileManager.default.fileExists(atPath: path) == false {
                sanitizedArguments.remove(at: i + 1)
                sanitizedArguments.remove(at: i)
            }
        }

        return sanitizedArguments
    }

    private func normalizeFilePath(_ path: String) -> String {
        return URL(filePath: path).standardizedFileURL.path()
    }

    private func cacheScope(scheme: String, target: String?) -> String {
        guard let target, target.isEmpty == false else {
            return scheme
        }

        return "\(scheme)::\(target)"
    }
}

extension BuildTargetPrepare {
    struct Params: Decodable {
        let targets: [TargetID]
    }
}
