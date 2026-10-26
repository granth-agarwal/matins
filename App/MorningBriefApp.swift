import AppKit
import Config
import OSLog
import Store
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
            status.title = store == nil ? "Database could not open. Restart to retry." : "Ready, \(config!.name)"
        } catch {
            log?.record(.configFailed)
            status.title = "Config could not load. Edit and reload."
        }
    }

    func menuWillOpen(_ menu: NSMenu) { loadConfig() }

    @objc private func reload() { loadConfig() }

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
