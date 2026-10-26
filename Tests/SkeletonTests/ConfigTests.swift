import Config
import Foundation
import Testing

struct ConfigTests {
    @Test func createsPrivateDefaultsAndReloadsPartialEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try ApplicationPaths(directory: root)
        let loader = ConfigLoader(url: paths.config)
        let defaults = try loader.load()
        #expect(defaults.triggerAfter == "09:00")
        #expect(defaults.model.provider == "apple_on_device")
        #expect(defaults.sources.chat == false)
        try "name: Ada\nsources: { gmail: false }\n".write(to: paths.config, atomically: true, encoding: .utf8)
        let edited = try loader.load()
        #expect(edited.name == "Ada")
        #expect(edited.sources.gmail == false)
        #expect(edited.sources.calendar == true)
        #expect(edited.caps.todos == 5)
        let attributes = try FileManager.default.attributesOfItem(atPath: paths.config.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test(arguments: [
        "name: [broken", "retention_days: 0", "trigger_after: '25:00'",
        "trigger_after: '17:00'", "model: { provider: unknown }", "caps: { todos: 6 }"
    ])
    func rejectsInvalidConfigWithoutOverwritingIt(_ yaml: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try ApplicationPaths(directory: root)
        try yaml.write(to: paths.config, atomically: true, encoding: .utf8)
        #expect(throws: ConfigurationError.self) { try ConfigLoader(url: paths.config).load() }
        #expect(try String(contentsOf: paths.config, encoding: .utf8) == yaml)
    }
}
