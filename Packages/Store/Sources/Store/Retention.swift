import Foundation
import GRDB
import Models
import Brief

extension BriefStore {
    static func preserveTasks(_ brief: BriefDocument, now: Date, db: Database) throws {
        for todo in brief.todos {
            try db.execute(sql: "INSERT OR IGNORE INTO tasks(id,title,checked,created_at,updated_at) VALUES (?,?,0,?,?)", arguments: [todo.id, todo.title, now.timeIntervalSince1970, now.timeIntervalSince1970])
        }
    }
    public func carryOver(now: Date = Date(), excluding: Set<String> = []) throws -> [CarryOver] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id,title,created_at FROM tasks WHERE checked=0 AND created_at<? ORDER BY created_at,id", arguments: [Calendar.current.startOfDay(for: now).timeIntervalSince1970]).compactMap { row in
                let id: String = row["id"]
                guard !excluding.contains(id) else { return nil }
                let created = Date(timeIntervalSince1970: row["created_at"])
                let age = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: created), to: Calendar.current.startOfDay(for: now)).day ?? 0
                return CarryOver(id: id, title: row["title"], age_days: max(1, age))
            }
        }
    }
    public func prune(retentionDays: Int, now: Date = Date()) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, retentionDays), to: now)!
        try database.write { db in
            try db.execute(sql: "PRAGMA secure_delete=ON")
            let rows = try Row.fetchAll(db, sql: "SELECT payload,created_at FROM briefs WHERE created_at<?", arguments: [cutoff.timeIntervalSince1970])
            for row in rows {
                let brief = try JSONDecoder().decode(BriefDocument.self, from: row["payload"])
                try Self.preserveTasks(brief, now: Date(timeIntervalSince1970: row["created_at"]), db: db)
            }
            try db.execute(sql: "DELETE FROM briefs WHERE created_at<?", arguments: [cutoff.timeIntervalSince1970])
            for table in ["events", "threads", "drive_files", "github_items"] {
                let rows = try Row.fetchAll(db, sql: "SELECT payload FROM \(table) WHERE updated_at<?", arguments: [cutoff.timeIntervalSince1970])
                for row in rows {
                    var record = try JSONDecoder().decode(SourceRecord.self, from: row["payload"])
                    if !record.isOpen || (record.source == .calendar && (record.end ?? .distantPast) < cutoff) {
                        try db.execute(sql: "DELETE FROM \(table) WHERE account_id=? AND scope=? AND id=?", arguments: [record.accountID, record.scope, record.id])
                    } else {
                        record.body = ""
                        try db.execute(sql: "UPDATE \(table) SET payload=? WHERE account_id=? AND scope=? AND id=?", arguments: [try JSONEncoder().encode(record), record.accountID, record.scope, record.id])
                    }
                }
            }
            let staleKeys = try String.fetchAll(db, sql: "SELECT key FROM meta WHERE key LIKE 'meetingState:%'")
            for key in staleKeys where String(key.dropFirst("meetingState:".count)) < Dates.day(cutoff) {
                try db.execute(sql: "DELETE FROM meta WHERE key=?", arguments: [key])
            }
        }
        try database.writeWithoutTransaction { try $0.execute(sql: "VACUUM") }
    }
    public func deleteAccount(_ id: String) throws {
        try database.write { db in
            try db.execute(sql: "PRAGMA secure_delete=ON")
            try db.execute(sql: "DELETE FROM accounts WHERE id=?", arguments: [id])
            try db.execute(sql: "DELETE FROM briefs")
            try db.execute(sql: "DELETE FROM tasks WHERE id LIKE ?", arguments: [id + "|%"])
            try db.execute(sql: "DELETE FROM meta WHERE key LIKE 'meetingState:%' OR key LIKE ?", arguments: ["calendarWindow:" + id + ":%"])
        }
        try database.writeWithoutTransaction { try $0.execute(sql: "VACUUM") }
    }
    public func deleteAllData() throws {
        try database.write { db in
            try db.execute(sql: "PRAGMA secure_delete=ON")
            for table in ["accounts", "briefs", "tasks", "meta"] { try db.execute(sql: "DELETE FROM \(table)") }
            try db.execute(sql: "INSERT INTO meta(key,value) VALUES ('schema','skeleton_v1')")
        }
        try database.writeWithoutTransaction { try $0.execute(sql: "VACUUM") }
    }
    public func close() throws { try database.close() }
}
