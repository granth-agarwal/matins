import Foundation
import Testing
import Popup
import Models

struct MeetingTests {
    @Test func plansOneRecheckAndTwoPopups() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let start = now.addingTimeInterval(1800)
        let event = SourceRecord(id: "a", accountID: "fixture", source: .calendar, title: "Meeting", start: start, end: start.addingTimeInterval(1800))
        let plan = MeetingPolicy.plan(event, now: now, minutesBefore: [10, 2], rechecked: false)
        #expect(plan.map(\.kind) == [.recheck, .popup, .popup])
        #expect(plan.map(\.date) == [-900.0, -600.0, -120.0].map { start.addingTimeInterval($0) })
        #expect(MeetingPolicy.plan(event, now: now, minutesBefore: [10, 2], rechecked: true).count == 2)
        var moved = event; moved.start = start.addingTimeInterval(3600)
        #expect(MeetingPolicy.plan(moved, now: now, minutesBefore: [10, 2], rechecked: true).first?.date == moved.start!.addingTimeInterval(-600))
    }
    @Test func excludesAllDayAndExpiredAndDoesNotReplayMissedPopups() {
        let now = Date()
        var event = SourceRecord(id: "a", accountID: "fixture", source: .calendar, title: "Meeting", start: now.addingTimeInterval(60))
        #expect(MeetingPolicy.plan(event, now: now, minutesBefore: [10, 2], rechecked: false).map(\.kind) == [.recheck])
        event.allDay = true
        #expect(MeetingPolicy.plan(event, now: now, minutesBefore: [10, 2], rechecked: false).isEmpty)
        event.allDay = false; event.start = now.addingTimeInterval(-301)
        #expect(MeetingPolicy.plan(event, now: now, minutesBefore: [10, 2], rechecked: false).isEmpty)
    }
    @Test func quietHoursSupportOvernightAndExactBoundaries() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func quiet(_ time: String, hours: [String] = ["22:00-08:00"]) -> Bool {
            let date = ISO8601DateFormatter().date(from: "2026-10-26T" + time + ":00Z")!
            return MeetingPolicy.quiet(now: date, enabled: true, quietMode: false, hours: hours, calendar: calendar)
        }
        #expect(quiet("22:00")); #expect(quiet("07:59")); #expect(!quiet("08:00")); #expect(!quiet("12:00"))
        #expect(quiet("12:00", hours: ["bad"]))
        #expect(MeetingPolicy.quiet(now: Date(), enabled: false, quietMode: false, hours: []))
        #expect(MeetingPolicy.quiet(now: Date(), enabled: true, quietMode: true, hours: []))
    }
}
