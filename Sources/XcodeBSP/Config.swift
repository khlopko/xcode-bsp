import Foundation

struct Config {
    let name: String
    let argv: [String]
    let version: String
    let bspVersion: String
    let languages: [String]
    let activeSchemes: [String]
}

extension Config: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case argv
        case version
        case bspVersion
        case languages
        case activeSchemes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        argv = try container.decode([String].self, forKey: .argv)
        version = try container.decode(String.self, forKey: .version)
        bspVersion = try container.decode(String.self, forKey: .bspVersion)
        languages = try container.decode([String].self, forKey: .languages)
        activeSchemes = try container.decodeIfPresent([String].self, forKey: .activeSchemes) ?? []
    }
}

extension Config: Sendable {
}

extension Config {
    func resolvedSchemes(from availableSchemes: [String]) -> [String] {
        if activeSchemes.isEmpty {
            return availableSchemes
        }

        return activeSchemes
    }

    static func dirURL() -> URL {
        let pwd = FileManager.default.currentDirectoryPath
        return URL(filePath: pwd).appending(component: ".bsp")
    }

    static func configURL() -> URL {
        return dirURL().appending(component: "xcode-bsp.json")
    }
}
