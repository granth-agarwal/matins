import AppKit
import CoreGraphics
import Config
import Models
import Store

@MainActor
public final class TriggerService: NSObject {
    private let store: BriefStore
    private let configuration: () -> AppConfig?
    private let run: () async -> Bool
    private let failure: () -> Void
    private var timer: Timer?
    private var evaluating = false
    private var sleeping = false
    public private(set) var sessionUnlocked = false

    public init(store: BriefStore, configuration: @escaping () -> AppConfig?,
                run: @escaping () async -> Bool, failure: @escaping () -> Void) {
        self.store = store; self.configuration = configuration; self.run = run; self.failure = failure
        super.init()
    }
    public func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.addObserver(self, selector: #selector(woke), name: event, object: nil)
        }
        for event in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspace.addObserver(self, selector: #selector(slept), name: event, object: nil)
        }
        workspace.addObserver(self, selector: #selector(locked), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(changed), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(locked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(unlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        for event in [NSNotification.Name.NSSystemTimeZoneDidChange, NSNotification.Name.NSSystemClockDidChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: event, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        evaluate()
    }
    public func stop() {
        timer?.invalidate(); timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
    public func userInteracted() { sessionUnlocked = true }
    public var displayAwake: Bool {
        !sleeping && CGDisplayIsActive(CGMainDisplayID()) != 0 && CGDisplayIsAsleep(CGMainDisplayID()) == 0
    }
    public func eligible(now: Date = Date()) -> Bool {
        guard let config = configuration() else { return false }
        do {
            return TriggerRules.shouldRun(now: now, after: config.triggerAfter, latest: config.latestShowTime,
                skip: config.skipDays, requireUnlocked: config.requireUnlocked, lastShown: try store.meta("lastShown"),
                displayAwake: displayAwake, sessionUnlocked: sessionUnlocked)
        } catch { failure(); return false }
    }
    public func evaluate() {
        schedule()
        guard !evaluating, eligible() else { return }
        evaluating = true
        Task {
            defer { evaluating = false; schedule() }
            let date = Dates.day(Date())
            if await run() {
                do { try store.setMeta("lastShown", date) } catch { failure() }
            }
        }
    }
    private func schedule() {
        timer?.invalidate(); timer = nil
        guard displayAwake, let config = configuration(), let date = TriggerRules.nextTrigger(now: Date(), after: config.triggerAfter) else { return }
        let timer = Timer(fireAt: date, interval: 0, target: self, selector: #selector(changed), userInfo: nil, repeats: false)
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    @objc private func woke() { sleeping = false; evaluate() }
    @objc private func slept() { sleeping = true; timer?.invalidate(); timer = nil }
    @objc private func locked() { sessionUnlocked = false }
    @objc private func unlocked() { sessionUnlocked = true; evaluate() }
    @objc private func changed() { evaluate() }
}
