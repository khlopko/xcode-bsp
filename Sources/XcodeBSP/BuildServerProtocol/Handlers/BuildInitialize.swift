import CryptoKit
import Foundation
import Logging

struct BuildInitialize {
    let xcodebuild: any XcodeBuildClient
    let cacheDir: URL
    let logger: Logger
    let configProvider: any ConfigProvider

    init(
        xcodebuild: any XcodeBuildClient = NoopXcodeBuildClient(),
        cacheDir: URL = FileManager.default.temporaryDirectory,
        logger: Logger = Logger(label: "xcode-bsp.build-initialize"),
        configProvider: any ConfigProvider = FileConfigProvider()
    ) {
        self.xcodebuild = xcodebuild
        self.cacheDir = cacheDir
        self.logger = logger
        self.configProvider = configProvider
    }
}

extension BuildInitialize: MethodHandler {
    var method: String {
        return "build/initialize"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        let config = try configProvider.load(decoder: decoder)

        let schemes: [String]
        if config.activeSchemes.isEmpty {
            do {
                let list = try xcodebuild.list(checkCache: true)
                schemes = config.resolvedSchemes(from: list.project.schemes)
            } catch {
                logger.error("failed to list schemes for build/initialize: \(error)")
                schemes = []
            }
        } else {
            schemes = config.activeSchemes
        }

        let sourceKitData = sourceKitData(forSchemes: schemes)
        return Result(capabilities: Result.Capabilities(), data: sourceKitData)
    }
}

extension BuildInitialize {
    private func sourceKitData(forSchemes schemes: [String]) -> Result.SourceKitData {
        for scheme in schemes {
            do {
                let settings = try xcodebuild.settingsForScheme(scheme, checkCache: true)
                guard let buildSettings = settings.first(where: { $0.action == "build" })?.buildSettings else {
                    continue
                }

                let indexStorePath = indexStorePath(fromBuildRoot: buildSettings.BUILD_ROOT)
                let indexDatabasePath = indexDatabasePath(forIndexStorePath: indexStorePath)
                return Result.SourceKitData(
                    indexDatabasePath: indexDatabasePath,
                    indexStorePath: indexStorePath,
                    watches: watches()
                )
            } catch {
                logger.error("failed to resolve build settings for \(scheme): \(error)")
            }
        }

        return Result.SourceKitData(indexDatabasePath: nil, indexStorePath: nil, watches: watches())
    }

    private func indexStorePath(fromBuildRoot buildRoot: String) -> String {
        let buildRootURL = URL(filePath: buildRoot)
        let indexStoreURL = buildRootURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(components: "Index.noindex", "DataStore")

        return indexStoreURL.standardizedFileURL.path()
    }

    private func indexDatabasePath(forIndexStorePath indexStorePath: String) -> String {
        let digest = Self.sha256Hex(for: Data(indexStorePath.utf8))
        return cacheDir.appending(component: "indexDatabase-\(digest)").path()
    }

    private func watches() -> [Result.SourceKitData.Watch] {
        return [
            Result.SourceKitData.Watch(globPattern: "**/*.swift"),
            Result.SourceKitData.Watch(globPattern: "**/*.h"),
            Result.SourceKitData.Watch(globPattern: "**/*.m"),
            Result.SourceKitData.Watch(globPattern: "**/*.mm"),
            Result.SourceKitData.Watch(globPattern: "**/*.c"),
            Result.SourceKitData.Watch(globPattern: "**/*.cpp"),
            Result.SourceKitData.Watch(globPattern: "**/*.xcodeproj/project.pbxproj"),
            Result.SourceKitData.Watch(globPattern: ".bsp/xcode-bsp.json"),
        ]
    }

    private static func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension BuildInitialize {
    struct Params: Decodable {
    }
}

extension BuildInitialize {
    struct Result: Encodable {
        let displayName: String = "xcode-bsp"
        let version: String = "0.1.0"
        let bspVersion: String = "2.0.0"
        let capabilities: Capabilities
        let dataKind: String = "sourceKit"
        let data: SourceKitData?
    }
}

extension BuildInitialize.Result {
    struct Capabilities: Encodable {
        let languageIds: [String] = ["swift", "objective-c", "objective-cpp", "c", "cpp"]
        let buildTargetChangedProvider: Bool = true
        let inverseSourcesProvider: Bool = true
    }
}

extension BuildInitialize.Result {
    struct SourceKitData: Encodable {
        let indexDatabasePath: String?
        let indexStorePath: String?
        let watches: [Watch]
        let prepareProvider: Bool = true
        let sourceKitOptionsProvider: Bool = true
        let waitForBuildSystemUpdatesProvider: Bool = true
    }
}

extension BuildInitialize.Result.SourceKitData {
    struct Watch: Encodable {
        let globPattern: String
    }
}

private struct NoopXcodeBuildClient: XcodeBuildClient {
    func list(checkCache: Bool) throws -> XcodeBuild.List {
        return XcodeBuild.List(project: XcodeBuild.List.Project(name: "", schemes: [], targets: []))
    }

    func settingsForScheme(_ scheme: String, checkCache: Bool) throws -> [XcodeBuild.Settings] {
        return []
    }

    func settingsForIndex(forScheme scheme: String, checkCache: Bool) throws -> XcodeBuild.SettingsForIndex {
        return [:]
    }
}
