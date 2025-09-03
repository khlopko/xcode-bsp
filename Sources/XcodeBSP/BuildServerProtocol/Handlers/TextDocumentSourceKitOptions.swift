import Foundation
import Logging

struct TextDocumentSourceKitOptions {
    let xcodebuild: XcodeBuild
    let logger: Logger
}

extension TextDocumentSourceKitOptions: MethodHandler {
    var method: String {
        return "textDocument/sourceKitOptions"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        let result: Result

        let components = URLComponents(string: request.params.target.uri)
        if let scheme = components?.queryItems?.first(where: { $0.name == "scheme" })?.value {
            let settings = try xcodebuild.settingsForScheme(scheme).first { $0.action == "build" }

            let settingsForIndex = try? xcodebuild.settingsForIndex(forScheme: scheme)

            if 
                let settingsForIndex,
                let filePath = URLComponents(string: request.params.textDocument.uri)?.path 
            {
                let settingsFoFile = settingsForIndex[scheme]?[filePath]
                var arguments = settingsFoFile?.swiftASTCommandArguments ?? []
                arguments.append(contentsOf: settingsFoFile?.clangASTCommandArguments ?? [])
                arguments.append(contentsOf: settingsFoFile?.clangPCHCommandArguments ?? [])
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
                result = Result(
                    compilerArguments: arguments,
                    workingDirectory: settings?.buildSettings.SOURCE_ROOT
                )
            } else {
                result = Result(compilerArguments: [], workingDirectory: nil)
            }
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
