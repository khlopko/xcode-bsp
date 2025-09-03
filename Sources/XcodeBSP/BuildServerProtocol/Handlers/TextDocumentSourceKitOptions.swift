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
            } catch {
                var argsByFilePaths: [String: [String]] = [:]
                let settingsForIndex = try? xcodebuild.settingsForIndex(forScheme: scheme)
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
