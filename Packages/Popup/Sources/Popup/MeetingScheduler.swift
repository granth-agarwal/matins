import AppKit
import UserNotifications
import Models
import Config
import Store

@MainActor
public final class MeetingScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let store: BriefStore
    private let configuration: () -> AppConfig?
    private let canPresent: () -> Bool
    private let recheck: (SourceRecord) async throws -> SourceRecord?
    private let failure: () -> Void
    private let center = UNUserNotificationCenter.current()
    private let popup = PopupWindow()
    private var records: [String: SourceRecord] = [:]
    private var timers: [String: Timer] = [:]
    private var queue: [String] = []
    private var visible: String?
    private var ignored: Set<String> = []
    private var rechecked: Set<String> = []
    private var delivered: Set<String> = []
    private var generation = 0
    private var notificationIDs: [String: Set<String>] = [:]
    private var stateDate = ""
    public init(store: BriefStore, configuration: @escaping () -> AppConfig?, canPresent: @escaping () -> Bool,
                recheck: @escaping (SourceRecord) async throws -> SourceRecord?, failure: @escaping () -> Void) {
        self.store = store; self.configuration = configuration; self.canPresent = canPresent
        self.recheck = recheck; self.failure = failure
        super.init()
        center.delegate = self
        let actions = [UNNotificationAction(identifier: "join", title: "Join", options: [.foreground]),
                       UNNotificationAction(identifier: "snooze", title: "Snooze 2 min", options: []),
                       UNNotificationAction(identifier: "ignore", title: "Ignore", options: [])]
        center.setNotificationCategories([UNNotificationCategory(identifier: "meeting", actions: actions, intentIdentifiers: [], options: [])])
        restoreState()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(woke), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(hide), name: NSWorkspace.screensDidSleepNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(hide), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: NSNotification.Name.NSSystemClockDidChange, object: nil)
    }
    public func requestNotificationPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert])) ?? false
    }
    private var stateKey: String { "meetingState:" + Dates.day(Date()) }
    private struct State: Codable { let ignored, rechecked, delivered: Set<String> }
    private func restoreState() {
        stateDate = Dates.day(Date())
        ignored.removeAll(); rechecked.removeAll(); delivered.removeAll()
        if let string = try? store.meta(stateKey), let data = string.data(using: .utf8), let state = try? JSONDecoder().decode(State.self, from: data) {
            ignored = state.ignored; rechecked = state.rechecked; delivered = state.delivered
        }
    }
    private func saveState() {
        do { try store.setMeta(stateKey, String(decoding: JSONEncoder().encode(State(ignored: ignored, rechecked: rechecked, delivered: delivered)), as: UTF8.self)) }
        catch { failure() }
    }
    public func register(_ events: [SourceRecord]) async {
        if stateDate != Dates.day(Date()) { restoreState() }
        generation += 1
        let revision = generation
        for timer in timers.values { timer.invalidate() }; timers.removeAll()
        queue.removeAll(); visible = nil; popup.dismiss()
        center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications()
        notificationIDs.removeAll()
        records = Dictionary(events.filter { $0.source == .calendar && !$0.allDay && ($0.start ?? .distantPast).addingTimeInterval(300) > Date() }.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        for record in records.values.sorted(by: { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }) {
            guard generation == revision else { return }
            await schedule(record, revision: revision)
        }
    }
    private func schedule(_ record: SourceRecord, revision: Int) async {
        guard let config = configuration(), config.sources.calendar, config.popups.enabled, !ignored.contains(record.key) else { return }
        let plan = MeetingPolicy.plan(record, now: Date(), minutesBefore: config.popups.minutesBefore, rechecked: rechecked.contains(record.key))
        for fire in plan {
            guard generation == revision else { return }
            let id = identifier(record.key, kind: fire.kind.rawValue, minutes: fire.minutes)
            if fire.kind == .popup {
                guard !delivered.contains(id), !MeetingPolicy.quiet(now: fire.date, enabled: config.popups.enabled,
                    quietMode: config.popups.quietMode == true, hours: config.popups.quietHours) else { continue }
            }
            addTimer(id, at: fire.date, key: record.key, kind: fire.kind.rawValue)
            if fire.kind == .popup { await notification(record, at: fire.date, id: id, revision: revision) }
        }
    }
    private func identifier(_ key: String, kind: String, minutes: Int) -> String { "mb:\(key):\(kind):\(minutes)" }
    private func addTimer(_ id: String, at date: Date, key: String, kind: String) {
        timers[id]?.invalidate()
        let timer = Timer(fireAt: max(date, Date().addingTimeInterval(0.1)), interval: 0, target: self,
            selector: #selector(fired(_:)), userInfo: ["id": id, "key": key, "kind": kind], repeats: false)
        timer.tolerance = 0.5; RunLoop.main.add(timer, forMode: .common); timers[id] = timer
    }
    private func notification(_ record: SourceRecord, at date: Date, id: String, revision: Int) async {
        guard date > Date(), revision == generation, !ignored.contains(record.key) else { return }
        let notificationID = id + "#" + String(revision)
        notificationIDs[record.key, default: []].insert(notificationID)
        let content = UNMutableNotificationContent()
        content.title = record.title; content.body = "Starts at \(record.start?.formatted(date: .omitted, time: .shortened) ?? "")"
        content.categoryIdentifier = "meeting"; content.userInfo = ["key": record.key]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        do {
            try await center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            if revision != generation || ignored.contains(record.key) { center.removePendingNotificationRequests(withIdentifiers: [notificationID]) }
        }
        catch { failure() }
    }
    @objc private func fired(_ timer: Timer) {
        guard let info = timer.userInfo as? [String: String], let id = info["id"], let key = info["key"],
              let record = records[key] else { return }
        timers.removeValue(forKey: id)
        if info["kind"] == "recheck" {
            guard !rechecked.contains(key) else { return }
            rechecked.insert(key); saveState()
            let revision = generation
            Task {
                do {
                    let updated = try await recheck(record)
                    guard revision == generation else { return }
                    cancelMeeting(key)
                    if let updated {
                        records[key] = updated
                        await schedule(updated, revision: revision)
                    } else { records.removeValue(forKey: key) }
                } catch { failure() }
            }
        } else if info["kind"] == "dismiss" {
            if visible == key { dismissVisible() }
        } else {
            delivered.insert(id); saveState()
            let ids = Array((notificationIDs[key] ?? []).filter { $0.hasPrefix(id + "#") })
            center.removePendingNotificationRequests(withIdentifiers: ids); center.removeDeliveredNotifications(withIdentifiers: ids)
            enqueue(key)
        }
    }
    private func enqueue(_ key: String) {
        guard !ignored.contains(key), (records[key]?.start?.addingTimeInterval(300) ?? .distantPast) > Date(),
              !queue.contains(key), visible != key else { return }
        queue.append(key); showNext()
    }
    private func showNext() {
        guard visible == nil, canPresent(), let config = configuration(),
              !MeetingPolicy.quiet(now: Date(), enabled: config.popups.enabled, quietMode: config.popups.quietMode == true, hours: config.popups.quietHours) else { return }
        while !queue.isEmpty {
            let key = queue.removeFirst()
            guard let record = records[key], let start = record.start, start.addingTimeInterval(300) > Date(), !ignored.contains(key) else { continue }
            visible = key
            popup.show(record) { [weak self] action in self?.handle(action, key: key) }
            addTimer("dismiss:" + key, at: start.addingTimeInterval(300), key: key, kind: "dismiss")
            break
        }
    }
    private func dismissVisible() { popup.dismiss(); visible = nil; showNext() }
    private func cancelMeeting(_ key: String) {
        let ids = timers.filter { ($0.value.userInfo as? [String: String])?["key"] == key }.map(\.key)
        for id in ids { timers.removeValue(forKey: id)?.invalidate() }
        let notifications = Array(notificationIDs.removeValue(forKey: key) ?? [])
        center.removePendingNotificationRequests(withIdentifiers: notifications)
        center.removeDeliveredNotifications(withIdentifiers: notifications)
        queue.removeAll { $0 == key }
        if visible == key { dismissVisible() }
    }
    private func handle(_ action: String, key: String) {
        if records[key] == nil { records[key] = (try? store.records(source: .calendar))?.first { $0.key == key } }
        guard let record = records[key], let start = record.start, start.addingTimeInterval(300) > Date() else { return }
        switch action {
        case "join":
            if let text = record.joinURL, let url = URL(string: text), url.scheme == "https" { NSWorkspace.shared.open(url) }
            ignored.insert(key); cancelMeeting(key)
        case "ignore": ignored.insert(key); cancelMeeting(key)
        case "snooze":
            cancelMeeting(key)
            let date = Date().addingTimeInterval(120)
            if date < start.addingTimeInterval(300) {
                let id = identifier(key, kind: "snooze", minutes: 2)
                addTimer(id, at: date, key: key, kind: "popup")
                let revision = generation
                Task { await notification(record, at: date, id: id, revision: revision) }
            }
        default: break
        }
        saveState()
    }
    public func clear() {
        generation += 1
        for timer in timers.values { timer.invalidate() }; timers.removeAll()
        records.removeAll(); queue.removeAll(); visible = nil; popup.dismiss()
        notificationIDs.removeAll()
        center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications()
    }
    public func stop() {
        for timer in timers.values { timer.invalidate() }; timers.removeAll()
        popup.dismiss()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self); NotificationCenter.default.removeObserver(self)
    }
    @objc private func woke() { Task { await Task.yield(); showNext() } }
    @objc private func hide() { popup.dismiss(); visible = nil; queue.removeAll() }
    @objc private func displayChanged() { popup.position() }
    @objc private func clockChanged() { let events = Array(records.values); Task { await register(events) } }
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [] }
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let key = response.notification.request.content.userInfo["key"] as? String
        let action = response.actionIdentifier
        await MainActor.run { if let key { self.handle(action, key: key) } }
    }
}
