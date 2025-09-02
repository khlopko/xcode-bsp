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
}

extension Config {
    static func dirURL() -> URL {
        let pwd = FileManager.default.currentDirectoryPath
        return URL(filePath: pwd).appending(component: ".bsp")
    }

    static func configURL() -> URL {
        return dirURL().appending(component: "xcode-bsp.json")
    }
}
