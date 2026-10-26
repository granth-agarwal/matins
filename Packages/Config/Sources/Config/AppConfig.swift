import Foundation
import Yams

public struct AppConfig: Codable, Sendable {
    public let name: String
    public let signature: String
    public let triggerAfter: String
    public let latestShowTime: String
    public let skipDays: [String]
    public let requireUnlocked: Bool
    public let retentionDays: Int
    public let sources: Sources
    public let gmail: Gmail
    public let sections: [String]
    public let caps: Caps
    public let labels: [String: String]
    public let palette: Palette
    public let model: Model
    public let popups: Popups
    public let oauth: OAuth?

    public struct OAuth: Codable, Sendable {
        public let googleClientID: String?
        public let githubClientID: String?
        enum CodingKeys: String, CodingKey {
            case googleClientID = "google_client_id"
            case githubClientID = "github_client_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, signature, sources, gmail, sections, caps, labels, palette, model, popups, oauth
        case triggerAfter = "trigger_after"
        case latestShowTime = "latest_show_time"
        case skipDays = "skip_days"
        case requireUnlocked = "require_unlocked"
        case retentionDays = "retention_days"
    }

    public struct Sources: Codable, Sendable {
        public let calendar, gmail, drive, github, chat: Bool
    }

    public struct Gmail: Codable, Sendable {
        public let excludeCategories: [String]
        public let vip, ignore: [String]
        enum CodingKeys: String, CodingKey {
            case excludeCategories = "exclude_categories"
            case vip, ignore
        }
    }

    public struct Caps: Codable, Sendable {
        public let todos, updates, replies: Int
    }

    public struct Palette: Codable, Sendable {
        public let mode: String
        public let pinned: Int?
        public let list: String
    }

    public struct Model: Codable, Sendable {
        public let provider, synthesis: String
        public let modelID: String?
        enum CodingKeys: String, CodingKey { case provider, synthesis; case modelID = "model_id" }
    }

    public struct Popups: Codable, Sendable {
        public let enabled: Bool
        public let minutesBefore: [Int]
        public let quietHours: [String]
        public let position: String
        enum CodingKeys: String, CodingKey {
            case enabled, position
            case minutesBefore = "minutes_before"
            case quietHours = "quiet_hours"
        }
    }

    public func validate() throws {
        func isTime(_ value: String) -> Bool {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }),
                  let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
            return (0...23).contains(hour) && (0...59).contains(minute)
        }
        let providers = ["apple_on_device", "anthropic", "openai", "ollama"]
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isTime(triggerAfter), isTime(latestShowTime), triggerAfter < latestShowTime,
              retentionDays > 0,
              Set(skipDays).isSubset(of: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]),
              Set(sections).isSubset(of: ["focus", "todos", "updates", "schedule"]),
              (0...5).contains(caps.todos), (0...4).contains(caps.updates), (0...5).contains(caps.replies),
              ["auto", "pinned"].contains(palette.mode),
              palette.pinned.map({ $0 >= 0 }) ?? (palette.mode == "auto"),
              providers.contains(model.provider), providers.contains(model.synthesis),
              popups.minutesBefore.allSatisfy({ $0 > 0 }), popups.position == "bottom_left"
        else { throw ConfigurationError.invalid }
    }
}

public enum ConfigurationError: Error, LocalizedError {
    case invalid
    public var errorDescription: String? {
        "Config could not load. Check config.yaml and reload."
    }
}

public struct ConfigLoader: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> AppConfig {
        do {
            let bundle = Bundle.main.url(forResource: "Config_Config", withExtension: "bundle")
                .flatMap(Bundle.init(url:)) ?? Bundle.module
            guard let defaultsURL = bundle.url(forResource: "DefaultConfig", withExtension: "yaml") else {
                throw ConfigurationError.invalid
            }
            let defaultsText = try String(contentsOf: defaultsURL, encoding: .utf8)
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try defaultsText.write(to: url, atomically: true, encoding: .utf8)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let text = try String(contentsOf: url, encoding: .utf8)
            guard let defaults = try Yams.load(yaml: defaultsText) as? [String: Any],
                  let overrides = try Yams.load(yaml: text) as? [String: Any] else {
                throw ConfigurationError.invalid
            }
            let merged = Self.merge(defaults, overrides)
            let config = try YAMLDecoder().decode(AppConfig.self, from: Yams.dump(object: merged))
            try config.validate()
            return config
        } catch {
            // Parser errors can contain file contents. Never expose them in diagnostics.
            throw ConfigurationError.invalid
        }
    }

    private static func merge(_ defaults: [String: Any], _ overrides: [String: Any]) -> [String: Any] {
        defaults.merging(overrides) { original, replacement in
            if let original = original as? [String: Any], let replacement = replacement as? [String: Any] {
                return merge(original, replacement)
            }
            return replacement
        }
    }
}
