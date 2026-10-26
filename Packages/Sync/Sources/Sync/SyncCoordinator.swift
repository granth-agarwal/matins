import Foundation
import Models

public struct SyncJob: Sendable {
    public let source: Source
    public let run: @Sendable () async throws -> Void
    public init(_ source: Source, run: @escaping @Sendable () async throws -> Void) { self.source = source; self.run = run }
}
public struct SyncOutcome: Sendable {
    public var succeeded: [Source] = []
    public var failed: [Source] = []
}
public enum SyncCoordinator {
    public static func run(_ jobs: [SyncJob]) async -> SyncOutcome {
        await withTaskGroup(of: (Source, Bool).self) { group in
            for job in jobs { group.addTask { do { try await job.run(); return (job.source, true) } catch { return (job.source, false) } } }
            var result = SyncOutcome()
            for await (source, success) in group {
                if success { result.succeeded.append(source) } else { result.failed.append(source) }
            }
            result.succeeded.sort { $0.rawValue < $1.rawValue }; result.failed.sort { $0.rawValue < $1.rawValue }
            return result
        }
    }
}
