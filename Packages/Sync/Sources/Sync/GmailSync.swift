import Foundation
import Models
import Store

public struct GmailSync: Sendable {
    public let api: API
    public let store: BriefStore
    public init(api: API, store: BriefStore) { self.api = api; self.store = store }
    private let base = "https://gmail.googleapis.com/gmail/v1/users/me"
    struct ID: Decodable, Sendable { let id: String }
    struct Part: Decodable, Sendable {
        struct Header: Decodable, Sendable { let name, value: String }
        struct Body: Decodable, Sendable { let data: String? }
        let mimeType: String?; let headers: [Header]?; let body: Body?; let parts: [Part]?
        var text: String {
            if let parts {
                let plain = parts.filter { $0.mimeType == "text/plain" }
                return (plain.isEmpty ? parts : plain).map(\.text).joined(separator: "\n")
            }
            guard mimeType == "text/plain" || mimeType == "text/html", var data = body?.data else { return "" }
            data = data.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            data += String(repeating: "=", count: (4 - data.count % 4) % 4)
            return Data(base64Encoded: data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }
    struct Message: Decodable, Sendable {
        let id, threadId: String; let snippet, internalDate: String?; let labelIds: [String]?; let payload: Part?
    }
    public func sync(account: String = "google", excluded: [String] = ["promotions", "social"], ignore: [String] = []) async throws {
        let checkpoint = try store.checkpoint(account: account, source: .gmail)
        do { try await fetch(account: account, checkpoint: checkpoint, excluded: excluded, ignore: ignore) }
        catch SyncError.status(404) { try await fetch(account: account, checkpoint: nil, excluded: excluded, ignore: ignore) }
    }
    private func fetch(account: String, checkpoint: String?, excluded: [String], ignore: [String]) async throws {
        struct Profile: Decodable, Sendable { let historyId: String }
        struct Page: Decodable, Sendable { let messages: [ID]?; let nextPageToken: String? }
        struct HistoryPage: Decodable, Sendable {
            struct Change: Decodable, Sendable {
                struct Entry: Decodable, Sendable { let message: ID }
                let messages: [ID]?; let messagesDeleted: [Entry]?
            }
            let history: [Change]?; let historyId: String; let nextPageToken: String?
        }
        var ids: Set<String> = [], removed: Set<String> = [], next: String?, seen: Set<String> = []
        var final: String
        if let checkpoint {
            final = checkpoint
            repeat {
                var query = ["startHistoryId": checkpoint, "maxResults": "500"]
                query["pageToken"] = next
                let page: HistoryPage = try await api.get(base + "/history", query: query)
                for change in page.history ?? [] {
                    ids.formUnion((change.messages ?? []).map(\.id))
                    removed.formUnion((change.messagesDeleted ?? []).map { $0.message.id })
                }
                final = page.historyId; next = page.nextPageToken
                if let next, !seen.insert(next).inserted { throw SyncError.pagination }
            } while next != nil
        } else {
            let profile: Profile = try await api.get(base + "/profile")
            final = profile.historyId
            repeat {
                var query = ["q": "newer_than:3d " + excluded.map { "-category:\($0)" }.joined(separator: " "), "maxResults": "500"]
                query["pageToken"] = next
                let page: Page = try await api.get(base + "/messages", query: query)
                ids.formUnion((page.messages ?? []).map(\.id)); next = page.nextPageToken
                if let next, !seen.insert(next).inserted { throw SyncError.pagination }
            } while next != nil
        }
        var records: [SourceRecord] = []
        for id in ids.subtracting(removed).sorted() {
            do {
                let message: Message = try await api.get(base + "/messages/" + API.component(id), query: ["format": "full"])
                let labels = Set(message.labelIds ?? [])
                let headers = message.payload?.headers ?? []
                let sender = headers.first { $0.name.lowercased() == "from" }?.value ?? ""
                if labels.contains("TRASH") || labels.contains("SPAM") || excluded.contains(where: { labels.contains("CATEGORY_" + $0.uppercased()) }) || ignore.contains(where: { sender.localizedCaseInsensitiveContains($0) }) {
                    removed.insert(id); continue
                }
                let title = headers.first { $0.name.lowercased() == "subject" }?.value ?? "Untitled message"
                records.append(SourceRecord(id: id, accountID: account, source: .gmail, title: title,
                    body: TextNormalizer.clean(message.payload?.text.isEmpty == false ? message.payload!.text : (message.snippet ?? "")),
                    url: "https://mail.google.com/mail/u/0/#all/" + message.threadId,
                    updated: Date(timeIntervalSince1970: (Double(message.internalDate ?? "") ?? 0) / 1000), isOpen: labels.contains("INBOX")))
            } catch SyncError.status(404) { removed.insert(id) }
        }
        try store.commit(account: account, source: .gmail, records: records, deleted: Array(removed), checkpoint: final, replace: checkpoint == nil)
    }
}
