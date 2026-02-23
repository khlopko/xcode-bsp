import Foundation
import Logging

struct TextDocumentSourceKitOptions {
    let graph: BuildGraphService
    let logger: Logger
    let refreshTrigger: any RefreshTrigger

    init(graph: BuildGraphService, logger: Logger, refreshTrigger: any RefreshTrigger) {
        self.graph = graph
        self.logger = logger
        self.refreshTrigger = refreshTrigger
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
            language=\(request.params.language ?? "nil") \
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
            if hasMissingCriticalPaths(arguments: options.options) {
                await refreshTrigger.requestRefresh(reason: "sourceKitOptions-stale-paths:\(targetURI)")
                logger.trace(
                    "sourceKitOptions request id=\(request.id) cache hit had missing critical paths; scheduled background refresh"
                )
                return Result(compilerArguments: [], workingDirectory: nil)
            }

            logger.trace(
                "sourceKitOptions request id=\(request.id) cache hit for target=\(targetURI) args=\(options.options.count)"
            )
            return Result(compilerArguments: options.options, workingDirectory: options.workingDirectory)
        }

        let resolvedFilePath = URL(filePath: filePath).resolvingSymlinksInPath().path()
        let candidateTargets = cachedSnapshot.targetsByFilePath[filePath]
            ?? cachedSnapshot.targetsByFilePath[resolvedFilePath]
            ?? []
        logger.debug(
            """
            sourceKitOptions args cache miss \
            request id=\(request.id) \
            target=\(targetURI) \
            filePath=\(filePath) \
            resolvedFilePath=\(resolvedFilePath) \
            candidateTargets=\(candidateTargets.count)
            """
        )
        logger.trace(
            """
            sourceKitOptions request id=\(request.id) cache miss for target=\(targetURI), refreshing \
            (candidateTargetsForFile=\(candidateTargets))
            """
        )

        await refreshTrigger.requestRefresh(reason: "sourceKitOptions-miss:\(targetURI)")
        logger.trace(
            """
            sourceKitOptions request id=\(request.id) returning empty result and scheduled background refresh \
            target=\(targetURI) \
            filePath=\(filePath) \
            resolvedFilePath=\(resolvedFilePath) \
            candidateTargetsBeforeRefresh=\(candidateTargets)
            """
        )

        return Result(compilerArguments: [], workingDirectory: nil)
    }
}

extension TextDocumentSourceKitOptions {
    struct Params: Decodable {
        let language: String?
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

    private func hasMissingCriticalPaths(arguments: [String]) -> Bool {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            if argument == "-fmodule-map-file", index + 1 < arguments.count {
                if FileManager.default.fileExists(atPath: arguments[index + 1]) == false {
                    return true
                }
            } else if argument.hasPrefix("-fmodule-map-file=") {
                let path = String(argument.dropFirst("-fmodule-map-file=".count))
                if FileManager.default.fileExists(atPath: path) == false {
                    return true
                }
            } else if argument == "-Xcc", index + 1 < arguments.count {
                let wrapped = arguments[index + 1]
                if wrapped == "-fmodule-map-file", index + 3 < arguments.count, arguments[index + 2] == "-Xcc" {
                    if FileManager.default.fileExists(atPath: arguments[index + 3]) == false {
                        return true
                    }
                } else if wrapped.hasPrefix("-fmodule-map-file=") {
                    let path = String(wrapped.dropFirst("-fmodule-map-file=".count))
                    if FileManager.default.fileExists(atPath: path) == false {
                        return true
                    }
                }
            }

            index += 1
        }

        return false
    }
}
