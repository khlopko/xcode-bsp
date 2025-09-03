import Foundation
import SQLite

actor Database {
    private let conn: Connection

    init(cacheDir: URL) throws {
        let path = cacheDir.appending(component: "options.sqlite3").path()
        print(path)
        if FileManager.default.fileExists(atPath: path) == false {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        conn = try Connection(path)
        print("created")

        try conn.execute(
            """
            CREATE TABLE IF NOT EXISTS arguments (
                id INTEGER PRIMARY KEY NOT NULL,
                scheme TEXT,
                path TEXT,
                list TEXT
            );
            """
        )
    }
}

extension Database {
    struct NotFoundError: Error {
    }

    func fetchArgs(filePath: String, scheme: String) throws -> [String] {
        let stmt = try conn.prepare("SELECT list FROM arguments WHERE filePath = ? AND scheme = ? LIMIT 1").run(filePath, scheme)
        guard let row = stmt.next(), let values = row[0] as? String else {
            throw NotFoundError()
        }
        return values.split(separator: ",").map { String($0) }
    }

    func updateArgs(argsByFilePaths: [String: [String]], scheme: String) throws {
        try conn.transaction {
            for (path, values) in argsByFilePaths {
                let valuesConj = values.joined(separator: ",")
                try conn.prepare("INSERT INTO arguments (scheme, path, list) VALUES (?, ?, ?)").run(scheme, path, valuesConj)
            }
        }
    }
}
