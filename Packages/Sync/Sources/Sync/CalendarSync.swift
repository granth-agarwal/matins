import Foundation
import Models
import Store

public struct CalendarEvent: Decodable, Sendable {
    public let id: String
    public let status, summary, description, htmlLink, updated, hangoutLink: String?
    public let start, end: EventTime?
    public let attendees: [Attendee]?
    public let attachments: [Attachment]?
    public struct Attendee: Decodable, Sendable {
        public let responseStatus: String?
        public let isSelf: Bool?
        enum CodingKeys: String, CodingKey { case responseStatus; case isSelf = "self" }
    }
    public struct Attachment: Decodable, Sendable { public let fileId: String? }
    public struct EventTime: Decodable, Sendable {
        public let dateTime, date, timeZone: String?
        public func value(fallbackZone: String?) -> Date? {
            if let dateTime { return Dates.parse(dateTime) }
            guard let date else { return nil }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(identifier: timeZone ?? fallbackZone ?? "") ?? .current
            return formatter.date(from: date)
        }
    }
    public var removed: Bool { status == "cancelled" || attendees?.contains { $0.isSelf == true && $0.responseStatus == "declined" } == true }
    public func record(account: String, calendar: String, zone: String?) -> SourceRecord? {
        guard !removed, let start = start?.value(fallbackZone: zone), let end = end?.value(fallbackZone: zone) else { return nil }
        return SourceRecord(id: id, accountID: account, source: .calendar, scope: calendar,
            title: summary ?? "Untitled meeting", body: TextNormalizer.clean(description ?? ""), url: htmlLink ?? "",
            updated: Dates.parse(updated) ?? start, start: start, end: end, allDay: self.start?.date != nil,
            joinURL: hangoutLink, attendeeCount: attendees?.count ?? 0, attachmentIDs: attachments?.compactMap(\.fileId) ?? [])
    }
}

public struct CalendarSync: Sendable {
    public let api: API
    public let store: BriefStore
    public init(api: API, store: BriefStore) { self.api = api; self.store = store }
    public func sync(account: String = "google", calendar: String = "primary", now: Date = Date()) async throws {
        let checkpoint = try store.checkpoint(account: account, source: .calendar, scope: calendar)
        do { try await fetch(account: account, calendar: calendar, token: checkpoint, now: now) }
        catch SyncError.status(410) { try await fetch(account: account, calendar: calendar, token: nil, now: now) }
    }
    private func fetch(account: String, calendar: String, token: String?, now: Date) async throws {
        struct Page: Decodable, Sendable { let items: [CalendarEvent]?; let nextPageToken, nextSyncToken, timeZone: String? }
        var query = ["singleEvents": "true", "showDeleted": "true", "maxResults": "2500"]
        if let token { query["syncToken"] = token }
        else {
            query["timeMin"] = Calendar.current.date(byAdding: .day, value: -1, to: now)!.ISO8601Format()
            query["timeMax"] = Calendar.current.date(byAdding: .day, value: 7, to: now)!.ISO8601Format()
        }
        var records: [SourceRecord] = [], deleted: [String] = [], seen: Set<String> = []
        while true {
            let page: Page = try await api.get("https://www.googleapis.com/calendar/v3/calendars/\(API.component(calendar))/events", query: query)
            for event in page.items ?? [] {
                if event.removed { deleted.append(event.id) }
                else if let record = event.record(account: account, calendar: calendar, zone: page.timeZone) { records.append(record) }
            }
            if let next = page.nextPageToken {
                guard seen.insert(next).inserted, seen.count < 1000 else { throw SyncError.pagination }
                query["pageToken"] = next
            } else {
                guard let next = page.nextSyncToken else { throw SyncError.invalidResponse }
                try store.commit(account: account, source: .calendar, scope: calendar, records: records, deleted: deleted, checkpoint: next, replace: token == nil)
                return
            }
        }
    }
    public func recheck(_ record: SourceRecord) async throws -> SourceRecord? {
        do {
            let event: CalendarEvent = try await api.get("https://www.googleapis.com/calendar/v3/calendars/\(API.component(record.scope))/events/\(API.component(record.id))")
            let value = event.record(account: record.accountID, calendar: record.scope, zone: nil)
            try store.commit(account: record.accountID, source: .calendar, scope: record.scope,
                records: value.map { [$0] } ?? [], deleted: value == nil ? [record.id] : [], checkpoint: nil)
            return value
        } catch SyncError.status(let status) where status == 404 || status == 410 {
            try store.commit(account: record.accountID, source: .calendar, scope: record.scope, records: [], deleted: [record.id], checkpoint: nil)
            return nil
        }
    }
}
