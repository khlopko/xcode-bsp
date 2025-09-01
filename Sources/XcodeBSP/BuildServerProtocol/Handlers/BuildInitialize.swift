import CryptoKit
import Foundation
import Logging

struct BuildInitialize {
    let xcodebuild: XcodeBuild
    let cacheDir: URL
    let logger: Logger
}

extension BuildInitialize: MethodHandler {
    var method: String {
        return "build/initialize"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        var settings: XcodeBuild.Settings?
        let list = try xcodebuild.list()
        for scheme in list.project.schemes {
            do {
                // just taking first target with action: "build"
                settings = try xcodebuild.settingsForScheme(scheme).first { $0.action == "build" }
                if settings != nil {
                    break
                }
            } catch {
                logger.error("failed to get settings for \(scheme): \(error)")
                continue
            }
        }

        var sourceKitData: Result.SourceKitData?
        if let settings {
            let indexStorePath = URL(string: settings.buildSettings.BUILD_ROOT)?
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(components: "Index.noindex", "DataStore")
                .path()
            let indexDatabasePath = indexStorePath.map { 
                return cacheDir.appending(component: "indexDatabase-\($0.sha256() ?? "")").path() 
            }
            sourceKitData = Result.SourceKitData(
                indexDatabasePath: indexDatabasePath,
                indexStorePath: indexStorePath
            )
        }

        return Result(capabilities: Result.Capabilities(), data: sourceKitData)
    }
}

extension String {
    func sha256() -> String? {
        guard let data = data(using: .utf8) else {
            return nil
        }

        let digest = SHA256.hash(data: data)
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
        return hashString
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
        let indexDatabasePath: String?
        let indexStorePath: String?
        let prepareProvider: Bool = false
        let sourceKitOptionsProvider: Bool = true
    }
}
