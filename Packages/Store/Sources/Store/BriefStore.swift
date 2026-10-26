import Foundation
import GRDB

public final class BriefStore: Sendable {
    private let database: DatabaseQueue

    public init(url: URL) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        database = try DatabaseQueue(path: url.path, configuration: configuration)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("skeleton_v1") { db in
            try db.create(table: "accounts") { table in
                table.column("id", .text).primaryKey()
                table.column("provider", .text).notNull()
                table.column("display_name", .text)
            }
            try db.create(table: "sync_state") { table in
                table.column("account_id", .text).notNull().references("accounts", onDelete: .cascade)
                table.column("source", .text).notNull()
                table.column("scope", .text).notNull()
                table.column("checkpoint", .text)
                table.column("updated_at", .datetime).notNull()
                table.primaryKey(["account_id", "source", "scope"])
            }
            try db.create(table: "meta") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }
            try db.execute(sql: "INSERT INTO meta (key, value) VALUES (?, ?)", arguments: ["schema", "skeleton_v1"])
        }
        try migrator.migrate(database)
    }

    public func schemaVersion() throws -> String? {
        try database.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: ["schema"])
        }
    }
}
