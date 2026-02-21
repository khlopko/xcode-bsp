import CryptoKit
import Foundation
import Logging

final class XcodeBuild: @unchecked Sendable {
    let cacheDir: URL
    let decoder: JSONDecoder
    let logger: Logger

    private let lock: NSLock
    private let workspaceCachePrefix: String

    private var listMemoryCache: Data?
    private var settingsMemoryCache: [String: Data]
    private var settingsForIndexMemoryCache: [String: Data]

    init(cacheDir: URL, decoder: JSONDecoder, logger: Logger) {
        self.cacheDir = cacheDir
        self.decoder = decoder
        self.logger = logger

        lock = NSLock()
        settingsMemoryCache = [:]
        settingsForIndexMemoryCache = [:]

        let workspacePath = FileManager.default.currentDirectoryPath
        let workspaceDigest = Self.sha256Hex(for: Data(workspacePath.utf8))
        workspaceCachePrefix = "\(URL(filePath: workspacePath).lastPathComponent)-\(workspaceDigest.prefix(12))"
    }
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
        if checkCache, let data = withLock({ listMemoryCache }) {
            return try decoder.decode(List.self, from: data)
        }

        let cacheURL = listCacheURL()
        do {
            let data = try exec(command: "-list", cacheURL: cacheURL, checkCache: checkCache)
            let list = try decoder.decode(List.self, from: data)
            if checkCache {
                withLock {
                    listMemoryCache = data
                }
            }
            return list
        } catch {
            guard checkCache else {
                throw error
            }

            let data = try exec(command: "-list", cacheURL: cacheURL, checkCache: false)
            let list = try decoder.decode(List.self, from: data)
            withLock {
                listMemoryCache = data
            }
            return list
        }
    }

    private func listCacheURL() -> URL {
        return cacheURL(fileName: "list.json")
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
        if checkCache, let data = withLock({ settingsMemoryCache[scheme] }) {
            return try decoder.decode([Settings].self, from: data)
        }

        let cacheURL = settingsCacheURL(forScheme: scheme)
        do {
            let data = try exec(
                command: "-showBuildSettings -scheme \"\(scheme)\" 2>/dev/null",
                cacheURL: cacheURL,
                checkCache: checkCache
            )
            let settings = try decoder.decode([Settings].self, from: data)
            if checkCache {
                withLock {
                    settingsMemoryCache[scheme] = data
                }
            }
            return settings
        } catch {
            guard checkCache else {
                throw error
            }

            let data = try exec(
                command: "-showBuildSettings -scheme \"\(scheme)\" 2>/dev/null",
                cacheURL: cacheURL,
                checkCache: false
            )
            let settings = try decoder.decode([Settings].self, from: data)
            withLock {
                settingsMemoryCache[scheme] = data
            }
            return settings
        }
    }
    
    private func settingsCacheURL(forScheme scheme: String) -> URL {
        return cacheURL(fileName: "\(cacheToken(forScheme: scheme))-settings.json")
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
        let cacheURL = settingsForIndexCacheURL(forScheme: scheme)

        if checkCache {
            if let data = withLock({ settingsForIndexMemoryCache[scheme] }) {
                return (try? decoder.decode(SettingsForIndex.self, from: data)) ?? [:]
            }

            guard
                let cachedData = try? Data(contentsOf: cacheURL),
                cachedData.isEmpty == false,
                let decoded = try? decoder.decode(SettingsForIndex.self, from: cachedData)
            else {
                logger.trace("settingsForIndex cache miss for scheme \(scheme)")
                return [:]
            }

            withLock {
                settingsForIndexMemoryCache[scheme] = cachedData
            }
            return decoded
        }

        let data = try exec(
            command: "-showBuildSettingsForIndex -scheme \"\(scheme)\" 2>/dev/null",
            cacheURL: cacheURL,
            checkCache: false
        )
        let settings = try decoder.decode(SettingsForIndex.self, from: data)
        withLock {
            settingsForIndexMemoryCache[scheme] = data
        }
        return settings
    }

    private func settingsForIndexCacheURL(forScheme scheme: String) -> URL {
        return cacheURL(fileName: "\(cacheToken(forScheme: scheme))-settingsForIndex.json")
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
            if FileManager.default.fileExists(atPath: cacheURL.path()) == false {
                FileManager.default.createFile(atPath: cacheURL.path(), contents: nil)
            }
            let output = try shell("xcodebuild -json \(command)", output: cacheURL)
            return output.data
        }
    }

    private func cacheURL(fileName: String) -> URL {
        let url = cacheDir.appending(component: "\(workspaceCachePrefix)-\(fileName)")
        if FileManager.default.fileExists(atPath: url.path()) == false {
            FileManager.default.createFile(atPath: url.path(), contents: nil)
        }
        return url
    }

    private func cacheToken(forScheme scheme: String) -> String {
        let normalized = scheme
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let digest = Self.sha256Hex(for: Data(scheme.utf8))
        return "\(normalized)-\(digest.prefix(8))"
    }

    private func withLock<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }

    private static func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func warmupBuild(forScheme scheme: String) throws {
        let escapedScheme = scheme.replacingOccurrences(of: "\"", with: "\\\"")
        _ = try? shell("xcodebuild -scheme \"\(escapedScheme)\" -resolvePackageDependencies >/dev/null 2>&1")
        _ = try shell(
            """
            xcodebuild -scheme "\(escapedScheme)" build \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO >/dev/null 2>&1
            """
        )
    }
}
