import Foundation
import Testing
import Trigger

struct TriggerTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var utc: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar }
    @Test func evaluatesEveryGateAndExclusiveLatestTime() {
        let now = date("2026-10-26T09:00:00Z")
        func eligible(_ now: Date, last: String? = nil, awake: Bool = true, unlocked: Bool = true, require: Bool = true) -> Bool {
            TriggerRules.shouldRun(now: now, after: "09:00", latest: "16:00", skip: ["sat", "sun"],
                requireUnlocked: require, lastShown: last, displayAwake: awake, sessionUnlocked: unlocked, calendar: utc)
        }
        #expect(eligible(now))
        #expect(!eligible(date("2026-10-26T08:59:59Z")))
        #expect(!eligible(date("2026-10-26T16:00:00Z")))
        #expect(!eligible(now, last: "2026-10-26"))
        #expect(eligible(now, last: "2026-10-25"))
        #expect(!eligible(now, awake: false))
        #expect(!eligible(now, unlocked: false))
        #expect(eligible(now, unlocked: false, require: false))
        #expect(!eligible(date("2026-10-25T10:00:00Z")))
    }
    @Test func nextTriggerHandlesDSTAndClockChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let spring = TriggerRules.nextTrigger(now: date("2026-03-08T06:00:00Z"), after: "02:30", calendar: calendar)!
        #expect(calendar.component(.day, from: spring) == 8)
        #expect(calendar.component(.hour, from: spring) == 3)
        let next = TriggerRules.nextTrigger(now: date("2026-10-26T10:00:00Z"), after: "09:00", calendar: utc)
        #expect(next == date("2026-10-27T09:00:00Z"))
    }
    @Test func lastShownUsesLocalDateAcrossTimezones() {
        let now = date("2026-10-26T04:00:00Z")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        #expect(!TriggerRules.shouldRun(now: now, after: "09:00", latest: "16:00", skip: [], requireUnlocked: true,
            lastShown: "2026-10-26", displayAwake: true, sessionUnlocked: true, calendar: calendar))
        #expect(TriggerRules.shouldRun(now: now, after: "09:00", latest: "16:00", skip: [], requireUnlocked: true,
            lastShown: "2026-10-25", displayAwake: true, sessionUnlocked: true, calendar: calendar))
    }
}
