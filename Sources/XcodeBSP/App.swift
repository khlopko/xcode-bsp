import ArgumentParser
import Foundation

@main
struct XcodeBSPApp: ParsableCommand {
    enum Action: String, Decodable {
        case config
        case server
    }

    @Argument(transform: { Action(rawValue: $0) })
    var action: Action?

    @Option(
        name: .long,
        help: "Path to xcode-bsp executable to write to .bsp/xcode-bsp.json (config action only)."
    )
    var executablePath: String?

    func validate() throws {
        if executablePath != nil, action != .config {
            throw ValidationError("--executable-path can only be used with the config action.")
        }
    }

    func run() throws {
        let action = action ?? .server
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(components: "Library", "Caches", "xcode-bsp")
        if FileManager.default.fileExists(atPath: cacheDir.path()) == false {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        switch action {
        case .config:
            print("Loading project config")
            let xcodebuild = XcodeBuild(
                cacheDir: cacheDir,
                decoder: JSONDecoder(),
                logger: try makeLogger(label: "xcode-bsp.config")
            )
            let list = try xcodebuild.list(checkCache: false)
            print("Choose schemes to include in config:")
            var activeSchemes: [String] = []
            for scheme in list.project.schemes {
                print("\(scheme) [Y/n]", terminator: " ")
                let answer = readLine() ?? "Y"
                if answer == "Y" {
                    activeSchemes.append(scheme)
                }
            }

            let workspaceContainerPath = try resolveConfiguredWorkspaceContainerPath()
            print("Using workspace container: \(workspaceContainerPath)")

            let executablePath = try resolveConfiguredExecutablePath()
            print("Using executable path: \(executablePath)")

            let bspDirPath = Config.dirURL().path()
            if FileManager.default.fileExists(atPath: bspDirPath) == false {
                do {
                    try FileManager.default.createDirectory(
                        atPath: bspDirPath,
                        withIntermediateDirectories: true
                    )
                } catch {
                    print("Failed to create dir: \(error)")
                    throw error
                }
            }

            let configPath = Config.configURL().path()
            if FileManager.default.fileExists(atPath: configPath) {
                try FileManager.default.removeItem(atPath: configPath)
            }

            let config = Config(
                name: "xcode-bsp",
                argv: [executablePath],
                version: "0.2.0",
                bspVersion: "2.0.0",
                languages: ["swift", "objective-c", "objective-cpp"],
                activeSchemes: activeSchemes,
                buildBackend: .swiftBuild,
                workspaceContainerPath: workspaceContainerPath
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            let data = try encoder.encode(config)
            FileManager.default.createFile(atPath: configPath, contents: data)
            print("Saved BSP config to \(configPath)")
        case .server:
            let config = try FileConfigProvider().load(decoder: JSONDecoder())
            switch config.buildBackend {
            case .swiftBuild:
                let server = try SwiftBuildServerBackend(cacheDir: cacheDir, config: config)
                try server.run()
            case .xcodeBuild:
                let server = try XcodeBuildServer(cacheDir: cacheDir)
                server.run()
            }
        }
    }
}

private extension XcodeBSPApp {
    func resolveConfiguredExecutablePath() throws -> String {
        if let executablePath {
            return try validateExecutablePath(executablePath)
        }

        let defaultPath = detectExecutablePath()
        print("xcode-bsp executable path [\(defaultPath)]", terminator: " ")
        let input = (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            return try validateExecutablePath(defaultPath)
        }

        return try validateExecutablePath(input)
    }

    func detectExecutablePath(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let argv0 = CommandLine.arguments.first ?? "xcode-bsp"
        if let resolvedFromArgument = resolveExecutableCandidate(argv0, fileManager: fileManager) {
            return resolvedFromArgument
        }

        let executableName = URL(filePath: argv0).lastPathComponent
        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(filePath: String(directory))
                    .appending(component: executableName)
                    .path()
                if fileManager.isExecutableFile(atPath: candidate) {
                    return URL(filePath: candidate).standardizedFileURL.resolvingSymlinksInPath().path()
                }
            }
        }

        return "/usr/local/bin/xcode-bsp"
    }

    func resolveConfiguredWorkspaceContainerPath(fileManager: FileManager = .default) throws -> String {
        let candidates = try workspaceContainerCandidates(fileManager: fileManager)
        guard candidates.isEmpty == false else {
            throw ValidationError(
                "No .xcworkspace or .xcodeproj found in the current directory. " +
                "Run `xcode-bsp config` from a project root."
            )
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        print("Choose workspace container for SwiftBuild:")
        for (index, candidate) in candidates.enumerated() {
            print("[\(index + 1)] \(candidate)")
        }

        print("Selection [1]", terminator: " ")
        let input = (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            return candidates[0]
        }

        guard let selectedIndex = Int(input), candidates.indices.contains(selectedIndex - 1) else {
            throw ValidationError("Invalid container selection: \(input)")
        }

        return candidates[selectedIndex - 1]
    }

    func workspaceContainerCandidates(fileManager: FileManager) throws -> [String] {
        let cwd = URL(filePath: fileManager.currentDirectoryPath)
        let contents = try fileManager.contentsOfDirectory(
            at: cwd,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let candidates = contents.compactMap { url -> String? in
            let pathExtension = url.pathExtension.lowercased()
            guard pathExtension == "xcworkspace" || pathExtension == "xcodeproj" else {
                return nil
            }
            return url.lastPathComponent
        }

        return candidates.sorted { lhs, rhs in
            let lhsIsWorkspace = lhs.lowercased().hasSuffix(".xcworkspace")
            let rhsIsWorkspace = rhs.lowercased().hasSuffix(".xcworkspace")
            if lhsIsWorkspace != rhsIsWorkspace {
                return lhsIsWorkspace
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    func resolveExecutableCandidate(_ value: String, fileManager: FileManager) -> String? {
        guard value.contains("/") else {
            return nil
        }

        let candidatePath = normalizePath(value, fileManager: fileManager)
        if fileManager.isExecutableFile(atPath: candidatePath) {
            return candidatePath
        }

        return nil
    }

    func validateExecutablePath(_ path: String, fileManager: FileManager = .default) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ValidationError("Executable path cannot be empty.")
        }

        let normalizedPath = normalizePath(trimmed, fileManager: fileManager)
        guard fileManager.fileExists(atPath: normalizedPath) else {
            throw ValidationError("Executable path does not exist: \(normalizedPath)")
        }
        guard fileManager.isExecutableFile(atPath: normalizedPath) else {
            throw ValidationError("Executable path is not executable: \(normalizedPath)")
        }

        return normalizedPath
    }

    func normalizePath(_ path: String, fileManager: FileManager) -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        let currentDirectory = URL(filePath: fileManager.currentDirectoryPath)
        return URL(filePath: expandedPath, relativeTo: currentDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path()
    }
}
