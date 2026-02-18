import Foundation

protocol XcodeBuildClient: Sendable {
    func list(checkCache: Bool) throws -> XcodeBuild.List
    func settingsForScheme(_ scheme: String, checkCache: Bool) throws -> [XcodeBuild.Settings]
    func settingsForIndex(forScheme scheme: String, checkCache: Bool) throws -> XcodeBuild.SettingsForIndex
}

extension XcodeBuild: XcodeBuildClient {
}
