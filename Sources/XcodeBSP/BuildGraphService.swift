import Foundation
import Logging

struct CompilerOptions: Sendable, Equatable {
    let options: [String]
    let workingDirectory: String?
}

struct BuildGraphTarget: Sendable, Equatable {
    let uri: String
    let displayName: String
    let dependencies: [String]
}

struct BuildGraphSnapshot: Sendable, Equatable {
    let targets: [BuildGraphTarget]
    let filesByTargetURI: [String: [String]]
    let optionsByTargetURI: [String: [String: CompilerOptions]]
    let targetsByFilePath: [String: [String]]
    let optionsByFilePath: [String: CompilerOptions]
    let indexStorePath: String?
}

struct BuildGraphRefreshResult: Sendable {
    let snapshot: BuildGraphSnapshot
    let changedTargetURIs: [String]
    let changedOptionsByFilePath: [String: CompilerOptions]
}

actor BuildGraphService {
    private let xcodebuild: any XcodeBuildClient
    private let configProvider: any ConfigProvider
    private let logger: Logger

    private let projectName: String
    private var snapshotCache: BuildGraphSnapshot?

    init(
        xcodebuild: any XcodeBuildClient,
        logger: Logger,
        configProvider: any ConfigProvider = FileConfigProvider()
    ) {
        self.xcodebuild = xcodebuild
        self.logger = logger
        self.configProvider = configProvider
        projectName = URL(filePath: FileManager.default.currentDirectoryPath).lastPathComponent
    }

    func snapshot(decoder: JSONDecoder) async throws -> BuildGraphSnapshot {
        if let snapshotCache {
            logger.trace("build graph snapshot cache hit\n\(snapshotCache.logDescription)")
            return snapshotCache
        }

        let refreshed = try await refresh(decoder: decoder, checkCache: true)
        return refreshed.snapshot
    }

    func refresh(decoder: JSONDecoder, checkCache: Bool) async throws -> BuildGraphRefreshResult {
        let config = try configProvider.load(decoder: decoder)
        let schemes = try resolveSchemes(config: config, checkCache: checkCache)

        var targets: [BuildGraphTarget] = []
        var filesByTargetURI: [String: [String]] = [:]
        var optionsByTargetURI: [String: [String: CompilerOptions]] = [:]
        var targetsByFile: [String: Set<String>] = [:]
        var indexStoreCandidates: [String] = []

        for scheme in schemes {
            let settingsForIndex = try settingsForIndex(forScheme: scheme, checkCache: checkCache)
            let nestedTargets = settingsForIndex.keys
                .filter { $0 != scheme && (settingsForIndex[$0]?.isEmpty == false) }
                .sorted()

            let schemeURI = makeTargetURI(scheme: scheme, target: nil)
            let nestedURIs = nestedTargets.map { makeTargetURI(scheme: scheme, target: $0) }
            targets.append(
                BuildGraphTarget(
                    uri: schemeURI,
                    displayName: scheme,
                    dependencies: nestedURIs
                )
            )

            let schemeOptions = compilerOptionsByFilePath(
                settingsForIndex: settingsForIndex,
                scheme: scheme,
                target: nil
            )
            optionsByTargetURI[schemeURI] = schemeOptions
            let schemeFiles = schemeOptions.keys.sorted()
            filesByTargetURI[schemeURI] = schemeFiles

            for filePath in schemeFiles {
                targetsByFile[filePath, default: []].insert(schemeURI)
                if let options = schemeOptions[filePath], let indexStorePath = indexStorePath(fromCompilerArguments: options.options) {
                    indexStoreCandidates.append(indexStorePath)
                }
            }

            for nestedTarget in nestedTargets {
                let targetURI = makeTargetURI(scheme: scheme, target: nestedTarget)
                targets.append(
                    BuildGraphTarget(
                        uri: targetURI,
                        displayName: "\(scheme) (\(nestedTarget))",
                        dependencies: []
                    )
                )

                let nestedOptions = compilerOptionsByFilePath(
                    settingsForIndex: settingsForIndex,
                    scheme: scheme,
                    target: nestedTarget
                )
                optionsByTargetURI[targetURI] = nestedOptions
                let nestedFiles = nestedOptions.keys.sorted()
                filesByTargetURI[targetURI] = nestedFiles

                for filePath in nestedFiles {
                    targetsByFile[filePath, default: []].insert(targetURI)
                    if let options = nestedOptions[filePath], let indexStorePath = indexStorePath(fromCompilerArguments: options.options) {
                        indexStoreCandidates.append(indexStorePath)
                    }
                }
            }
        }

        let targetsByFilePath = targetsByFile.mapValues { Array($0).sorted() }

        var optionsByFilePath: [String: CompilerOptions] = [:]
        for targetURI in optionsByTargetURI.keys.sorted() {
            for (filePath, options) in (optionsByTargetURI[targetURI] ?? [:]).sorted(by: { $0.key < $1.key }) {
                if optionsByFilePath[filePath] == nil {
                    optionsByFilePath[filePath] = options
                }
            }
        }

        let indexStorePath = preferredIndexStorePath(
            candidates: indexStoreCandidates,
            schemes: schemes,
            checkCache: checkCache
        )

        let snapshot = BuildGraphSnapshot(
            targets: targets.sorted(by: { $0.uri < $1.uri }),
            filesByTargetURI: filesByTargetURI,
            optionsByTargetURI: optionsByTargetURI,
            targetsByFilePath: targetsByFilePath,
            optionsByFilePath: optionsByFilePath,
            indexStorePath: indexStorePath
        )

        let previous = snapshotCache
        snapshotCache = snapshot

        let changedTargetURIs = changedTargetURIs(previous: previous, current: snapshot)
        let changedOptionsByFilePath = changedOptionsByFilePath(previous: previous, current: snapshot)

        logger.trace(
            """
            build graph snapshot refreshed \
            (changedTargets: \(changedTargetURIs.count), changedFiles: \(changedOptionsByFilePath.count))
            \(snapshot.logDescription)
            """
        )

        return BuildGraphRefreshResult(
            snapshot: snapshot,
            changedTargetURIs: changedTargetURIs,
            changedOptionsByFilePath: changedOptionsByFilePath
        )
    }

    func invalidate() {
        snapshotCache = nil
    }
}

