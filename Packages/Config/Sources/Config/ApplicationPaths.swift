import Foundation

public struct ApplicationPaths: Sendable {
    public let directory: URL
    public var config: URL { directory.appendingPathComponent("config.yaml") }
    public var database: URL { directory.appendingPathComponent("morning-brief.sqlite") }
    public var log: URL { directory.appendingPathComponent("morning-brief.log") }

    public init(directory: URL? = nil) throws {
        self.directory = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("MorningBrief", isDirectory: true)
        try FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
    }
}
