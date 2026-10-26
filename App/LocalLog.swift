import Foundation
import OSLog

@MainActor
final class LocalLog {
    enum Event: String {
        case launched = "App launched"
        case configLoaded = "Config loaded"
        case configFailed = "Config could not load"
        case storeReady = "Database ready"
        case storeFailed = "Database could not open"
        case stopped = "App stopped"
    }

    private let url: URL
    private let system = Logger(subsystem: "com.granth.morningbrief", category: "lifecycle")

    init(url: URL) { self.url = url }

    func record(_ event: Event) {
        system.info("\(event.rawValue, privacy: .public)")
        do {
            let manager = FileManager.default
            if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
               size.intValue > 262_144 {
                let previous = url.appendingPathExtension("previous")
                if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
                try manager.moveItem(at: url, to: previous)
            }
            if !manager.fileExists(atPath: url.path) {
                guard manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
                else { throw CocoaError(.fileWriteUnknown) }
            }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            let line = "\(Date().ISO8601Format()) \(event.rawValue)\n"
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            system.error("Local log could not be written")
        }
    }
}
