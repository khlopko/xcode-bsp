import Foundation

struct TextDocumentSourceKitOptions {
}

extension TextDocumentSourceKitOptions: MethodHandler {
    var method: String {
        return "textDocument/sourceKitOptions"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        let result: Result

        let output = shell("xcodebuild -showBuildSettings -json")
        if let outputData = output.text?.data(using: .utf8) {
            do {
                let xcodeBuildSettings = try decoder.decode([XcodeBuildSettings].self, from: outputData)
                if let scheme = request.params.target.uri.split(separator: "://").last,
                    let xcodeTarget = xcodeBuildSettings.first(where: { $0.target == scheme })
                {
                    result = Result(
                        compilerArguments: [],
                        workingDirectory: xcodeTarget.buildSettings.BUILD_ROOT
                    )
                }
                else {
                    result = Result(compilerArguments: [], workingDirectory: nil)
                }
            } catch {
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
