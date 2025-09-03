import Foundation
import Logging

struct XcodeBuild {
    let cacheDir: URL
    let decoder: JSONDecoder
    let logger: Logger
}

extension XcodeBuild {
    struct List: Decodable {
        let project: Project
    }
}

extension XcodeBuild.List {
    struct Project: Decodable {
        let name: String
        let schemes: [String]
        let targets: [String]
    }
}

extension XcodeBuild {
    func list(checkCache: Bool = true) throws -> List {
        let data = try exec(command: "-list", cacheURL: listCacheURL(), checkCache: checkCache)
        let list = try decoder.decode(List.self, from: data)
        return list
    }

    private func listCacheURL() -> URL {
        // this will overwrite setting for multiple projects, need to revisit it soon
        let url = cacheDir.appending(component: "list.json")
        if FileManager.default.fileExists(atPath: url.path()) == false {
            FileManager.default.createFile(atPath: url.path(), contents: nil)
        }
        return url
    }
}

extension XcodeBuild {
    struct Settings: Decodable {
        let target: String
        let action: String
        let buildSettings: BuildSettings
    }
}

extension XcodeBuild.Settings {
    struct BuildSettings: Decodable {
        let BUILD_DIR: String
        let BUILD_ROOT: String
        let PROJECT: String
        let SOURCE_ROOT: String
        let TARGET_NAME: String
    }
}

extension XcodeBuild {
    func settingsForScheme(_ scheme: String, checkCache: Bool = true) throws -> [Settings] {
        let data = try exec(
            command: "-showBuildSettings -scheme \(scheme) 2>/dev/null",
            cacheURL: settingsCacheURL(forScheme: scheme),
            checkCache: checkCache
        )
        let settings = try decoder.decode([Settings].self, from: data)
        return settings
    }
    
    private func settingsCacheURL(forScheme scheme: String) -> URL {
        let url = cacheDir.appending(component: "\(scheme)-settings.json")
        if FileManager.default.fileExists(atPath: url.path()) == false {
            FileManager.default.createFile(atPath: url.path(), contents: nil)
        }
        return url
    }
}

extension XcodeBuild {
    typealias SettingsForIndex = [String: [String: FileSettings]]

    struct FileSettings: Decodable {
        let swiftASTCommandArguments: [String]?
        let clangASTCommandArguments: [String]?
        let clangPCHCommandArguments: [String]?
    }
}

extension XcodeBuild {
    func settingsForIndex(forScheme scheme: String, checkCache: Bool = true) throws -> SettingsForIndex {
        let data = try exec(
            command: "-showBuildSettingsForIndex -scheme \(scheme) 2>/dev/null",
            cacheURL: settingsForIndexCacheURL(forScheme: scheme),
            checkCache: checkCache
        )
        let settings = try decoder.decode(SettingsForIndex.self, from: data)
        return settings
    }

    private func settingsForIndexCacheURL(forScheme scheme: String) -> URL {
        let url = cacheDir.appending(component: "\(scheme)-settingsForIndex.json")
        if FileManager.default.fileExists(atPath: url.path()) == false {
            FileManager.default.createFile(atPath: url.path(), contents: nil)
        }
        return url
    }
}

extension XcodeBuild {
    private struct NoCacheError: Error {
    }

    private func exec(command: String, cacheURL: URL, checkCache: Bool) throws -> Data {
        do {
            guard checkCache else {
                throw NoCacheError()
            }

            let handle = try FileHandle(forReadingFrom: cacheURL)
            guard let cachedData = try handle.readToEnd() else {
                throw NoCacheError()
            }

            return cachedData
        }
        catch {
            let output = try shell("xcodebuild -json \(command)", output: cacheURL)
            return output.data
        }
    }
}
