import Foundation
import Logging

struct XcodeBuild {
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
    func list() throws -> List {
        let output = try shell("xcodebuild -json -list")
        let list = try decoder.decode(List.self, from: output.data)
        logger.trace("\(output.command): \(list)")
        return list
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
    func settingsForScheme(_ scheme: String) throws -> [Settings] {
        let output = try shell("xcodebuild -json -showBuildSettings -scheme \(scheme) 2>/dev/null")
        let settings = try decoder.decode([Settings].self, from: output.data)
        logger.trace("\(output.command): \(settings)")
        return settings
    }
}

extension XcodeBuild {
    typealias SettingsForIndex = [String: [String: FileSettings]]

    struct FileSettings: Decodable {
        let swiftASTCommandArguments: [String]
    }
}

extension XcodeBuild {
    func settingsForIndex(forScheme scheme: String) throws -> SettingsForIndex {
        let output = try shell("xcodebuild -json -showBuildSettingsForIndex -scheme \(scheme) 2>/dev/null")
        let settings = try decoder.decode(SettingsForIndex.self, from: output.data)
        logger.trace("\(output.command): \(settings)")
        return settings
    }
}

