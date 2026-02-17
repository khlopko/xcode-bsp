import Foundation
import Logging

struct TextDocumentSourceKitOptions {
    let xcodebuild: XcodeBuild
    let db: Database
    let logger: Logger
}

extension TextDocumentSourceKitOptions: MethodHandler {
    var method: String {
        return "textDocument/sourceKitOptions"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result {
        let result: Result

        let targetComponents = URLComponents(string: request.params.target.uri)
        if
            let scheme = targetComponents?.queryItems?.first(where: { $0.name == "scheme" })?.value,
            let filePath = filePath(fromDocumentURI: request.params.textDocument.uri)
        {
            let target = targetComponents?.queryItems?.first(where: { $0.name == "target" })?.value
            let cacheScope = cacheScope(scheme: scheme, target: target)

            var arguments: [String]
            do {
                arguments = try await db.fetchArgs(filePath: filePath, scheme: cacheScope)

                if hasMissingSDK(arguments: arguments) {
                    logger.debug("missing SDK in cached compiler arguments for \(cacheScope), refreshing")

                    let refreshedByFilePath = compilerArgumentsByFilePath(
                        forScheme: scheme,
                        target: target,
                        checkCache: false
                    )
                    if refreshedByFilePath.isEmpty == false {
                        let sanitizedByFilePath = sanitizeMissingSDK(argumentsByFilePath: refreshedByFilePath)
                        try await db.updateArgs(argsByFilePaths: sanitizedByFilePath, scheme: cacheScope)
                        arguments = compilerArguments(forFilePath: filePath, byFilePath: sanitizedByFilePath)
                    } else {
                        arguments = removeMissingSDK(arguments: arguments)
                    }
                }
            } catch is Database.NotFoundError {
                var argsByFilePaths = compilerArgumentsByFilePath(
                    forScheme: scheme,
                    target: target,
                    checkCache: true
                )
                if hasMissingSDK(arguments: compilerArguments(forFilePath: filePath, byFilePath: argsByFilePaths)) {
                    logger.debug("missing SDK in compiler arguments for \(cacheScope), bypassing xcodebuild cache")

                    let refreshedByFilePath = compilerArgumentsByFilePath(
                        forScheme: scheme,
                        target: target,
                        checkCache: false
                    )
                    if refreshedByFilePath.isEmpty == false {
                        argsByFilePaths = refreshedByFilePath
                    }
                }

                argsByFilePaths = sanitizeMissingSDK(argumentsByFilePath: argsByFilePaths)
                try await db.updateArgs(argsByFilePaths: argsByFilePaths, scheme: cacheScope)

                arguments = compilerArguments(forFilePath: filePath, byFilePath: argsByFilePaths)
            }

            result = Result(
                compilerArguments: arguments,
                workingDirectory: workingDirectory(arguments: arguments)
            )
        } else {
            result = Result(compilerArguments: [], workingDirectory: nil)
        }

        return result
    }
}

extension TextDocumentSourceKitOptions {
    struct Params: Decodable {
        let language: String
        let textDocument: TextDocument
        let target: TargetID
    }
}

extension TextDocumentSourceKitOptions.Params {
    struct TextDocument: Decodable {
        let uri: String
    }
}

extension TextDocumentSourceKitOptions {
    struct Result: Encodable {
        let compilerArguments: [String]
        let workingDirectory: String?
    }
}

extension TextDocumentSourceKitOptions {
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

    private func compilerArguments(forFilePath filePath: String, byFilePath: [String: [String]]) -> [String] {
        let normalized = normalizeFilePath(filePath)
        if let exact = byFilePath[normalized] {
            return exact
        }

        let resolved = URL(filePath: normalized).resolvingSymlinksInPath().path()
        if let symlinkResolved = byFilePath[resolved] {
            return symlinkResolved
        }

        return []
    }

    private func filePath(fromDocumentURI documentURI: String) -> String? {
        guard let url = URL(string: documentURI), url.isFileURL else {
            return nil
        }

        return normalizeFilePath(url.path())
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

    private func workingDirectory(arguments: [String]) -> String? {
        for (i, arg) in arguments.enumerated() {
            if arg == "-working-directory", i + 1 < arguments.count {
                return arguments[i + 1]
            }

            if arg.hasPrefix("-working-directory=") {
                return String(arg.dropFirst("-working-directory=".count))
            }
        }

        return nil
    }

    private func sanitizeMissingSDK(argumentsByFilePath: [String: [String]]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (filePath, arguments) in argumentsByFilePath {
            result[filePath] = removeMissingSDK(arguments: arguments)
        }
        return result
    }

    private func hasMissingSDK(arguments: [String]) -> Bool {
        guard let sdkPath = sdkPath(arguments: arguments) else {
            return false
        }

        return FileManager.default.fileExists(atPath: sdkPath) == false
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

    private func sdkPath(arguments: [String]) -> String? {
        for (i, arg) in arguments.enumerated() {
            guard arg == "-sdk", i + 1 < arguments.count else {
                continue
            }

            return arguments[i + 1]
        }

        return nil
    }
}
