import AppKit
import Auth
import Config
import OSLog
import Store
import Sync
import Models
import Brief
import UI
import Trigger
import Popup
import SwiftUI
import ServiceManagement

@main
struct MorningBriefApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAgent.self) private var agent

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class MenuBarAgent: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let google = GoogleAuth()
    private let github = GitHubAuth()
    private var authTask: Task<Void, Never>?
    private var authWindow: NSWindow?
    private var running = false
    private var actionRunning = false
    private let briefWindow = BriefWindowController()
    private var trigger: TriggerService?
    private var meetings: MeetingScheduler?
    private let settingsWindow = SettingsWindowController()
    private var item: NSStatusItem?
    private var paths: ApplicationPaths?
    private var log: LocalLog?
    private var store: BriefStore?
    private var config: AppConfig?
    private let status = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sun.horizon", accessibilityDescription: "Morning Brief")
        item.button?.toolTip = "Morning Brief"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Morning Brief", action: nil, keyEquivalent: ""))
        menu.addItem(status)
        menu.addItem(.separator())
        add("Sign in with Google", action: #selector(signInGoogle), to: menu)
        add("Sign in with GitHub", action: #selector(signInGitHub), to: menu)
        add("Cancel sign-in", action: #selector(cancelSignIn), to: menu)
        add("Refresh Calendar", action: #selector(refreshCalendar), to: menu)
        add("Refresh sources", action: #selector(refreshSources), to: menu)
        add("Refresh brief", action: #selector(generateBrief), to: menu)
        add("Show today's brief", action: #selector(showToday), to: menu)
        add("Open config…", action: #selector(openConfig), to: menu)
        add("Reload config", action: #selector(reload), to: menu)
        add("Open data folder", action: #selector(openDataFolder), to: menu)
        add("Settings…", action: #selector(openSettings), to: menu)
        menu.addItem(.separator())
        add("Quit Morning Brief", action: #selector(quit), key: "q", to: menu)
        item.menu = menu
        self.item = item
        start()
    }

    private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
    }

    private func start() {
        do {
            let paths = try ApplicationPaths()
            self.paths = paths
            let log = LocalLog(url: paths.log)
            self.log = log
            log.record(.launched)
            do {
                store = try BriefStore(url: paths.database)
                log.record(.storeReady)
            } catch {
                log.record(.storeFailed)
            }
            loadConfig()
            if let store {
                let meetings = MeetingScheduler(store: store, configuration: { [weak self] in self?.config },
                    canPresent: { [weak self] in
                        guard let self, let trigger = self.trigger else { return false }
                        return (try? store.meta("onboarded")) == "true" && trigger.displayAwake && (self.config?.requireUnlocked == false || trigger.sessionUnlocked)
                    }, recheck: { [weak self] event in
                        guard let self else { return nil }
                        let token = try await self.google.accessToken()
                        return try await CalendarSync(api: API(token: token), store: store).recheck(event)
                    }, failure: { [weak self] in self?.log?.record(.meetingFailed) })
                self.meetings = meetings
                let trigger = TriggerService(store: store, configuration: { [weak self] in self?.config },
                    run: { [weak self] in await self?.runDaily() ?? false },
                    failure: { [weak self] in self?.status.title = "Daily state could not save. Try again." })
                self.trigger = trigger
                trigger.start()
                if (try? store.meta("onboarded")) == "true" {
                    Task { await meetings.register((try? enabledRecords(source: .calendar)) ?? []) }
                } else { openSettings() }
            }
        } catch {
            status.title = "App data folder could not open"
            Logger(subsystem: "com.granth.morningbrief", category: "lifecycle")
                .error("App data folder could not open")
        }
    }

    private func loadConfig() {
        guard let paths else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let previous = config.flatMap { try? encoder.encode($0) }
            config = try ConfigLoader(url: paths.config).load()
            if previous != nil, previous != config.flatMap({ try? encoder.encode($0) }), let meetings {
                Task { await meetings.register((try? enabledRecords(source: .calendar)) ?? []) }
            }
            log?.record(.configLoaded)
            status.title = google.needsSignIn ? "Sign in again" : (store == nil ? "Database could not open. Restart to retry." : "Ready, \(config!.name)")
        } catch {
            log?.record(.configFailed)
            status.title = "Config could not load. Edit and reload."
        }
    }

    func menuWillOpen(_ menu: NSMenu) { trigger?.userInteracted(); loadConfig() }

    @objc private func reload() { loadConfig(); trigger?.evaluate() }

    private func sourceEnabled(_ source: Source) -> Bool {
        guard let config else { return false }
        switch source {
        case .calendar: return config.sources.calendar
        case .gmail: return config.sources.gmail
        case .drive: return config.sources.drive
        case .github: return config.sources.github
        }
    }
    private func enabledRecords(source: Source? = nil) throws -> [SourceRecord] {
        guard let store else { return [] }
        return try store.records(source: source).filter { record in
            guard sourceEnabled(record.source), record.accountID == (record.source == .github ? "github" : google.accountID) else { return false }
            return record.source != .calendar || (config?.calendars ?? ["primary"]).contains(record.scope)
        }
    }
    private func isEnabledTask(_ key: String) -> Bool {
        Source.allCases.contains { source in
            guard sourceEnabled(source), key.hasPrefix((source == .github ? "github" : google.accountID) + "|" + source.rawValue + "|") else { return false }
            return source != .calendar || (config?.calendars ?? ["primary"]).contains { key.hasPrefix(google.accountID + "|calendar|" + $0 + "|") }
        }
    }

    @objc private func openSettings() {
        loadConfig()
        guard let config, let paths, let store else { return }
        settingsWindow.show(config: config, onboarding: (try? store.meta("onboarded")) != "true",
            loginEnabled: SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval,
            save: { [weak self] value in
                try ConfigLoader(url: paths.config).save(value)
                self?.loadConfig()
            }, begin: { [weak self] in
                try store.setMeta("onboarded", "true")
                self?.trigger?.userInteracted(); self?.trigger?.evaluate()
            }, login: { value in
                if value {
                    if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval { try SMAppService.mainApp.register() }
                } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval { try SMAppService.mainApp.unregister() }
            }, google: { [weak self] in self?.signInGoogle() }, github: { [weak self] in self?.signInGitHub() },
            notifications: { [weak self] in
                guard let meetings = self?.meetings else { return false }
                let enabled = await meetings.requestNotificationPermission()
                if let records = try? self?.enabledRecords(source: .calendar) { await meetings.register(records) }
                return enabled
            }, saveSecret: { kind, value in
                guard ["anthropic", "google_client_secret"].contains(kind) else { throw AuthError.keychain }
                try Keychain().write(Data(value.utf8), key: kind)
            }, signOut: { [weak self] in try await self?.signOutGoogle() },
            deleteData: { [weak self] in try await self?.removeLocalData(uninstall: false) },
            uninstall: { [weak self] in try await self?.removeLocalData(uninstall: true) },
            openConfig: { [weak self] in self?.openConfig() })
    }
    private func signOutGoogle() async throws {
        guard !running, !actionRunning, let store else { throw ModelError.configuration }
        authTask?.cancel()
        let account = google.accountID
        try google.signOut()
        meetings?.clear(); briefWindow.close()
        try store.deleteAccount(account)
        status.title = "Google signed out"
    }
    private func removeLocalData(uninstall: Bool) async throws {
        guard !running, !actionRunning, let store, let paths else { throw ModelError.configuration }
        authTask?.cancel(); google.cancel(); meetings?.clear(); briefWindow.close(); authWindow?.close()
        if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            try await SMAppService.mainApp.unregister()
        }
        try google.signOut(); try await github.signOut()
        for key in ["anthropic", "google_client_secret"] { try Keychain().delete(key) }
        try store.deleteAllData()
        let manager = FileManager.default
        for url in [paths.config, paths.log, paths.log.appendingPathExtension("previous")] where manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        if let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            for name in ["MorningBrief", "com.granth.morningbrief"] {
                let url = caches.appendingPathComponent(name, isDirectory: true)
                if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            }
        }
        if uninstall {
            trigger?.stop(); meetings?.stop(); try store.close(); self.store = nil
            try manager.trashItem(at: paths.directory, resultingItemURL: nil)
            let bundle = Bundle.main.bundleURL
            if bundle.pathExtension == "app", Bundle.main.bundleIdentifier == "com.granth.morningbrief" {
                try manager.trashItem(at: bundle, resultingItemURL: nil)
            }
            NSApp.terminate(nil)
        } else {
            settingsWindow.close(); loadConfig(); openSettings()
        }
    }

    private func runDaily() async -> Bool {
        guard !running, let store, (try? store.meta("onboarded")) == "true" else { return false }
        running = true
        defer { running = false }
        do {
            let day = Dates.day(Date())
            let brief: BriefDocument
            if let data = try store.brief(date: day) {
                brief = try JSONDecoder().decode(BriefDocument.self, from: data)
            } else {
                if try store.meta("dailyAttempt") == day {
                    brief = BriefGenerator.fallback(records: try enabledRecords(), now: Date(), succeeded: [], failed: [])
                } else {
                    try store.setMeta("dailyAttempt", day)
                    brief = try await makeBrief().document
                }
            }
            guard trigger?.eligible() == true, brief.date == Dates.day(Date()) else { return false }
            try displayBrief(brief)
            return briefWindow.isVisible
        } catch { status.title = "Daily brief could not open. Use Refresh to retry."; return false }
    }

    private func provider() -> any ModelProvider {
        guard let config else { return UnavailableProvider() }
        if config.model.provider == "apple_on_device" { return AppleProvider() }
        if config.model.provider == "anthropic", let key = try? Keychain().read("anthropic"),
           let value = String(data: key, encoding: .utf8), let model = config.model.modelID {
            return AnthropicProvider(key: value, model: model)
        }
        return UnavailableProvider()
    }
    private func makeBrief() async throws -> BriefResult {
        guard let store, let config else { throw ModelError.configuration }
        do { try store.prune(retentionDays: config.retentionDays) } catch { log?.record(.retentionFailed) }
        let outcome = await syncSources()
        var records = try enabledRecords()
        let states = try store.taskStates()
        for index in records.indices where states[records[index].key] == true { records[index].isOpen = false }
        let result = await BriefGenerator().generate(records: records, succeeded: outcome.succeeded.map(\.rawValue), failed: outcome.failed.map(\.rawValue), provider: provider())
        var document = result.document
        document.carry_over = try store.carryOver(excluding: Set(document.todos.map(\.id))).filter { isEnabledTask($0.id) }
        try store.saveBrief(date: document.date, data: JSONEncoder().encode(document))
        await meetings?.register((try? enabledRecords(source: .calendar)) ?? [])
        return BriefResult(document: document, usedFallback: result.usedFallback)
    }
    @objc private func generateBrief() {
        guard !running else { return }; running = true; loadConfig()
        Task {
            defer { running = false }
            do {
                let result = try await makeBrief()
                try displayBrief(result.document)
                status.title = result.usedFallback ? "Brief ready using source records" : "Brief ready"
            } catch { status.title = "Brief could not be saved. Try again." }
        }
    }
    private func displayBrief(_ brief: BriefDocument) throws {
        guard let config, let store else { return }
        let records = try enabledRecords()
        let keys = Set(records.map(\.key)), urls = Set(records.map(\.url))
        var document = brief
        document.sources_used = brief.sources_used.filter { Source(rawValue: $0).map(sourceEnabled) ?? false }
        document.failed_sources = brief.failed_sources.filter { Source(rawValue: $0).map(sourceEnabled) ?? false }
        document.todos = brief.todos.filter { keys.contains($0.id) }
        document.updates = brief.updates.filter { urls.contains($0.source_url) }
        document.replies = brief.replies.filter { urls.contains($0.thread_url) }
        document.carry_over = brief.carry_over.filter { isEnabledTask($0.id) }
        let current = BriefGenerator.fallback(records: records, now: Date(), succeeded: [], failed: [])
        document.schedule = current.schedule.map { meeting in
            var meeting = meeting
            meeting.prep = brief.schedule.first(where: { $0.event_id == meeting.event_id })?.prep ?? []
            return meeting
        }
        if !keys.contains(document.focus.source_id) { document.focus = Focus(title: "", detail: "", action: "open", source_id: "") }
        if document.schedule.isEmpty { document.greeting_line = "No meetings today. Your time is open." }
        try briefWindow.show(document, config: config, store: store, retry: { [weak self] in self?.generateBrief() }, signIn: google.needsSignIn ? { [weak self] in self?.signInGoogle() } : nil, action: { [weak self] key in
            guard let self, !self.actionRunning else { return "Preparation is already in progress." }
            self.actionRunning = true
            defer { self.actionRunning = false }
            self.loadConfig()
            do {
                let records = try self.enabledRecords()
                return await StickerAction().run(key: key, records: records, provider: self.provider()).text
            } catch { return "Source notes could not open. Refresh your brief." }
        })
    }
    @objc private func showToday() {
        loadConfig()
        do {
            guard let store else { return }
            let brief: BriefDocument
            if let data = try store.brief(date: Dates.day(Date())) { brief = try JSONDecoder().decode(BriefDocument.self, from: data) }
            else { brief = BriefGenerator.fallback(records: try enabledRecords(), now: Date(), succeeded: [], failed: []) }
            try displayBrief(brief)
        } catch { status.title = "Brief could not open. Try again." }
    }

    private func syncSources() async -> SyncOutcome {
        guard let store, let config else { return await SyncCoordinator.run([]) }
        let googleToken: String?
        if config.sources.calendar || config.sources.gmail || config.sources.drive { googleToken = try? await google.accessToken() } else { googleToken = nil }
        let githubToken: String?
        if config.sources.github { githubToken = try? await github.accessToken() } else { githubToken = nil }
        let googleAPI = API(token: googleToken ?? "")
        let githubAPI = API(token: githubToken ?? "")
        let account = google.accountID
        let attachments = Set((try? enabledRecords(source: .calendar))?.flatMap(\.attachmentIDs) ?? [])
        let calendarTask: Task<Void, Error>? = config.sources.calendar ? Task.detached {
            guard googleToken != nil else { throw AuthError.signInAgain }
            for calendar in config.calendars ?? ["primary"] { try await CalendarSync(api: googleAPI, store: store).sync(account: account, calendar: calendar) }
        } : nil
        var jobs: [SyncJob] = []
        if let calendarTask { jobs.append(SyncJob(.calendar) { try await calendarTask.value }) }
        if config.sources.gmail { jobs.append(SyncJob(.gmail) { guard googleToken != nil else { throw AuthError.signInAgain }; try await GmailSync(api: googleAPI, store: store).sync(account: account, excluded: config.gmail.excludeCategories, ignore: config.gmail.ignore, vip: config.gmail.vip) }) }
        if config.sources.drive { jobs.append(SyncJob(.drive) {
            guard googleToken != nil else { throw AuthError.signInAgain }
            try await DriveSync(api: googleAPI, store: store).sync(account: account, attachments: attachments, freshAttachments: {
                if let calendarTask { _ = await calendarTask.result }
                return Set(((try? store.records(source: .calendar)) ?? []).filter { $0.accountID == account && (config.calendars ?? ["primary"]).contains($0.scope) }.flatMap(\.attachmentIDs))
            })
        }) }
        if config.sources.github { jobs.append(SyncJob(.github) { guard githubToken != nil else { throw AuthError.signInAgain }; try await GitHubSync(api: githubAPI, store: store).sync() }) }
        return await SyncCoordinator.run(jobs)
    }
    @objc private func refreshSources() {
        guard !running else { return }; running = true
        loadConfig()
        Task {
            defer { running = false }
            status.title = "Syncing sources"
            let result = await syncSources()
            await meetings?.register((try? enabledRecords(source: .calendar)) ?? [])
            status.title = google.needsSignIn ? "Sign in again" : (result.failed.isEmpty ? "Sources synced" : "Some sources could not sync. Tap to retry.")
        }
    }

    @objc private func refreshCalendar() {
        guard let store, !running else { return }; running = true
        Task {
            defer { running = false }
            do {
                let api = API(token: try await google.accessToken())
                for calendar in config?.calendars ?? ["primary"] { try await CalendarSync(api: api, store: store).sync(account: google.accountID, calendar: calendar) }
                await meetings?.register((try? enabledRecords(source: .calendar)) ?? [])
                let events = try enabledRecords(source: .calendar).filter { $0.start.map { Calendar.current.isDateInToday($0) } ?? false }
                let lines = events.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }.map { "\($0.start!.formatted(date: .omitted, time: .shortened))  \($0.title)" }
                _ = showAuthWindow(lines.isEmpty ? "No meetings today." : lines.joined(separator: "\n"))
                status.title = "Calendar synced"
            } catch { status.title = google.needsSignIn ? "Sign in again" : "Calendar could not sync. Tap to retry." }
        }
    }

    private func showAuthWindow(_ text: String) -> NSWindow {
        let window = authWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Connect your sources"
        window.contentView = NSHostingView(rootView: Text(text).padding(32).frame(maxWidth: .infinity, maxHeight: .infinity))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        authWindow = window
        return window
    }
    @objc private func signInGoogle() {
        guard !running else { status.title = "Wait for the current refresh to finish."; return }
        loadConfig()
        let window = showAuthWindow("Calendar: read events and meeting links.\nGmail: read messages for your brief.\nDrive: read meeting notes and attachments.\nNothing is edited or sent. Tokens stay in Keychain.")
        authTask?.cancel()
        authTask = Task {
            do {
                let enabled = [config?.sources.calendar ?? false, config?.sources.gmail ?? false, config?.sources.drive ?? false]
                let scopes = zip(GoogleAuth.scopes, enabled).compactMap { $0.1 ? $0.0 : nil }
                guard !scopes.isEmpty else { status.title = "Enable a Google source in config."; return }
                let previous = google.accountID
                try await google.signIn(clientID: config?.oauth?.googleClientID, window: window, scopes: scopes)
                if previous != google.accountID { try store?.deleteAccount(previous); briefWindow.close(); meetings?.clear() }
                status.title = "Google connected"; window.close()
            } catch { status.title = (error as? AuthError)?.errorDescription ?? "Sign-in could not finish." }
        }
    }
    @objc private func signInGitHub() {
        guard !running else { status.title = "Wait for the current refresh to finish."; return }
        loadConfig(); authTask?.cancel(); google.cancel()
        authTask = Task {
            do {
                let code = try await github.start(clientID: config?.oauth?.githubClientID)
                let window = showAuthWindow("Enter this code on GitHub:\n\(code.user_code)\n\nRead notifications and public issues. Nothing is edited.")
                if let url = URL(string: code.verification_uri), url.scheme == "https", url.host == "github.com" { NSWorkspace.shared.open(url) }
                try await github.finish(code, clientID: config?.oauth?.githubClientID ?? "")
                status.title = "GitHub connected"; window.close()
            } catch { status.title = (error as? AuthError)?.errorDescription ?? "Sign-in could not finish." }
        }
    }
    @objc private func cancelSignIn() { authTask?.cancel(); google.cancel(); authWindow?.close() }

    @objc private func openConfig() {
        guard let paths else { return }
        NSWorkspace.shared.open(paths.config)
    }

    @objc private func openDataFolder() {
        guard let paths else { return }
        NSWorkspace.shared.open(paths.directory)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) { trigger?.stop(); meetings?.stop(); log?.record(.stopped) }
}
