import Config
import Foundation
import Store
import Testing

struct StoreTests {
    @Test func createsSQLiteDatabaseAndReopensWithoutResettingIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try ApplicationPaths(directory: root)
        do {
            let store = try BriefStore(url: paths.database)
            #expect(try store.schemaVersion() == "skeleton_v1")
        }
        let reopened = try BriefStore(url: paths.database)
        #expect(try reopened.schemaVersion() == "skeleton_v1")
        let data = try Data(contentsOf: paths.database)
        #expect(String(decoding: data.prefix(15), as: UTF8.self) == "SQLite format 3")
        let attributes = try FileManager.default.attributesOfItem(atPath: paths.database.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
