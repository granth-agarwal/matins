import Foundation
import Models

public struct MeetingFire: Equatable, Sendable {
    public enum Kind: String, Sendable { case recheck, popup }
    public let kind: Kind
    public let date: Date
    public let minutes: Int
}

public enum MeetingPolicy {
    public static func quiet(now: Date, enabled: Bool, quietMode: Bool, hours: [String], calendar: Calendar = .current) -> Bool {
        if !enabled || quietMode { return true }
        let current = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return hours.contains { interval in
            let parts = interval.split(separator: "-")
            guard parts.count == 2, let start = minutes(String(parts[0])), let end = minutes(String(parts[1])) else { return true }
            if start == end { return true }
            return start < end ? current >= start && current < end : current >= start || current < end
        }
    }
    public static func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
    public static func plan(_ record: SourceRecord, now: Date, minutesBefore: [Int], rechecked: Bool) -> [MeetingFire] {
        guard record.source == .calendar, !record.allDay, let start = record.start,
              start.addingTimeInterval(300) > now else { return [] }
        var result: [MeetingFire] = []
        if !rechecked, start > now {
            result.append(MeetingFire(kind: .recheck, date: max(now.addingTimeInterval(0.1), start.addingTimeInterval(-900)), minutes: 15))
        }
        for minute in Set(minutesBefore).sorted(by: >) where minute > 0 {
            let date = start.addingTimeInterval(-Double(minute * 60))
            if date > now { result.append(MeetingFire(kind: .popup, date: date, minutes: minute)) }
        }
        return result.sorted { $0.date < $1.date }
    }
}
