import Foundation
import CryptoKit
import Logging

struct BuildInitialize {
    let logger: Logger
}

extension BuildInitialize: MethodHandler {
    var method: String {
        return "build/initialize"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        var sourceKitData: Result.SourceKitData?
        let output = shell("xcodebuild -showBuildSettings -json")
        if let outputData = output.text?.data(using: .utf8) {
            let xcodeBuildSettings = try decoder.decode([XcodeBuildSettings].self, from: outputData)
            // just taking first target with action: "build"
            if let buildableTarget = xcodeBuildSettings.first(where: { $0.action == "build" }) {
                logger.debug("xcode build settings: \(buildableTarget)")
                let indexStorePath = buildableTarget.buildSettings.BUILD_ROOT
                let cachePath = "~/Library/Caches/xcode-bsp"
                var sha256 = SHA256()
                sha256.update(data: indexStorePath.data(using: .utf8)!)
                let digest = sha256.finalize().split(separator: Character(":").asciiValue!)[1]
                sourceKitData = Result.SourceKitData(
                    indexDatabasePath: cachePath + "/indexDatabase-\(digest)",
                    indexStorePath: indexStorePath
                )
            }
        }

        return Result(capabilities: Result.Capabilities(), data: sourceKitData)
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
    }
}

extension BuildInitialize.Result {
    struct SourceKitData: Encodable {
        let indexDatabasePath: String
        let indexStorePath: String
        let sourceKitOptionsProvider: Bool = true
    }
}
