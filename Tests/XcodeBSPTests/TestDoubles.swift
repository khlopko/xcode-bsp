import Foundation
import Logging
@testable import XcodeBSP

struct StaticConfigProvider: ConfigProvider {
    let config: Config

    func load(decoder: JSONDecoder) throws -> Config {
        return config
    }
}

struct FailingConfigProvider: ConfigProvider {
    struct StubError: Error {
    }

    func load(decoder: JSONDecoder) throws -> Config {
        throw StubError()
    }
}

final class StubXcodeBuildClient: @unchecked Sendable {
    private let lock = NSLock()

    private(set) var listCallCount: Int
    private(set) var settingsForSchemeCalls: [(scheme: String, checkCache: Bool)]
    private(set) var settingsForIndexCalls: [(scheme: String, checkCache: Bool)]

    var listResult: XcodeBuild.List
    var settingsForSchemeByScheme: [String: [XcodeBuild.Settings]]
    var settingsForIndexByScheme: [String: XcodeBuild.SettingsForIndex]
    var settingsForIndexBySchemeAndCache: [String: [Bool: XcodeBuild.SettingsForIndex]]

    init(
        listResult: XcodeBuild.List,
        settingsForSchemeByScheme: [String: [XcodeBuild.Settings]] = [:],
        settingsForIndexByScheme: [String: XcodeBuild.SettingsForIndex] = [:],
        settingsForIndexBySchemeAndCache: [String: [Bool: XcodeBuild.SettingsForIndex]] = [:]
    ) {
        self.listResult = listResult
        self.settingsForSchemeByScheme = settingsForSchemeByScheme
        self.settingsForIndexByScheme = settingsForIndexByScheme
        self.settingsForIndexBySchemeAndCache = settingsForIndexBySchemeAndCache
        listCallCount = 0
        settingsForSchemeCalls = []
        settingsForIndexCalls = []
    }
}

extension StubXcodeBuildClient: XcodeBuildClient {
    func list(checkCache: Bool) throws -> XcodeBuild.List {
        lock.lock()
        listCallCount += 1
        lock.unlock()
        return listResult
    }

    func settingsForScheme(_ scheme: String, checkCache: Bool) throws -> [XcodeBuild.Settings] {
        lock.lock()
        settingsForSchemeCalls.append((scheme, checkCache))
        lock.unlock()
        return settingsForSchemeByScheme[scheme] ?? []
    }

    func settingsForIndex(forScheme scheme: String, checkCache: Bool) throws -> XcodeBuild.SettingsForIndex {
        lock.lock()
        settingsForIndexCalls.append((scheme, checkCache))
        lock.unlock()
        if let byCache = settingsForIndexBySchemeAndCache[scheme], let value = byCache[checkCache] {
            return value
        }
        return settingsForIndexByScheme[scheme] ?? [:]
    }
}

actor InMemoryArgumentsStore: ArgumentsStore {
    private var valuesByScheme: [String: [String: [String]]] = [:]
    private(set) var updateCallCount: Int = 0

    func seed(filePath: String, scheme: String, arguments: [String]) {
        var schemeValues = valuesByScheme[scheme] ?? [:]
        schemeValues[filePath] = arguments
        valuesByScheme[scheme] = schemeValues
    }

    func fetchArgs(filePath: String, scheme: String) async throws -> [String] {
        if let arguments = valuesByScheme[scheme]?[filePath] {
            return arguments
        }

        throw Database.NotFoundError()
    }

    func updateArgs(argsByFilePaths: [String: [String]], scheme: String) async throws {
        updateCallCount += 1
        valuesByScheme[scheme] = argsByFilePaths
    }

    func args(filePath: String, scheme: String) -> [String]? {
        return valuesByScheme[scheme]?[filePath]
    }
}

func makeTestLogger() -> Logger {
    return Logger(label: "xcode-bsp.tests")
}
