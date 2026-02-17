import CryptoKit
import Foundation
import SQLite

actor Database {
    private let conn: Connection

    init(cacheDir: URL) throws {
        if FileManager.default.fileExists(atPath: cacheDir.path()) == false {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        let path = cacheDir.appending(component: "options.sqlite3").path()
        if FileManager.default.fileExists(atPath: path) == false {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        conn = try Connection(path)
        try conn.execute("PRAGMA foreign_keys = ON;")

        try Self.migrateIfNeeded(conn: conn)
        try Self.createTablesIfNeeded(conn: conn)
    }
}

extension Database {
    struct NotFoundError: Error {
    }

    private struct InvalidPayloadError: Error {
    }

    private struct MissingArgumentSetError: Error {
    }

    private struct InvalidEncodingError: Error {
    }

    func fetchArgs(filePath: String, scheme: String) throws -> [String] {
        let payload = try conn.scalar(
            """
            SELECT argument_sets.payload
            FROM file_arguments
            INNER JOIN argument_sets ON argument_sets.id = file_arguments.argument_set_id
            WHERE file_arguments.scheme = ? AND file_arguments.path = ?
            LIMIT 1
            """,
            scheme,
            filePath
        ) as? String

        guard let payload else {
            throw NotFoundError()
        }

        guard let payloadData = payload.data(using: .utf8) else {
            throw InvalidPayloadError()
        }

        return try JSONDecoder().decode([String].self, from: payloadData)
    }

    func updateArgs(argsByFilePaths: [String: [String]], scheme: String) throws {
        let encoder = JSONEncoder()

        try conn.transaction {
            try conn.prepare("DELETE FROM file_arguments WHERE scheme = ?").run(scheme)

            for (path, values) in argsByFilePaths {
                let payloadData = try encoder.encode(values)
                guard let payload = String(data: payloadData, encoding: .utf8) else {
                    throw InvalidEncodingError()
                }

                let hash = Self.sha256Hex(for: payloadData)

                try conn.prepare(
                    """
                    INSERT INTO argument_sets (hash, payload)
                    VALUES (?, ?)
                    ON CONFLICT(hash) DO NOTHING
                    """
                ).run(hash, payload)

                let argumentSetID = try conn.scalar(
                    "SELECT id FROM argument_sets WHERE hash = ? LIMIT 1",
                    hash
                ) as? Int64

                guard let argumentSetID else {
                    throw MissingArgumentSetError()
                }

                try conn.prepare(
                    """
                    INSERT INTO file_arguments (scheme, path, argument_set_id)
                    VALUES (?, ?, ?)
                    ON CONFLICT(scheme, path) DO UPDATE SET
                        argument_set_id = excluded.argument_set_id
                    """
                ).run(scheme, path, argumentSetID)
            }

            try conn.execute(
                "DELETE FROM argument_sets WHERE id NOT IN (SELECT DISTINCT argument_set_id FROM file_arguments)"
            )
        }
    }

    private static func migrateIfNeeded(conn: Connection) throws {
        guard try tableExists(named: "arguments", conn: conn) else {
            return
        }

        try conn.execute("DROP TABLE arguments")
        try conn.execute("VACUUM")
    }

    private static func createTablesIfNeeded(conn: Connection) throws {
        try conn.execute(
            """
            CREATE TABLE IF NOT EXISTS argument_sets (
                id INTEGER PRIMARY KEY NOT NULL,
                hash TEXT NOT NULL UNIQUE,
                payload TEXT NOT NULL
            );
            """
        )

        try conn.execute(
            """
            CREATE TABLE IF NOT EXISTS file_arguments (
                scheme TEXT NOT NULL,
                path TEXT NOT NULL,
                argument_set_id INTEGER NOT NULL,
                PRIMARY KEY (scheme, path),
                FOREIGN KEY (argument_set_id) REFERENCES argument_sets(id) ON DELETE CASCADE
            );
            """
        )

        try conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_file_arguments_argument_set_id
            ON file_arguments(argument_set_id);
            """
        )
    }

    private static func tableExists(named name: String, conn: Connection) throws -> Bool {
        let row = try conn.scalar(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
            name
        ) as? Int64

        return row == 1
    }

    private static func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
