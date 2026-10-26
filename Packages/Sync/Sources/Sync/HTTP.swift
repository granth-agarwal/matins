import Foundation

public struct HTTPResult: Sendable {
    public let data: Data
    public let status: Int
    public let etag: String?
    public init(data: Data, status: Int = 200, etag: String? = nil) { self.data = data; self.status = status; self.etag = etag }
}
public protocol HTTPTransport: Sendable { func get(_ url: URL, token: String, etag: String?) async throws -> HTTPResult }
public struct LiveHTTP: HTTPTransport {
    public init() {}
    public func get(_ url: URL, token: String, etag: String?) async throws -> HTTPResult {
        guard url.scheme == "https", ["www.googleapis.com", "gmail.googleapis.com", "api.github.com"].contains(url.host) else { throw SyncError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 40
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        request.setValue("MorningBrief", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        guard data.count <= 20_000_000 else { throw SyncError.tooLarge }
        return HTTPResult(data: data, status: response.statusCode, etag: response.value(forHTTPHeaderField: "ETag"))
    }
}
public enum SyncError: Error { case status(Int), invalidResponse, invalidURL, tooLarge, pagination }
public struct API: Sendable {
    public let transport: any HTTPTransport
    public let token: String
    public init(token: String, transport: any HTTPTransport = LiveHTTP()) { self.token = token; self.transport = transport }
    public static func component(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
    public func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let result = try await raw(path, query: query)
        guard (200...299).contains(result.status) else { throw SyncError.status(result.status) }
        return try JSONDecoder().decode(T.self, from: result.data)
    }
    public func raw(_ path: String, query: [String: String] = [:], etag: String? = nil) async throws -> HTTPResult {
        guard var url = URLComponents(string: path) else { throw SyncError.invalidURL }
        url.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = url.url else { throw SyncError.invalidURL }
        return try await transport.get(url, token: token, etag: etag)
    }
}
