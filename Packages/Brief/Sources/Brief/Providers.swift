import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct AppleProvider: ModelProvider {
    public init() {}
    public func respond(instructions: String, input: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            guard SystemLanguageModel.default.isAvailable else { throw ModelError.unavailable }
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: input).content
        }
        #endif
        throw ModelError.unavailable
    }
}

public struct AnthropicProvider: ModelProvider {
    private let key: String
    private let model: String
    public init(key: String, model: String) { self.key = key; self.model = model }
    public func respond(instructions: String, input: String) async throws -> String {
        guard !key.isEmpty, !model.isEmpty else { throw ModelError.configuration }
        struct Request: Encodable {
            struct Message: Encodable { let role, content: String }
            let model: String; let max_tokens: Int; let system: String; let messages: [Message]
        }
        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(model: model, max_tokens: 4096, system: instructions, messages: [.init(role: "user", content: input)]))
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { throw ModelError.invalidResponse }
        return try JSONDecoder().decode(Response.self, from: data).content.filter { $0.type == "text" }.compactMap(\.text).joined()
    }
}

public struct UnavailableProvider: ModelProvider {
    public init() {}
    public func respond(instructions: String, input: String) async throws -> String { throw ModelError.unavailable }
}
