import Foundation

protocol XcodeBuildClient: Sendable {
    func list(checkCache: Bool) throws -> XcodeBuild.List
    func settingsForIndex(forScheme scheme: String, checkCache: Bool) throws -> XcodeBuild.SettingsForIndex
}

extension XcodeBuild: XcodeBuildClient {
}
