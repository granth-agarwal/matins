import Foundation

public enum Source: String, Codable, CaseIterable, Sendable { case calendar, gmail, drive, github }

public struct SourceRecord: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var accountID: String
    public var source: Source
    public var scope: String
    public var title: String
    public var body: String
    public var url: String
    public var updated: Date
    public var start: Date?
    public var end: Date?
    public var allDay: Bool
    public var joinURL: String?
    public var attendeeCount: Int
    public var attachmentIDs: [String]
    public var isOpen: Bool
    public var person: String?
    public var kind: String?
    public var rank: Int?
    public init(id: String, accountID: String, source: Source, scope: String = "", title: String,
                body: String = "", url: String = "", updated: Date = Date(), start: Date? = nil,
                end: Date? = nil, allDay: Bool = false, joinURL: String? = nil, attendeeCount: Int = 0,
                attachmentIDs: [String] = [], isOpen: Bool = true, person: String? = nil, kind: String? = nil, rank: Int? = nil) {
        self.id = id; self.accountID = accountID; self.source = source; self.scope = scope
        self.title = title; self.body = body; self.url = url; self.updated = updated; self.start = start
        self.end = end; self.allDay = allDay; self.joinURL = joinURL; self.attendeeCount = attendeeCount
        self.attachmentIDs = attachmentIDs; self.isOpen = isOpen
        self.person = person; self.kind = kind; self.rank = rank
    }
    public var key: String { "\(accountID)|\(source.rawValue)|\(scope)|\(id)" }
}

public enum TextNormalizer {
    public static func clean(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: "(?is)<blockquote\\b.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<div[^>]*class=[\"'][^\"']*gmail_(quote|signature)[^\"']*[\"'][^>]*>.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
        var lines: [String] = []
        for line in stripped.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix(">") || (value.hasPrefix("On ") && value.hasSuffix("wrote:")) || value == String(repeating: "-", count: 2) || value.hasPrefix("Sent from my ") { break }
            lines.append(value)
        }
        return String(lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).prefix(1200))
    }
    public static func words(_ text: String, limit: Int) -> String {
        text.split(whereSeparator: \.isWhitespace).prefix(limit).joined(separator: " ")
    }
}

public enum Dates {
    public static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
