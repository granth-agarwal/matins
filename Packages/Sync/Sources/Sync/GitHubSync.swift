import Foundation
import Models
import Store

public struct GitHubSync: Sendable {
    public let api: API
    public let store: BriefStore
    public init(api: API, store: BriefStore) { self.api = api; self.store = store }
    struct Checkpoint: Codable { var since: String; var etag: String? }
    struct Notice: Decodable, Sendable {
        struct Subject: Decodable, Sendable { let title: String; let url, type: String? }
        struct Repo: Decodable, Sendable { let html_url: String }
        let id, updated_at: String; let subject: Subject; let repository: Repo
    }
    struct Search: Decodable, Sendable {
        struct Item: Decodable, Sendable { let id: Int; let title, html_url, updated_at, state: String; let body: String? }
        let items: [Item]; let total_count: Int; let incomplete_results: Bool
    }
    public func sync(account: String = "github", now: Date = Date()) async throws {
        let previous = try store.checkpoint(account: account, source: .github)
            .flatMap { try JSONDecoder().decode(Checkpoint.self, from: Data($0.utf8)) }
        let since = previous?.since ?? now.addingTimeInterval(-3 * 86400).ISO8601Format()
        var records: [SourceRecord] = [], page = 1, etag: String?
        while true {
            let response = try await api.raw("https://api.github.com/notifications", query: ["since": since, "all": "true", "per_page": "100", "page": String(page)], etag: page == 1 ? previous?.etag : nil)
            if response.status == 304 { etag = previous?.etag; break }
            guard response.status == 200 else { throw SyncError.status(response.status) }
            if page == 1 { etag = response.etag }
            let notices = try JSONDecoder().decode([Notice].self, from: response.data)
            for item in notices {
                let url = item.subject.url?.replacingOccurrences(of: "https://api.github.com/repos/", with: "https://github.com/").replacingOccurrences(of: "/pulls/", with: "/pull/") ?? item.repository.html_url
                records.append(SourceRecord(id: "notice:" + item.id, accountID: account, source: .github,
                    title: item.subject.title, url: url, updated: Dates.parse(item.updated_at) ?? now, kind: item.subject.type))
            }
            if notices.count < 100 { break }
            page += 1; guard page <= 100 else { throw SyncError.pagination }
        }
        for query in ["is:open is:pr review-requested:@me", "is:open is:issue assignee:@me"] {
            page = 1
            repeat {
                let result: Search = try await api.get("https://api.github.com/search/issues", query: ["q": query, "per_page": "100", "page": String(page)])
                guard !result.incomplete_results, result.total_count <= 1000 else { throw SyncError.tooLarge }
                records += result.items.map { SourceRecord(id: "issue:\($0.id)", accountID: account, source: .github,
                    title: $0.title, body: TextNormalizer.clean($0.body ?? ""), url: $0.html_url,
                    updated: Dates.parse($0.updated_at) ?? now, isOpen: $0.state == "open", kind: query.contains("is:pr") ? "PullRequest" : "Issue") }
                if page * 100 >= result.total_count { break }
                page += 1
            } while page <= 10
        }
        let old = try store.records(source: .github).filter { $0.accountID == account && $0.id.hasPrefix("issue:") }
        let ids = Set(records.map(\.id))
        let deleted = old.filter { !ids.contains($0.id) }.map(\.id)
        let checkpoint = String(decoding: try JSONEncoder().encode(Checkpoint(since: now.ISO8601Format(), etag: etag)), as: UTF8.self)
        try store.commit(account: account, source: .github, records: records, deleted: deleted, checkpoint: checkpoint)
    }
}
