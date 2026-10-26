import Foundation
import Testing
import Sync
import Store
import Models

struct SourceSyncTests {
    @Test func gmailCapturesCheckpointBeforeListingAndResumesHistory() async throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let http = FixtureHTTP([response(#"{"historyId":"10"}"#), response(#"{"messages":[{"id":"m"}]}"#),
            response(#"{"id":"m","threadId":"t","labelIds":["INBOX"],"internalDate":"1793000000000","payload":{"mimeType":"text/plain","headers":[{"name":"Subject","value":"Reply today"}],"body":{"data":"SGVsbG8"}}}"#),
            response(#"{"historyId":"11","history":[{"messagesDeleted":[{"message":{"id":"m"}}]}]}"#)])
        let sync = GmailSync(api: API(token: "test", transport: http), store: store)
        try await sync.sync()
        #expect(try store.records().first?.body == "Hello")
        try await sync.sync()
        #expect(try store.records().isEmpty)
        #expect(try store.checkpoint(account: "google", source: .gmail) == "11")
        #expect(await http.urls.last?.absoluteString.contains("startHistoryId=10") == true)
    }
    @Test func gmailExpiredHistoryFallsBack() async throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        try store.commit(account: "google", source: .gmail, records: [], checkpoint: "old")
        let http = FixtureHTTP([response("{}", status: 404), response(#"{"historyId":"new"}"#), response("{}")])
        try await GmailSync(api: API(token: "test", transport: http), store: store).sync()
        #expect(try store.checkpoint(account: "google", source: .gmail) == "new")
    }
    @Test func driveResumesAndRemovesFiles() async throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let http = FixtureHTTP([response(#"{"startPageToken":"one"}"#), response(#"{"files":[{"id":"d","name":"Meet notes","mimeType":"text/plain"}]}"#), response(#"{"changes":[{"fileId":"d","removed":true}],"newStartPageToken":"two"}"#)])
        let sync = DriveSync(api: API(token: "test", transport: http), store: store)
        try await sync.sync(); #expect(try store.records().count == 1)
        try await sync.sync(); #expect(try store.records().isEmpty)
        #expect(try store.checkpoint(account: "google", source: .drive) == "two")
    }
    @Test func githubNotModifiedStillRefreshesAssignments() async throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let empty = #"{"items":[],"total_count":0,"incomplete_results":false}"#
        let http = FixtureHTTP([response("[]"), response(empty), response(empty), response("", status: 304), response(empty), response(empty)])
        let sync = GitHubSync(api: API(token: "test", transport: http), store: store)
        try await sync.sync(); try await sync.sync()
        #expect(await http.urls.count == 6)
        #expect(try store.checkpoint(account: "github", source: .github) != nil)
    }
    @Test func sourceFailuresAreIndependent() async {
        let result = await SyncCoordinator.run([SyncJob(.gmail) { throw SyncError.status(403) }, SyncJob(.calendar) {}])
        #expect(result.failed == [.gmail]); #expect(result.succeeded == [.calendar])
    }
    @Test func normalizationRemovesHTMLQuotesAndCapsBodies() {
        #expect(TextNormalizer.clean("<p>Hello</p>\n> quoted") == "Hello")
        #expect(TextNormalizer.clean(String(repeating: "x", count: 1400)).count == 1200)
        #expect(TextNormalizer.clean("Hello\nSent from my phone\nfooter") == "Hello")
    }
}
