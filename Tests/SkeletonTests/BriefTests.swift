import Foundation
import Testing
import Brief
import Models

actor FixtureProvider: ModelProvider {
    let output: String
    var calls = 0
    init(_ output: String) { self.output = output }
    func respond(instructions: String, input: String) async throws -> String { calls += 1; return output }
}
struct BriefTests {
    @Test func twentyFixtureDaysProduceGroundedJSON() async throws {
        struct Day: Decodable { let date, title, source: String; let empty: Bool }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/days.json")
        let days = try JSONDecoder().decode([Day].self, from: Data(contentsOf: url))
        #expect(days.count == 20)
        for (index, day) in days.enumerated() {
            let now = Dates.parse(day.date + "T10:00:00Z")!
            let source = Source(rawValue: day.source)!
            let record = SourceRecord(id: "fixture-\(index)", accountID: "fixture", source: source,
                title: day.title, url: "https://example.test/item/\(index)", updated: now,
                start: source == .calendar ? now : nil, end: source == .calendar ? now.addingTimeInterval(3600) : nil)
            let records = day.empty ? [] : [record]
            let baseline = BriefGenerator.fallback(records: records, now: now, succeeded: [source.rawValue], failed: [])
            let data = try JSONEncoder().encode(baseline)
            let provider = FixtureProvider(String(decoding: data, as: UTF8.self))
            let result = await BriefGenerator().generate(records: records, now: now, succeeded: [source.rawValue], failed: [], provider: provider)
            #expect(!result.usedFallback)
            try BriefGenerator.validate(result.document, records: records, baseline: baseline)
            #expect(await provider.calls == 1)
            #expect(try JSONDecoder().decode(BriefDocument.self, from: JSONEncoder().encode(result.document)) == baseline)
        }
    }
    @Test func invalidOutputFallsBackWithoutSecondModelCall() async {
        let provider = FixtureProvider("not JSON")
        let result = await BriefGenerator().generate(records: [], succeeded: [], failed: ["gmail"], provider: provider)
        #expect(result.usedFallback)
        #expect(result.document.failed_sources == ["gmail"])
        #expect(await provider.calls == 1)
    }
    @Test func inventedFactsAndWrongLinksAreRejected() throws {
        let now = Date()
        let record = SourceRecord(id: "a", accountID: "fixture", source: .gmail, title: "Review document", url: "https://example.test/a", updated: now)
        let baseline = BriefGenerator.fallback(records: [record], now: now, succeeded: ["gmail"], failed: [])
        var invalid = baseline; invalid.todos[0].source_url = "https://example.test/forged"
        #expect(throws: ModelError.self) { try BriefGenerator.validate(invalid, records: [record], baseline: baseline) }
        invalid = baseline; invalid.focus.title = "Meet invented person at noon"
        #expect(throws: ModelError.self) { try BriefGenerator.validate(invalid, records: [record], baseline: baseline) }
    }
    @Test func oldItemsDoNotReachModel() {
        let now = Date()
        let old = SourceRecord(id: "old", accountID: "fixture", source: .gmail, title: "Old", updated: now.addingTimeInterval(-4 * 86400))
        #expect(BriefGenerator.eligible([old], now: now).isEmpty)
    }
}
