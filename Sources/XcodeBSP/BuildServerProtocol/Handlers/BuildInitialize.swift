import CryptoKit
import Foundation

struct BuildInitialize {
    let graph: BuildGraphService
    let cacheDir: URL

    init(graph: BuildGraphService, cacheDir: URL) {
        self.graph = graph
        self.cacheDir = cacheDir
    }
}

extension BuildInitialize: MethodHandler {
    var method: String {
        return "build/initialize"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) async throws -> Result {
        let snapshot = try await graph.snapshot(decoder: decoder)

        let indexStorePath = snapshot.indexStorePath
        let indexDatabasePath = indexStorePath.map(indexDatabasePath(forIndexStorePath:))
        let sourceKitData = Result.SourceKitData(
            indexDatabasePath: indexDatabasePath,
            indexStorePath: indexStorePath,
            watches: watches()
        )

        return Result(capabilities: Result.Capabilities(), data: sourceKitData)
    }
}

extension BuildInitialize {
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
