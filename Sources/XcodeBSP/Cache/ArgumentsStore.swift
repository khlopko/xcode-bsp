import Foundation

protocol ArgumentsStore: Sendable {
    func fetchArgs(filePath: String, scheme: String) async throws -> [String]
    func updateArgs(argsByFilePaths: [String: [String]], scheme: String) async throws
}

extension Database: ArgumentsStore {
}
