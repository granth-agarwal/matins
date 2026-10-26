import Foundation
import Testing
import Brief
import Models

struct StickerTests {
    @Test func explicitActionMakesOneGroundedCall() async throws {
        let record = SourceRecord(id: "a", accountID: "fixture", source: .calendar, title: "Review launch plan", body: "Confirm owners and review open questions", attachmentIDs: ["notes"])
        let linked = SourceRecord(id: "notes", accountID: "fixture", source: .drive, title: "Launch notes")
        let unrelated = SourceRecord(id: "secret", accountID: "other", source: .drive, title: "Other account")
        let note = PrepNote(source_id: record.key, bullets: ["Confirm owners and review open questions"])
        let provider = FixtureProvider(String(decoding: try JSONEncoder().encode(note), as: UTF8.self))
        let result = await StickerAction().run(key: record.key, records: [record, linked, unrelated], provider: provider)
        #expect(!result.usedFallback)
        #expect(result.note == note)
        #expect(await provider.calls == 1)
        #expect(StickerAction.context(key: record.key, records: [record, linked, unrelated]).count == 2)
    }
    @Test func inventedPrepFallsBackAndMissingSourceMakesNoCall() async {
        let record = SourceRecord(id: "a", accountID: "fixture", source: .gmail, title: "Review proposal")
        let provider = FixtureProvider("{\"source_id\":\"\(record.key)\",\"bullets\":[\"Meet invented person at noon\"]}")
        let result = await StickerAction().run(key: record.key, records: [record], provider: provider)
        #expect(result.usedFallback)
        #expect(result.note.bullets == ["Review proposal"])
        let missing = await StickerAction().run(key: "missing", records: [], provider: provider)
        #expect(missing.usedFallback)
        #expect(await provider.calls == 1)
    }
}
