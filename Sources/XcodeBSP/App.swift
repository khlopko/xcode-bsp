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

    func run() throws {
        let action = action ?? .server
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(components: "Library", "Caches", "xcode-bsp")
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
                argv: ["/usr/local/bin/xcode-bsp"],
                version: "0.1.0",
                bspVersion: "2.0.0",
                languages: ["swift", "objective-c", "objective-cpp"],
                activeSchemes: activeSchemes
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            let data = try encoder.encode(config)
            FileManager.default.createFile(atPath: configPath, contents: data)
        case .server:
            let server = try XcodeBuildServer(cacheDir: cacheDir)
            server.run()
        }
    }
}
