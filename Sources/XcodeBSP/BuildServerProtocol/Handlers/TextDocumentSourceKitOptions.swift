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

        let components = URLComponents(string: request.params.target.uri)
        if
            let scheme = components?.queryItems?.first(where: { $0.name == "scheme" })?.value,
            let filePath = URLComponents(string: request.params.textDocument.uri)?.path
        {
            let settings = try xcodebuild.settingsForScheme(scheme).first { $0.action == "build" }

            var arguments: [String]
            do {
                arguments = try await db.fetchArgs(filePath: filePath, scheme: scheme)
                logger.debug("loaded from db: \(arguments)")

                if hasMissingSDK(arguments: arguments) {
                    logger.debug("missing SDK in cached compiler arguments for scheme \(scheme), refreshing")

                    let refreshedByFilePath = compilerArgumentsByFilePath(forScheme: scheme, checkCache: false)
                    if refreshedByFilePath.isEmpty == false {
                        let sanitizedByFilePath = sanitizeMissingSDK(argumentsByFilePath: refreshedByFilePath)
                        try await db.updateArgs(argsByFilePaths: sanitizedByFilePath, scheme: scheme)
                        arguments = sanitizedByFilePath[filePath] ?? []
                    } else {
                        arguments = removeMissingSDK(arguments: arguments)
                    }
                }
            } catch is Database.NotFoundError {
                var argsByFilePaths = compilerArgumentsByFilePath(forScheme: scheme, checkCache: true)
                if hasMissingSDK(arguments: argsByFilePaths[filePath] ?? []) {
                    logger.debug("missing SDK in compiler arguments for scheme \(scheme), bypassing xcodebuild cache")

                    let refreshedByFilePath = compilerArgumentsByFilePath(forScheme: scheme, checkCache: false)
                    if refreshedByFilePath.isEmpty == false {
                        argsByFilePaths = refreshedByFilePath
                    }
                }

                argsByFilePaths = sanitizeMissingSDK(argumentsByFilePath: argsByFilePaths)
                try await db.updateArgs(argsByFilePaths: argsByFilePaths, scheme: scheme)

                arguments = argsByFilePaths[filePath] ?? []
            }

            result = Result(
                compilerArguments: arguments,
                workingDirectory: settings?.buildSettings.SOURCE_ROOT
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
    private func compilerArgumentsByFilePath(forScheme scheme: String, checkCache: Bool) -> [String: [String]] {
        var argsByFilePaths: [String: [String]] = [:]
        let settingsForIndex = try? xcodebuild.settingsForIndex(forScheme: scheme, checkCache: checkCache)
        for (key, value) in settingsForIndex?[scheme] ?? [:] {
            var arguments = value.swiftASTCommandArguments ?? []
            arguments.append(contentsOf: value.clangASTCommandArguments ?? [])
            arguments.append(contentsOf: value.clangPCHCommandArguments ?? [])
            arguments = arguments.filter { $0 != "-use-frontend-parseable-output" }

            for (i, arg) in arguments.enumerated().reversed() {
                if arg == "-emit-localized-strings-path" {
                    arguments.remove(at: i)
                    arguments.remove(at: i - 1)
                }
                if arg == "-emit-localized-strings" {
                    arguments.remove(at: i)
                }
            }
            argsByFilePaths[key] = arguments
        }

        return argsByFilePaths
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
