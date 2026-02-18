import Foundation
import Logging

struct TextDocumentSourceKitOptions {
    let graph: BuildGraphService
    let state: BuildSystemState
    let logger: Logger

    init(graph: BuildGraphService, state: BuildSystemState, logger: Logger) {
        self.graph = graph
        self.state = state
        self.logger = logger
    }
}

extension TextDocumentSourceKitOptions: MethodHandler {
    var method: String {
        return "textDocument/sourceKitOptions"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result {
        guard let filePath = filePath(fromDocumentURI: request.params.textDocument.uri) else {
            return Result(compilerArguments: [], workingDirectory: nil)
        }

        let targetURI = request.params.target.uri

        let cachedSnapshot = try await graph.snapshot(decoder: decoder)
        if let options = cachedSnapshot.options(forFilePath: filePath, targetURI: targetURI) {
            return Result(compilerArguments: options.options, workingDirectory: options.workingDirectory)
        }

        logger.debug("missing compiler arguments in cached graph for \(targetURI), refreshing")

        await state.beginUpdate()
        do {
            let refresh = try await graph.refresh(decoder: decoder, checkCache: false)
            await state.recordRefreshChanges(refresh)
            await state.endUpdate()

            if let options = refresh.snapshot.options(forFilePath: filePath, targetURI: targetURI) {
                return Result(compilerArguments: options.options, workingDirectory: options.workingDirectory)
            }
        } catch {
            await state.endUpdate()
            throw error
        }

        return Result(compilerArguments: [], workingDirectory: nil)
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
    private func filePath(fromDocumentURI documentURI: String) -> String? {
        guard let url = URL(string: documentURI), url.isFileURL else {
            return nil
        }

        return URL(filePath: url.path()).standardizedFileURL.path()
    }
}
