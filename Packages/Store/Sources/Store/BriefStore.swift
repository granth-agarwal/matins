import Foundation
import GRDB
import Models
import Brief

public final class BriefStore: Sendable {
    let database: DatabaseQueue

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
        migrator.registerMigration("source_records_v2") { db in
            for table in ["events", "threads", "drive_files", "github_items"] {
                try db.execute(sql: "CREATE TABLE \(table) (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, scope TEXT NOT NULL, id TEXT NOT NULL, payload BLOB NOT NULL, updated_at DOUBLE NOT NULL, PRIMARY KEY(account_id, scope, id))")
            }
        }
        migrator.registerMigration("briefs_v3") { db in
            try db.execute(sql: "CREATE TABLE briefs (date TEXT PRIMARY KEY, payload BLOB NOT NULL, created_at DOUBLE NOT NULL)")
        }
        migrator.registerMigration("tasks_v4") { db in
            try db.execute(sql: "CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL, checked INTEGER NOT NULL DEFAULT 0, created_at DOUBLE NOT NULL, updated_at DOUBLE NOT NULL)")
        }
        try migrator.migrate(database)
    }

    public func schemaVersion() throws -> String? {
        try database.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: ["schema"])
        }
    }
}

extension BriefStore {
    private func table(_ source: Source) -> String {
        switch source { case .calendar: "events"; case .gmail: "threads"; case .drive: "drive_files"; case .github: "github_items" }
    }
    public func checkpoint(account: String, source: Source, scope: String = "") throws -> String? {
        try database.read { db in
            try String.fetchOne(db, sql: "SELECT checkpoint FROM sync_state WHERE account_id=? AND source=? AND scope=?", arguments: [account, source.rawValue, scope])
        }
    }
    public func commit(account: String, source: Source, scope: String = "", records: [SourceRecord], deleted: [String] = [], checkpoint: String?, replace: Bool = false) throws {
        let table = table(source)
        try database.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO accounts(id,provider) VALUES (?,?)", arguments: [account, source == .github ? "github" : "google"])
            if replace { try db.execute(sql: "DELETE FROM \(table) WHERE account_id=? AND scope=?", arguments: [account, scope]) }
            for id in deleted { try db.execute(sql: "DELETE FROM \(table) WHERE account_id=? AND scope=? AND id=?", arguments: [account, scope, id]) }
            for record in records {
                guard record.accountID == account, record.source == source, record.scope == scope else { throw StoreError.wrongScope }
                let data = try JSONEncoder().encode(record)
                try db.execute(sql: "INSERT INTO \(table)(account_id,scope,id,payload,updated_at) VALUES (?,?,?,?,?) ON CONFLICT(account_id,scope,id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at", arguments: [account, scope, record.id, data, record.updated.timeIntervalSince1970])
            }
            if let checkpoint {
                try db.execute(sql: "INSERT INTO sync_state(account_id,source,scope,checkpoint,updated_at) VALUES (?,?,?,?,?) ON CONFLICT(account_id,source,scope) DO UPDATE SET checkpoint=excluded.checkpoint,updated_at=excluded.updated_at", arguments: [account, source.rawValue, scope, checkpoint, Date()])
            }
        }
    }
    public func records(source: Source? = nil) throws -> [SourceRecord] {
        try database.read { db in
            try (source.map { [$0] } ?? Source.allCases).flatMap { source in
                try Data.fetchAll(db, sql: "SELECT payload FROM \(table(source))").map { try JSONDecoder().decode(SourceRecord.self, from: $0) }
            }
        }
    }
    public func meta(_ key: String) throws -> String? {
        try database.read { try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key=?", arguments: [key]) }
    }
    public func setMeta(_ key: String, _ value: String) throws {
        try database.write { try $0.execute(sql: "INSERT INTO meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", arguments: [key, value]) }
    }
    public func saveBrief(date: String, data: Data, now: Date = Date()) throws {
        let brief = try JSONDecoder().decode(BriefDocument.self, from: data)
        try database.write { db in
            try db.execute(sql: "INSERT INTO briefs(date,payload,created_at) VALUES (?,?,?) ON CONFLICT(date) DO UPDATE SET payload=excluded.payload,created_at=excluded.created_at", arguments: [date, data, now.timeIntervalSince1970])
            try Self.preserveTasks(brief, now: now, db: db)
        }
    }
    public func brief(date: String) throws -> Data? {
        try database.read { try Data.fetchOne($0, sql: "SELECT payload FROM briefs WHERE date=?", arguments: [date]) }
    }
    public func setTask(id: String, title: String, checked: Bool, now: Date = Date()) throws {
        try database.write { try $0.execute(sql: "INSERT INTO tasks(id,title,checked,created_at,updated_at) VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,checked=excluded.checked,updated_at=excluded.updated_at", arguments: [id, title, checked, now.timeIntervalSince1970, now.timeIntervalSince1970]) }
    }
    public func taskStates() throws -> [String: Bool] {
        try database.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id,checked FROM tasks").map { ($0["id"] as String, $0["checked"] as Bool) })
        }
    }
}
public enum StoreError: Error { case wrongScope }