extension BuildGraphService {
    private func resolveSchemes(config: Config, checkCache: Bool) throws -> [String] {
        if config.activeSchemes.isEmpty == false {
            return config.activeSchemes
        }

        do {
            logger.trace("invoking xcodebuild.list(checkCache: \(checkCache))")
            return try xcodebuild.list(checkCache: checkCache).project.schemes
        } catch {
            guard checkCache else {
                throw error
            }

            logger.trace("invoking xcodebuild.list(checkCache: false) after failure with cached result")
            return try xcodebuild.list(checkCache: false).project.schemes
        }
    }

    private func settingsForIndex(forScheme scheme: String, checkCache: Bool) throws -> XcodeBuild.SettingsForIndex {
        do {
            logger.trace("invoking xcodebuild.settingsForIndex(forScheme: \(scheme), checkCache: \(checkCache))")
            let settings = try xcodebuild.settingsForIndex(forScheme: scheme, checkCache: checkCache)
            if settings.isEmpty, checkCache {
                logger.trace("invoking xcodebuild.settingsForIndex(forScheme: \(scheme), checkCache: false) because cached settings are empty")
                return try xcodebuild.settingsForIndex(forScheme: scheme, checkCache: false)
            }
            return settings
        } catch {
            guard checkCache else {
                throw error
            }

            logger.trace("invoking xcodebuild.settingsForIndex(forScheme: \(scheme), checkCache: false) after failure with cached result")
            return try xcodebuild.settingsForIndex(forScheme: scheme, checkCache: false)
        }
    }

    private func makeTargetURI(scheme: String, target: String?) -> String {
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

    private func compilerOptionsByFilePath(
        settingsForIndex: XcodeBuild.SettingsForIndex,
        scheme: String,
        target: String?
    ) -> [String: CompilerOptions] {
        let fileSettings = fileSettingsByPath(from: settingsForIndex, scheme: scheme, target: target)

        var result: [String: CompilerOptions] = [:]
        for (path, settings) in fileSettings {
            let normalizedPath = normalizeFilePath(path)
            let options = sanitizedCompilerArguments(from: settings)
            result[normalizedPath] = CompilerOptions(
                options: options,
                workingDirectory: workingDirectory(arguments: options)
            )
        }

        return result
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
        for (_, values) in settingsForIndex {
            for (filePath, fileSettings) in values {
                merged[filePath] = fileSettings
            }
        }

        return merged
    }

    private func sanitizedCompilerArguments(from settings: XcodeBuild.FileSettings) -> [String] {
        var arguments = settings.swiftASTCommandArguments ?? []
        arguments.append(contentsOf: settings.clangASTCommandArguments ?? [])
        arguments.append(contentsOf: settings.clangPCHCommandArguments ?? [])

        arguments = arguments.filter { $0 != "-use-frontend-parseable-output" }
        for (index, argument) in arguments.enumerated().reversed() {
            if argument == "-emit-localized-strings-path", index > 0 {
                arguments.remove(at: index)
                arguments.remove(at: index - 1)
            } else if argument == "-emit-localized-strings" {
                arguments.remove(at: index)
            }
        }

        return removeMissingSDK(arguments: arguments)
    }

    private func removeMissingSDK(arguments: [String]) -> [String] {
        var sanitized = arguments
        for (index, argument) in arguments.enumerated().reversed() {
            guard argument == "-sdk", index + 1 < arguments.count else {
                continue
            }

            let path = arguments[index + 1]
            if FileManager.default.fileExists(atPath: path) == false {
                sanitized.remove(at: index + 1)
                sanitized.remove(at: index)
            }
        }

        return sanitized
    }

    private func workingDirectory(arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == "-working-directory", index + 1 < arguments.count {
                return arguments[index + 1]
            }

            if argument.hasPrefix("-working-directory=") {
                return String(argument.dropFirst("-working-directory=".count))
            }
        }

        return nil
    }

