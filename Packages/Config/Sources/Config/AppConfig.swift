import Foundation
import Yams

public struct AppConfig: Codable, Sendable {
    public var name: String
    public var signature: String
    public var triggerAfter: String
    public var latestShowTime: String
    public var skipDays: [String]
    public var requireUnlocked: Bool
    public var retentionDays: Int
    public var sources: Sources
    public var gmail: Gmail
    public var sections: [String]
    public var caps: Caps
    public var labels: [String: String]
    public var palette: Palette
    public var model: Model
    public var popups: Popups
    public var oauth: OAuth?
    public var calendars: [String]?

    public struct OAuth: Codable, Sendable {
        public var googleClientID: String?
        public var githubClientID: String?
        public init(googleClientID: String? = nil, githubClientID: String? = nil) {
            self.googleClientID = googleClientID; self.githubClientID = githubClientID
        }
        enum CodingKeys: String, CodingKey {
            case googleClientID = "google_client_id"
            case githubClientID = "github_client_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, signature, sources, gmail, sections, caps, labels, palette, model, popups, oauth, calendars
        case triggerAfter = "trigger_after"
        case latestShowTime = "latest_show_time"
        case skipDays = "skip_days"
        case requireUnlocked = "require_unlocked"
        case retentionDays = "retention_days"
    }

    public struct Sources: Codable, Sendable {
        public var calendar, gmail, drive, github, chat: Bool
    }

    public struct Gmail: Codable, Sendable {
        public var excludeCategories: [String]
        public var vip, ignore: [String]
        enum CodingKeys: String, CodingKey {
            case excludeCategories = "exclude_categories"
            case vip, ignore
        }
    }

    public struct Caps: Codable, Sendable {
        public var todos, updates, replies: Int
    }

    public struct Palette: Codable, Sendable {
        public var mode: String
        public var pinned: Int?
        public var list: PaletteList
    }

    public enum PaletteList: Codable, Sendable {
        case defaults
        case custom([PaletteColors])
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self), value == "default" { self = .defaults }
            else { self = .custom(try container.decode([PaletteColors].self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self { case .defaults: try container.encode("default"); case .custom(let list): try container.encode(list) }
        }
    }
    public struct PaletteColors: Codable, Sendable {
        public var name, ground, glow1, glow2, accent: String
        public init(name: String, ground: String, glow1: String, glow2: String, accent: String) {
            self.name = name; self.ground = ground; self.glow1 = glow1; self.glow2 = glow2; self.accent = accent
        }
        enum CodingKeys: String, CodingKey { case name, ground, accent; case glow1 = "glow_1"; case glow2 = "glow_2" }
    }

    public struct Model: Codable, Sendable {
        public var provider, synthesis: String
        public var modelID: String?
        enum CodingKeys: String, CodingKey { case provider, synthesis; case modelID = "model_id" }
    }

    public struct Popups: Codable, Sendable {
        public var enabled: Bool
        public var quietMode: Bool?
        public var minutesBefore: [Int]
        public var quietHours: [String]
        public var position: String
        enum CodingKeys: String, CodingKey {
            case enabled, position
            case minutesBefore = "minutes_before"
            case quietHours = "quiet_hours"
            case quietMode = "quiet_mode"
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
        if let calendars { guard !calendars.isEmpty, calendars.allSatisfy({ !$0.isEmpty }) else { throw ConfigurationError.invalid } }
        if case .custom(let colors) = palette.list {
            guard (1...32).contains(colors.count), colors.allSatisfy({ color in
                let valid = [color.ground, color.glow1, color.glow2, color.accent].allSatisfy { value in
                    let value = value.hasPrefix("#") ? String(value.dropFirst()) : value
                    return value.count == 6 && Int(value, radix: 16) != nil
                }
                func luminance(_ hex: String) -> Double {
                    let value = Int(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
                    let channels = [16, 8, 0].map { shift -> Double in
                        let c = Double((value >> shift) & 255) / 255
                        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
                    }
                    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
                }
                return valid && (luminance(color.accent) + 0.05) / (luminance("0E0E0E") + 0.05) >= 4.5
            }) else { throw ConfigurationError.invalid }
        }
        for interval in popups.quietHours {
            let parts = interval.split(separator: "-")
            guard parts.count == 2, parts.allSatisfy({ isTime(String($0)) }) else { throw ConfigurationError.invalid }
        }
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
    public var url: URL

    public init(url: URL) { self.url = url }

    public func save(_ config: AppConfig) throws {
        try config.validate()
        let data = Data(try YAMLEncoder().encode(config).utf8)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".config-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw ConfigurationError.invalid }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: url) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

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
