import Foundation
import Testing
import Sync
import Store
import Models

actor FixtureHTTP: HTTPTransport {
    var results: [HTTPResult]
    var urls: [URL] = []
    init(_ results: [HTTPResult]) { self.results = results }
    func get(_ url: URL, token: String, etag: String?) async throws -> HTTPResult {
        urls.append(url)
        guard !results.isEmpty else { throw SyncError.invalidResponse }
        return results.removeFirst()
    }
}
func response(_ json: String, status: Int = 200) -> HTTPResult { HTTPResult(data: Data(json.utf8), status: status) }
func temporaryStore() throws -> (URL, BriefStore) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (root, try BriefStore(url: root.appendingPathComponent("test.sqlite")))
}
struct SyncTests {
    let event = #"{"id":"a","summary":"Standup","start":{"dateTime":"2026-10-26T09:00:00Z"},"end":{"dateTime":"2026-10-26T10:00:00Z"}}"#
    @Test func calendarPaginatesThenUsesTokenAndDeletes() async throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let http = FixtureHTTP([response("{\"items\":[\(event)],\"nextPageToken\":\"page2\"}"), response(#"{"nextSyncToken":"first"}"#), response(#"{"items":[{"id":"a","status":"cancelled"}],"nextSyncToken":"second"}"#)])
        let sync = CalendarSync(api: API(token: "fixture", transport: http), store: store)
        try await sync.sync()
        #expect(try store.records().count == 1)
        try await sync.sync()
        #expect(try store.records().isEmpty)
        #expect(try store.checkpoint(account: "google", source: .calendar, scope: "primary") == "second")
        let urls = await http.urls
        #expect(urls[2].absoluteString.contains("syncToken=first"))
        #expect(!urls[2].absoluteString.contains("timeMin"))
    }
    @Test func failedPageDoesNotCommitAndExpiredTokenReplaces() async throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let http = FixtureHTTP([response("{\"items\":[\(event)],\"nextPageToken\":\"next\"}"), response("{}", status: 500)])
        do { try await CalendarSync(api: API(token: "fixture", transport: http), store: store).sync(); Issue.record("Expected page failure") } catch {}
        #expect(try store.records().isEmpty)
        #expect(try store.checkpoint(account: "google", source: .calendar, scope: "primary") == nil)
        try store.commit(account: "google", source: .calendar, scope: "primary", records: [], checkpoint: "expired")
        let recovery = FixtureHTTP([response("{}", status: 410), response(#"{"nextSyncToken":"fresh"}"#)])
        try await CalendarSync(api: API(token: "fixture", transport: recovery), store: store).sync()
        #expect(try store.checkpoint(account: "google", source: .calendar, scope: "primary") == "fresh")
    }
    @Test func transactionRollsBackOnWrongAccount() throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let wrong = SourceRecord(id: "a", accountID: "other", source: .calendar, title: "Fixture")
        #expect(throws: StoreError.self) { try store.commit(account: "google", source: .calendar, records: [wrong], checkpoint: "bad") }
        #expect(try store.checkpoint(account: "google", source: .calendar) == nil)
    }
    @Test func allDayAndDeclinedParsing() throws {
        let allDay = try JSONDecoder().decode(CalendarEvent.self, from: Data(#"{"id":"d","start":{"date":"2026-10-26"},"end":{"date":"2026-10-27"}}"#.utf8))
        #expect(allDay.record(account: "google", calendar: "primary", zone: "Asia/Kolkata")?.allDay == true)
        let declined = try JSONDecoder().decode(CalendarEvent.self, from: Data(#"{"id":"d","attendees":[{"self":true,"responseStatus":"declined"}]}"#.utf8))
        #expect(declined.removed)
    }
}
