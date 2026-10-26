import Foundation
import Models

public enum TriggerRules {
    public static func shouldRun(now: Date, after: String, latest: String, skip: [String],
                                 requireUnlocked: Bool, lastShown: String?, displayAwake: Bool,
                                 sessionUnlocked: Bool, calendar: Calendar = .current) -> Bool {
        guard displayAwake, !requireUnlocked || sessionUnlocked,
              lastShown != Dates.day(now, calendar: calendar) else { return false }
        let components = calendar.dateComponents([.hour, .minute, .weekday], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        guard let lower = minutes(after), let upper = minutes(latest), minute >= lower, minute < upper else { return false }
        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        return !skip.contains(names[(components.weekday ?? 1) - 1])
    }
    public static func minutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
    public static func nextTrigger(now: Date, after: String, calendar: Calendar = .current) -> Date? {
        guard let value = minutes(after) else { return nil }
        return calendar.nextDate(after: now, matching: DateComponents(hour: value / 60, minute: value % 60),
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
}