    private func indexStorePath(fromCompilerArguments arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == "-index-store-path", index + 1 < arguments.count {
                return normalizePath(arguments[index + 1])
            }

            if argument.hasPrefix("-index-store-path=") {
                return normalizePath(String(argument.dropFirst("-index-store-path=".count)))
            }
        }

        return nil
    }

    private func preferredIndexStorePath(
        candidates: [String],
        schemes: [String],
        checkCache: Bool
    ) -> String? {
        if let preferredFromArgs = mostFrequentPath(from: candidates) {
            return preferredFromArgs
        }

        for scheme in schemes {
            logger.trace("invoking xcodebuild.settingsForScheme(\(scheme), checkCache: \(checkCache))")
            guard let settings = try? xcodebuild.settingsForScheme(scheme, checkCache: checkCache) else {
                continue
            }

            guard let buildRoot = settings.first(where: { $0.action == "build" })?.buildSettings.BUILD_ROOT else {
                continue
            }

            let heuristic = URL(filePath: buildRoot)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(components: "Index.noindex", "DataStore")
                .standardizedFileURL
                .path()
            logger.trace("using fallback index store path from BUILD_ROOT for scheme \(scheme): \(heuristic)")
            return heuristic
        }

        return nil
    }

    private func mostFrequentPath(from paths: [String]) -> String? {
        guard paths.isEmpty == false else {
            return nil
        }

        var counts: [String: Int] = [:]
        for path in paths {
            counts[path, default: 0] += 1
        }

        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .first?
            .key
    }

    private func changedTargetURIs(previous: BuildGraphSnapshot?, current: BuildGraphSnapshot) -> [String] {
        guard let previous else {
            return current.targets.map(\.uri)
        }

        var changed: Set<String> = []
        let currentByURI = Dictionary(uniqueKeysWithValues: current.targets.map { ($0.uri, $0) })
        let previousByURI = Dictionary(uniqueKeysWithValues: previous.targets.map { ($0.uri, $0) })

        for uri in Set(currentByURI.keys).union(previousByURI.keys) {
            let oldTarget = previousByURI[uri]
            let newTarget = currentByURI[uri]
            if oldTarget != newTarget {
                changed.insert(uri)
                continue
            }

            if previous.filesByTargetURI[uri] != current.filesByTargetURI[uri] {
                changed.insert(uri)
            }
        }

        return Array(changed).sorted()
    }

    private func changedOptionsByFilePath(
        previous: BuildGraphSnapshot?,
        current: BuildGraphSnapshot
    ) -> [String: CompilerOptions] {
        guard let previous else {
            return current.optionsByFilePath
        }

        let allPaths = Set(previous.optionsByFilePath.keys).union(current.optionsByFilePath.keys)
        var result: [String: CompilerOptions] = [:]

        for path in allPaths {
            let oldValue = previous.optionsByFilePath[path]
            let newValue = current.optionsByFilePath[path]
            if oldValue != newValue, let newValue {
                result[path] = newValue
            }
        }

        return result
    }

    private func normalizeFilePath(_ path: String) -> String {
        return URL(filePath: path).standardizedFileURL.path()
    }

    private func normalizePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return URL(filePath: path).standardizedFileURL.path()
        }

        return path
    }
}

extension BuildGraphSnapshot {
    var logDescription: String {
        var lines: [String] = []
        lines.append("snapshot:")
        lines.append("  indexStorePath: \(indexStorePath ?? "nil")")

        lines.append("  targets[\(targets.count)]:")
        for target in targets.sorted(by: { $0.uri < $1.uri }) {
            let dependencies = target.dependencies.sorted().joined(separator: ", ")
            lines.append("    - uri: \(target.uri)")
            lines.append("      displayName: \(target.displayName)")
            lines.append("      dependencies: [\(dependencies)]")
        }

        return lines.joined(separator: "\n")
    }

    func options(forFilePath filePath: String, targetURI: String?) -> CompilerOptions? {
        let normalizedFilePath = URL(filePath: filePath).standardizedFileURL.path()
        let resolvedFilePath = URL(filePath: normalizedFilePath).resolvingSymlinksInPath().path()

        if let targetURI,
           let byFile = optionsByTargetURI[targetURI],
           let exact = byFile[normalizedFilePath] ?? byFile[resolvedFilePath]
        {
            return exact
        }

        if let exact = optionsByFilePath[normalizedFilePath] ?? optionsByFilePath[resolvedFilePath] {
            return exact
        }

        return nil
    }
}
