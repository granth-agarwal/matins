import Foundation

public struct DeviceCode: Decodable, Sendable {
    public let device_code, user_code, verification_uri: String
    public let expires_in, interval: Int
}

public enum DevicePoll: Equatable, Sendable {
    case wait(Int), authorized(String), denied
    public static func result(error: String?, token: String?, interval: Int) -> DevicePoll {
        if let token { return .authorized(token) }
        switch error {
        case "authorization_pending": return .wait(interval)
        case "slow_down": return .wait(interval + 5)
        default: return .denied
        }
    }
}

public actor GitHubAuth {
    private let keychain: Keychain
    private let session: URLSession
    public init(keychain: Keychain = Keychain(), session: URLSession = URLSession(configuration: .ephemeral)) {
        self.keychain = keychain; self.session = session
    }
    private func post<T: Decodable>(_ path: String, fields: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: "https://github.com/login/" + path)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw AuthError.network }
        return try JSONDecoder().decode(T.self, from: data)
    }
    public func start(clientID: String?) async throws -> DeviceCode {
        guard let clientID, !clientID.isEmpty else { throw AuthError.missingClient }
        return try await post("device/code", fields: ["client_id": clientID, "scope": "notifications"])
    }
    public func finish(_ code: DeviceCode, clientID: String) async throws {
        struct Response: Decodable { let access_token: String?; let error: String? }
        let end = Date().addingTimeInterval(TimeInterval(code.expires_in))
        var interval = max(5, code.interval)
        while Date() < end {
            try await Task.sleep(for: .seconds(interval))
            let result: Response = try await post("oauth/access_token", fields: ["client_id": clientID,
                "device_code": code.device_code, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            try Task.checkCancellation()
            switch DevicePoll.result(error: result.error, token: result.access_token, interval: interval) {
            case .authorized(let token): try keychain.write(Data(token.utf8), key: "github"); return
            case .wait(let seconds): interval = seconds
            case .denied: throw AuthError.cancelled
            }
        }
        throw AuthError.expired
    }
    public func accessToken() throws -> String {
        guard let data = try keychain.read("github"), let token = String(data: data, encoding: .utf8) else { throw AuthError.signInAgain }
        return token
    }
    public func signOut() throws { try keychain.delete("github") }
}
