import AppKit
import Auth
import Config
import OSLog
import Store
import Sync
import Models
import Brief
import UI
import SwiftUI

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
    private let briefWindow = BriefWindowController()
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
        add("Generate brief", action: #selector(generateBrief), to: menu)
        add("Show today's brief", action: #selector(showToday), to: menu)
        add("Open config…", action: #selector(openConfig), to: menu)
        add("Reload config", action: #selector(reload), to: menu)
        add("Open data folder", action: #selector(openDataFolder), to: menu)
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
        } catch {
            status.title = "App data folder could not open"
            Logger(subsystem: "com.granth.morningbrief", category: "lifecycle")
                .error("App data folder could not open")
        }
    }

    private func loadConfig() {
        guard let paths else { return }
        do {
            config = try ConfigLoader(url: paths.config).load()
            log?.record(.configLoaded)
            status.title = google.needsSignIn ? "Sign in again" : (store == nil ? "Database could not open. Restart to retry." : "Ready, \(config!.name)")
        } catch {
            log?.record(.configFailed)
            status.title = "Config could not load. Edit and reload."
        }
    }

    func menuWillOpen(_ menu: NSMenu) { loadConfig() }

    @objc private func reload() { loadConfig() }

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
        guard let store else { throw ModelError.configuration }
        let outcome = await syncSources()
        let records = try store.records()
        let result = await BriefGenerator().generate(records: records, succeeded: outcome.succeeded.map(\.rawValue), failed: outcome.failed.map(\.rawValue), provider: provider())
        try store.saveBrief(date: result.document.date, data: JSONEncoder().encode(result.document))
        return result
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
        try briefWindow.show(brief, config: config, store: store, retry: { [weak self] in self?.generateBrief() }, action: { _ in "Preparation actions arrive in the next milestone." })
    }
    @objc private func showToday() {
        loadConfig()
        do {
            guard let store else { return }
            let brief: BriefDocument
            if let data = try store.brief(date: Dates.day(Date())) { brief = try JSONDecoder().decode(BriefDocument.self, from: data) }
            else { brief = BriefGenerator.fallback(records: try store.records(), now: Date(), succeeded: [], failed: []) }
            try displayBrief(brief)
        } catch { status.title = "Brief could not open. Try again." }
    }

    private func syncSources() async -> SyncOutcome {
        guard let store, let config else { return await SyncCoordinator.run([]) }
        let googleToken = try? await google.accessToken()
        let githubToken = try? await github.accessToken()
        let googleAPI = API(token: googleToken ?? "")
        let githubAPI = API(token: githubToken ?? "")
        let attachments = Set((try? store.records(source: .calendar))?.flatMap(\.attachmentIDs) ?? [])
        var jobs: [SyncJob] = []
        if config.sources.calendar { jobs.append(SyncJob(.calendar) { guard googleToken != nil else { throw AuthError.signInAgain }; try await CalendarSync(api: googleAPI, store: store).sync() }) }
        if config.sources.gmail { jobs.append(SyncJob(.gmail) { guard googleToken != nil else { throw AuthError.signInAgain }; try await GmailSync(api: googleAPI, store: store).sync(excluded: config.gmail.excludeCategories, ignore: config.gmail.ignore) }) }
        if config.sources.drive { jobs.append(SyncJob(.drive) { guard googleToken != nil else { throw AuthError.signInAgain }; try await DriveSync(api: googleAPI, store: store).sync(attachments: attachments) }) }
        if config.sources.github { jobs.append(SyncJob(.github) { guard githubToken != nil else { throw AuthError.signInAgain }; try await GitHubSync(api: githubAPI, store: store).sync() }) }
        return await SyncCoordinator.run(jobs)
    }
    @objc private func refreshSources() {
        loadConfig()
        Task {
            status.title = "Syncing sources"
            let result = await syncSources()
            status.title = google.needsSignIn ? "Sign in again" : (result.failed.isEmpty ? "Sources synced" : "Some sources could not sync. Tap to retry.")
        }
    }

    @objc private func refreshCalendar() {
        guard let store else { return }
        Task {
            do {
                try await CalendarSync(api: API(token: google.accessToken()), store: store).sync()
                let events = try store.records(source: .calendar).filter { $0.start.map { Calendar.current.isDateInToday($0) } ?? false }
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
        loadConfig()
        let window = showAuthWindow("Calendar: read events and meeting links.\nGmail: read messages for your brief.\nDrive: read meeting notes and attachments.\nNothing is edited or sent. Tokens stay in Keychain.")
        authTask?.cancel()
        authTask = Task {
            do {
                let enabled = [config?.sources.calendar ?? false, config?.sources.gmail ?? false, config?.sources.drive ?? false]
                let scopes = zip(GoogleAuth.scopes, enabled).compactMap { $0.1 ? $0.0 : nil }
                guard !scopes.isEmpty else { status.title = "Enable a Google source in config."; return }
                try await google.signIn(clientID: config?.oauth?.googleClientID, window: window, scopes: scopes)
                status.title = "Google connected"; window.close()
            } catch { status.title = (error as? AuthError)?.errorDescription ?? "Sign-in could not finish." }
        }
    }
    @objc private func signInGitHub() {
        loadConfig(); authTask?.cancel()
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

    func applicationWillTerminate(_ notification: Notification) { log?.record(.stopped) }
}
