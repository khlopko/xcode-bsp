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
        let documentURI = request.params.textDocument.uri
        let targetURI = request.params.target.uri

        logger.trace(
            """
            sourceKitOptions request id=\(request.id) \
            language=\(request.params.language) \
            target=\(targetURI) \
            documentURI=\(documentURI)
            """
        )

        guard let filePath = filePath(fromDocumentURI: documentURI) else {
            logger.trace("sourceKitOptions request id=\(request.id) ignored: non-file document URI")
            return Result(compilerArguments: [], workingDirectory: nil)
        }

        logger.trace("sourceKitOptions request id=\(request.id) resolved filePath=\(filePath)")

        let cachedSnapshot = try await graph.snapshot(decoder: decoder)
        if let options = cachedSnapshot.options(forFilePath: filePath, targetURI: targetURI) {
            logger.trace(
                "sourceKitOptions request id=\(request.id) cache hit for target=\(targetURI) args=\(options.options.count)"
            )
            return Result(compilerArguments: options.options, workingDirectory: options.workingDirectory)
        }

        let resolvedFilePath = URL(filePath: filePath).resolvingSymlinksInPath().path()
        let candidateTargets = cachedSnapshot.targetsByFilePath[filePath]
            ?? cachedSnapshot.targetsByFilePath[resolvedFilePath]
            ?? []
        logger.trace(
            """
            sourceKitOptions request id=\(request.id) cache miss for target=\(targetURI), refreshing \
            (candidateTargetsForFile=\(candidateTargets))
            """
        )

        var refreshedSnapshot: BuildGraphSnapshot?

        await state.beginUpdate()
        do {
            let refresh = try await graph.refresh(decoder: decoder, checkCache: false)
            refreshedSnapshot = refresh.snapshot
            await state.recordRefreshChanges(refresh)
            await state.endUpdate()

            if let options = refresh.snapshot.options(forFilePath: filePath, targetURI: targetURI) {
                logger.trace(
                    "sourceKitOptions request id=\(request.id) refresh hit for target=\(targetURI) args=\(options.options.count)"
                )
                return Result(compilerArguments: options.options, workingDirectory: options.workingDirectory)
            }
        } catch {
            await state.endUpdate()
            throw error
        }

        let refreshedCandidateTargets = refreshedSnapshot?.targetsByFilePath[filePath]
            ?? refreshedSnapshot?.targetsByFilePath[resolvedFilePath]
            ?? []
        logger.trace(
            """
            sourceKitOptions request id=\(request.id) returning empty result \
            target=\(targetURI) \
            filePath=\(filePath) \
            resolvedFilePath=\(resolvedFilePath) \
            candidateTargetsAfterRefresh=\(refreshedCandidateTargets)
            """
        )

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
