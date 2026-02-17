import Foundation

protocol ConfigProvider: Sendable {
    func load(decoder: JSONDecoder) throws -> Config
}

struct FileConfigProvider {
}

extension FileConfigProvider: ConfigProvider {
    func load(decoder: JSONDecoder) throws -> Config {
        return try decoder.decode(Config.self, from: Data(contentsOf: Config.configURL()))
    }
}
