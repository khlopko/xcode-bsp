import Foundation

struct BuildInitialize {
    let configProvider: any ConfigProvider

    init(configProvider: any ConfigProvider = FileConfigProvider()) {
        self.configProvider = configProvider
    }
}

extension BuildInitialize: MethodHandler {
    var method: String {
        return "build/initialize"
    }

    func handle(request: Request<Params>, decoder: JSONDecoder) throws -> Result {
        _ = try configProvider.load(decoder: decoder)

        let sourceKitData = Result.SourceKitData(indexDatabasePath: nil, indexStorePath: nil)

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
        let indexDatabasePath: String?
        let indexStorePath: String?
        let prepareProvider: Bool = true
        let sourceKitOptionsProvider: Bool = true
    }
}
