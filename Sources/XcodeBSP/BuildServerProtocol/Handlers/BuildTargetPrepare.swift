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
            let initialRefresh = try await graph.refresh(decoder: decoder, checkCache: true)
            await state.recordRefreshChanges(initialRefresh)

            let preparedTargets = request.params.targets.compactMap { target -> (TargetID, PreparedTarget)? in
                guard let parsedTarget = parseTarget(fromURI: target.uri) else {
                    logger.error("failed to extract scheme from target uri: \(target.uri)")
                    return nil
                }
                return (target, parsedTarget)
            }

            let warmupSchemes = schemesRequiringWarmup(
                preparedTargets: preparedTargets,
                snapshot: initialRefresh.snapshot
            )

            var snapshot = initialRefresh.snapshot
            if warmupSchemes.isEmpty == false {
                for scheme in warmupSchemes {
                    do {
                        logger.debug("buildTarget/prepare warmup build started for scheme \(scheme)")
                        try await graph.warmupBuild(forScheme: scheme)
                        logger.debug("buildTarget/prepare warmup build completed for scheme \(scheme)")
                    } catch {
                        logger.error("buildTarget/prepare warmup build failed for scheme \(scheme): \(error)")
                    }
                }

                let refreshed = try await graph.refresh(decoder: decoder, checkCache: true)
                await state.recordRefreshChanges(refreshed)
                snapshot = refreshed.snapshot
            }

            for (target, parsedTarget) in preparedTargets {

                let lookupURI = canonicalTargetURI(scheme: parsedTarget.scheme, target: parsedTarget.target)
                let optionsByFile = snapshot.optionsByTargetURI[target.uri] ?? snapshot.optionsByTargetURI[lookupURI] ?? [:]
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

    private func schemesRequiringWarmup(
        preparedTargets: [(TargetID, PreparedTarget)],
        snapshot: BuildGraphSnapshot
    ) -> [String] {
        var schemes: Set<String> = []

        for (target, parsedTarget) in preparedTargets {
            let lookupURI = canonicalTargetURI(scheme: parsedTarget.scheme, target: parsedTarget.target)
            let optionsByFile = snapshot.optionsByTargetURI[target.uri] ?? snapshot.optionsByTargetURI[lookupURI] ?? [:]
            guard optionsByFile.isEmpty == false else {
                continue
            }

            /*
            if optionsByFile.values.contains(where: { hasMissingCriticalPaths(arguments: $0.options) }) {
            */
                schemes.insert(parsedTarget.scheme)
            /*
            }
            */
        }

        return schemes.sorted()
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

extension BuildTargetPrepare {
    struct Params: Decodable {
        let targets: [TargetID]
    }
}
