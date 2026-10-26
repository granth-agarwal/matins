import Foundation
import Models
import Store

public struct DriveSync: Sendable {
    public let api: API
    public let store: BriefStore
    public init(api: API, store: BriefStore) { self.api = api; self.store = store }
    private let base = "https://www.googleapis.com/drive/v3"
    struct File: Decodable, Sendable {
        let id: String; let name, mimeType, modifiedTime, webViewLink, description: String?; let trashed: Bool?
    }
    public func sync(account: String = "google", attachments: Set<String> = [], freshAttachments: (@Sendable () async -> Set<String>)? = nil) async throws {
        let checkpoint = try store.checkpoint(account: account, source: .drive)
        do { try await fetch(account: account, checkpoint: checkpoint, attachments: attachments, freshAttachments: freshAttachments) }
        catch SyncError.status(410) { try await fetch(account: account, checkpoint: nil, attachments: attachments, freshAttachments: freshAttachments) }
    }
    private func fetch(account: String, checkpoint: String?, attachments: Set<String>, freshAttachments: (@Sendable () async -> Set<String>)?) async throws {
        struct Token: Decodable, Sendable { let startPageToken: String }
        struct Files: Decodable, Sendable { let files: [File]?; let nextPageToken: String? }
        struct Changes: Decodable, Sendable {
            struct Change: Decodable, Sendable { let fileId: String; let removed: Bool?; let file: File? }
            let changes: [Change]?; let nextPageToken, newStartPageToken: String?
        }
        let fields = "id,name,mimeType,modifiedTime,webViewLink,description,trashed"
        var files: [String: File] = [:], removed: Set<String> = [], next: String?, seen: Set<String> = []
        var final: String
        if let checkpoint {
            next = checkpoint; final = checkpoint
            repeat {
                let page: Changes = try await api.get(base + "/changes", query: ["pageToken": next!, "pageSize": "1000", "fields": "nextPageToken,newStartPageToken,changes(fileId,removed,file(\(fields)))"])
                for change in page.changes ?? [] {
                    if change.removed == true || change.file?.trashed == true { removed.insert(change.fileId) }
                    else if let file = change.file { files[file.id] = file }
                }
                if let token = page.newStartPageToken { final = token }
                next = page.nextPageToken
                if let next, !seen.insert(next).inserted { throw SyncError.pagination }
            } while next != nil
        } else {
            let token: Token = try await api.get(base + "/changes/startPageToken")
            final = token.startPageToken
            repeat {
                var query = ["q": "trashed = false and (name contains 'Meet' or name contains 'notes' or name contains 'transcript')", "pageSize": "1000", "fields": "nextPageToken,files(\(fields))"]
                query["pageToken"] = next
                let page: Files = try await api.get(base + "/files", query: query)
                for file in page.files ?? [] { files[file.id] = file }
                next = page.nextPageToken
                if let next, !seen.insert(next).inserted { throw SyncError.pagination }
            } while next != nil
        }
        let attachments = attachments.union(await freshAttachments?() ?? [])
        let cached = try store.records(source: .drive)
        for id in attachments where files[id] == nil && !removed.contains(id) && !cached.contains(where: { $0.accountID == account && $0.id == id }) {
            do { files[id] = try await api.get(base + "/files/" + API.component(id), query: ["fields": fields]) }
            catch SyncError.status(404) { removed.insert(id) }
        }
        var records: [SourceRecord] = []
        for file in files.values {
            let name = file.name ?? "Untitled document"
            let relevant = attachments.contains(file.id) || name.localizedCaseInsensitiveContains("meet") || name.localizedCaseInsensitiveContains("transcript") || name.localizedCaseInsensitiveContains("notes")
            guard relevant, file.trashed != true else { removed.insert(file.id); continue }
            var body = file.description ?? ""
            if file.mimeType == "application/vnd.google-apps.document" {
                let result = try await api.raw(base + "/files/" + API.component(file.id) + "/export", query: ["mimeType": "text/plain"])
                guard result.status == 200 else { throw SyncError.status(result.status) }
                body = String(decoding: result.data, as: UTF8.self)
            }
            records.append(SourceRecord(id: file.id, accountID: account, source: .drive, title: name,
                body: TextNormalizer.clean(body), url: file.webViewLink ?? "", updated: Dates.parse(file.modifiedTime) ?? .distantPast))
        }
        try store.commit(account: account, source: .drive, records: records, deleted: Array(removed), checkpoint: final, replace: checkpoint == nil)
    }
}
