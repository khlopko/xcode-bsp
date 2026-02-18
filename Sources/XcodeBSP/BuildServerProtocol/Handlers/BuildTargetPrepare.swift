import Foundation
import Logging

struct BuildTargetPrepare {
    let graph: BuildGraphService
    let db: any ArgumentsStore
    let logger: Logger
    let state: BuildSystemState

    private let projectName: String

    init(
        graph: BuildGraphService,
        db: any ArgumentsStore,
        logger: Logger,
        state: BuildSystemState
    ) {
        self.graph = graph
        self.db = db
        self.logger = logger
        self.state = state
        projectName = URL(filePath: FileManager.default.currentDirectoryPath).lastPathComponent
    }
}

extension BuildTargetPrepare: MethodHandler {
    typealias Result = EmptyResult

    var method: String {
        return "buildTarget/prepare"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result {
        await state.beginUpdate()
        do {
            let refresh = try await graph.refresh(decoder: decoder, checkCache: true)
            await state.recordRefreshChanges(refresh)

            for target in request.params.targets {
                guard let parsedTarget = parseTarget(fromURI: target.uri) else {
                    logger.error("failed to extract scheme from target uri: \(target.uri)")
                    continue
                }

                let lookupURI = canonicalTargetURI(scheme: parsedTarget.scheme, target: parsedTarget.target)
                let optionsByFile = refresh.snapshot.optionsByTargetURI[target.uri] ?? refresh.snapshot.optionsByTargetURI[lookupURI] ?? [:]
                if optionsByFile.isEmpty {
                    logger.debug("buildTarget/prepare produced no compiler arguments for \(target.uri)")
                    continue
                }

                let argsByFilePaths = optionsByFile.mapValues { $0.options }
                do {
                    try await db.updateArgs(
                        argsByFilePaths: argsByFilePaths,
                        scheme: cacheScope(scheme: parsedTarget.scheme, target: parsedTarget.target)
                    )
                    logger.debug("buildTarget/prepare cached compiler arguments for \(target.uri)")
                } catch {
                    logger.error("buildTarget/prepare failed for \(target.uri): \(error)")
                }
            }

            await state.endUpdate()
            return Result()
        } catch {
            await state.endUpdate()
            throw error
        }
    }
}

extension BuildTargetPrepare {
    private struct PreparedTarget {
        let scheme: String
        let target: String?
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

    private func cacheScope(scheme: String, target: String?) -> String {
        guard let target, target.isEmpty == false else {
            return scheme
        }

        return "\(scheme)::\(target)"
    }

    private func canonicalTargetURI(scheme: String, target: String?) -> String {
        var components = URLComponents()
        components.scheme = "xcode"
        components.host = projectName

        var queryItems = [URLQueryItem(name: "scheme", value: scheme)]
        if let target, target.isEmpty == false {
            queryItems.append(URLQueryItem(name: "target", value: target))
        }
        components.queryItems = queryItems

        let fallbackTarget = target.map { "&target=\($0)" } ?? ""
        return components.string ?? "xcode://\(projectName)?scheme=\(scheme)\(fallbackTarget)"
    }
}

extension BuildTargetPrepare {
    struct Params: Decodable {
        let targets: [TargetID]
    }
}
