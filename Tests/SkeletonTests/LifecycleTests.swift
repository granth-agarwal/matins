import Foundation
import Testing
import Config
import Store
import Models
import Brief
import UI
import Sync

struct LifecycleTests {
    @Test func settingsSaveRoundTripsPrivatelyAndRejectsInvalidChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try ApplicationPaths(directory: root)
        let loader = ConfigLoader(url: paths.config)
        var config = try loader.load()
        config.name = "Ada"; config.calendars = ["primary", "team@example.test"]
        config.oauth = AppConfig.OAuth(googleClientID: "public-client", githubClientID: "public-github")
        config.popups.quietMode = true; config.popups.quietHours = ["22:00-08:00"]
        config.palette.list = .custom([.init(name: "Custom", ground: "101010", glow1: "303030", glow2: "505050", accent: "FFF0DC")])
        try loader.save(config)
        let loaded = try loader.load()
        #expect(loaded.name == "Ada")
        #expect(loaded.calendars?.count == 2)
        #expect(loaded.oauth?.googleClientID == "public-client")
        #expect(loaded.popups.quietMode == true)
        if case .custom(let list) = loaded.palette.list { #expect(list.count == 1) } else { Issue.record("Lost custom palette") }
        let attributes = try FileManager.default.attributesOfItem(atPath: paths.config.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        config.triggerAfter = "25:00"
        #expect(throws: ConfigurationError.self) { try loader.save(config) }
        #expect(try loader.load().triggerAfter == "09:00")
        config.triggerAfter = "09:00"; config.popups.quietHours = ["invalid"]
        #expect(throws: ConfigurationError.self) { try loader.save(config) }
    }
    @Test func retentionKeepsUncheckedTasksAndClearsOldBodies() throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let old = now.addingTimeInterval(-10 * 86400)
        let open = SourceRecord(id: "open", accountID: "fixture", source: .gmail, title: "Review proposal", body: "Private fixture body", url: "https://example.test/open", updated: old)
        var closed = open; closed.id = "closed"; closed.isOpen = false
        try store.commit(account: "fixture", source: .gmail, records: [open, closed], checkpoint: "history")
        let brief = BriefGenerator.fallback(records: [SourceRecord(id: "open", accountID: "fixture", source: .gmail, title: "Review proposal", url: open.url, updated: old)], now: old, succeeded: ["gmail"], failed: [])
        try store.saveBrief(date: brief.date, data: JSONEncoder().encode(brief), now: old)
        try store.setTask(id: "checked", title: "Completed", checked: true, now: old)
        try store.prune(retentionDays: 7, now: now)
        #expect(try store.brief(date: brief.date) == nil)
        let records = try store.records()
        #expect(records.count == 1 && records[0].body.isEmpty)
        #expect(try store.checkpoint(account: "fixture", source: .gmail) == "history")
        let carry = try store.carryOver(now: now)
        #expect(carry.map(\.id) == [open.key])
        #expect(carry.first?.age_days == 10)
        #expect(try store.taskStates()["checked"] == true)
    }
    @Test func refreshingBriefDoesNotUncheckCompletedTasks() throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let record = SourceRecord(id: "a", accountID: "fixture", source: .github, title: "Review change", url: "https://example.test/a")
        let brief = BriefGenerator.fallback(records: [record], now: Date(), succeeded: [], failed: [])
        try store.setTask(id: record.key, title: record.title, checked: true)
        try store.saveBrief(date: brief.date, data: JSONEncoder().encode(brief))
        #expect(try store.taskStates()[record.key] == true)
    }
    @Test func deletionIsLocalAndAccountScoped() throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        for account in ["google:a", "google:b"] {
            let record = SourceRecord(id: "same", accountID: account, source: .gmail, title: "Fixture")
            try store.commit(account: account, source: .gmail, records: [record], checkpoint: "checkpoint")
            try store.setTask(id: record.key, title: record.title, checked: false)
        }
        try store.setMeta("onboarded", "true")
        try store.setMeta("lastShown", "2026-10-26")
        try store.setMeta("dailyAttempt", "2026-10-26")
        try store.deleteAccount("google:a")
        #expect(try store.records().map(\.accountID) == ["google:b"])
        #expect(try store.taskStates().count == 1)
        #expect(try store.meta("onboarded") == "true")
        #expect(try store.meta("lastShown") == "2026-10-26")
        #expect(try store.meta("dailyAttempt") == "2026-10-26")
        try store.deleteAllData()
        #expect(try store.records().isEmpty)
        #expect(try store.taskStates().isEmpty)
        #expect(try store.meta("onboarded") == nil)
        #expect(try store.schemaVersion() == "skeleton_v1")
    }
    @Test func calendarWindowAdvancesOnNewDayWithoutAnExtraSync() async throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let day = Dates.parse("2026-10-26T09:00:00Z")!
        let http = FixtureHTTP([response(#"{"nextSyncToken":"day1"}"#), response(#"{"nextSyncToken":"same-day"}"#), response(#"{"nextSyncToken":"day2"}"#)])
        let sync = CalendarSync(api: API(token: "fixture", transport: http), store: store)
        try await sync.sync(now: day); try await sync.sync(now: day)
        try await sync.sync(now: day.addingTimeInterval(86400))
        let urls = await http.urls
        #expect(urls.count == 3)
        #expect(urls[1].absoluteString.contains("syncToken=day1"))
        #expect(urls[2].absoluteString.contains("timeMin="))
        #expect(!urls[2].absoluteString.contains("syncToken="))
    }
    @Test func heroContrastIncludesEveryGlowExtreme() {
        for palette in BriefPalette.defaults {
            #expect(BriefPalette.contrast(palette.accent, palette.heroBackground(shade: palette.heroShade)) >= 3)
        }
    }
    @Test func modelJSONRejectsUnknownFieldsAndEncodesNullDue() throws {
        let record = SourceRecord(id: "fixture", accountID: "fixture", source: .gmail, title: "Review proposal", url: "https://example.test/a")
        let brief = BriefGenerator.fallback(records: [record], now: Date(), succeeded: [], failed: [])
        let data = try JSONEncoder().encode(brief)
        #expect(try BriefJSON.decode(data) == brief)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let todos = try #require(object["todos"] as? [[String: Any]])
        #expect(todos[0]["due"] is NSNull)
        object["invented_field"] = true
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ModelError.self) { try BriefJSON.decode(invalid) }
    }
    @Test func normalizerRemovesHTMLReplyAndSignatureBlocks() {
        #expect(TextNormalizer.clean("<p>Hello</p><blockquote>Old email</blockquote>") == "Hello")
        #expect(TextNormalizer.clean("<p>Hello</p><div class='gmail_signature'>Signature</div>") == "Hello")
    }
    @Test func driveIncludesFreshCalendarAttachmentsInTheSameRun() async throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let http = FixtureHTTP([response(#"{"startPageToken":"first"}"#), response(#"{"files":[]}"#), response(#"{"id":"linked","name":"Project outline","mimeType":"text/plain"}"#)])
        try await DriveSync(api: API(token: "fixture", transport: http), store: store).sync(freshAttachments: { ["linked"] })
        #expect(try store.records(source: .drive).first?.id == "linked")
        #expect(try store.checkpoint(account: "google", source: .drive) == "first")
        #expect(await http.urls.count == 3)
    }
}
