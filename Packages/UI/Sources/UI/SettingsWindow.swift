import AppKit
import SwiftUI
import Config

@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    public override init() { super.init() }
    public func close() { window?.close() }
    public func windowWillClose(_ notification: Notification) { window?.contentView = nil }
    public func show(config: AppConfig, onboarding: Bool, loginEnabled: Bool,
                     save: @escaping (AppConfig) throws -> Void,
                     begin: @escaping () throws -> Void,
                     login: @escaping (Bool) throws -> Void,
                     google: @escaping () -> Void, github: @escaping () -> Void,
                     notifications: @escaping () async -> Bool,
                     saveSecret: @escaping (String, String) throws -> Void,
                     signOut: @escaping () async throws -> Void,
                     deleteData: @escaping () async throws -> Void,
                     uninstall: @escaping () async throws -> Void,
                     openConfig: @escaping () -> Void) {
        let window = window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 780),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = onboarding ? "Welcome to Morning Brief" : "Morning Brief settings"
        window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width: 580, height: 580)
        window.contentView = NSHostingView(rootView: PreferencesPage(draft: config, loginEnabled: loginEnabled,
            onboarding: onboarding, save: save, begin: begin, login: login, google: google, github: github,
            notifications: notifications, saveSecret: saveSecret, signOut: signOut, deleteData: deleteData,
            uninstall: uninstall, openConfig: openConfig, close: { [weak window] in window?.close() }))
        if self.window == nil { window.center() }
        self.window = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PreferencesPage: View {
    @ViewState var draft: AppConfig
    @ViewState var loginEnabled: Bool
    let onboarding: Bool
    let save: (AppConfig) throws -> Void
    let begin: () throws -> Void
    let login: (Bool) throws -> Void
    let google, github: () -> Void
    let notifications: () async -> Bool
    let saveSecret: (String, String) throws -> Void
    let signOut, deleteData, uninstall: () async throws -> Void
    let openConfig, close: () -> Void
    @ViewState private var message: String?
    @ViewState private var credential = ""
    @ViewState private var credentialKind = "anthropic"
    @ViewState private var confirmation: String?
    @ViewState private var busy = false
    @ViewState private var consentCloud = false
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Form {
                    if onboarding {
                        Section("A calmer start") {
                            Text("Once each eligible morning, Morning Brief gathers your day. You can refresh whenever you choose.")
                            Text("Your default model runs on this Mac when available. Otherwise, a local brief uses source records. No analytics or telemetry is collected.")
                        }
                    }
                    Section("Your brief") {
                        TextField("Name", text: $draft.name)
                        TextField("Signature text or image path", text: $draft.signature)
                        HStack { TextField("After", text: $draft.triggerAfter); TextField("Latest", text: $draft.latestShowTime) }
                        TextField("Skip days, separated by commas", text: joined($draft.skipDays))
                        Toggle("Require an unlocked screen", isOn: $draft.requireUnlocked)
                        Stepper("Keep cached bodies for \(draft.retentionDays) days", value: $draft.retentionDays, in: 1...90)
                    }
                    Section("Read access only") {
                        Toggle("Calendar: events, attendees and meeting links", isOn: $draft.sources.calendar)
                        Toggle("Gmail: messages for your daily brief", isOn: $draft.sources.gmail)
                        Toggle("Drive: meeting documents and attachments", isOn: $draft.sources.drive)
                        Toggle("GitHub: notifications and accessible issue searches", isOn: $draft.sources.github)
                        Text("These connections never edit, send or delete anything in your accounts. You can disconnect at any time.").font(.callout).foregroundStyle(.secondary)
                        TextField("Calendar IDs, separated by commas", text: Binding(get: { (draft.calendars ?? ["primary"]).joined(separator: ", ") }, set: { draft.calendars = split($0) }))
                        TextField("Google desktop client ID", text: oauthBinding(google: true))
                        TextField("GitHub OAuth client ID", text: oauthBinding(google: false))
                        HStack { Button("Sign in with Google") { saveThen(google) }; Button("Sign in with GitHub") { saveThen(github) } }
                    }
                    Section("Model and privacy") {
                        Picker("Provider", selection: $draft.model.provider) {
                            Text("Apple on this Mac").tag("apple_on_device")
                            Text("Anthropic cloud").tag("anthropic")
                        }
                        if draft.model.provider == "anthropic" {
                            TextField("Anthropic model ID", text: Binding(get: { draft.model.modelID ?? "" }, set: { draft.model.modelID = $0 }))
                            Text("Cloud mode sends compact email text and other source records to Anthropic for synthesis and sticker actions. Choose it only if you want this data to leave your Mac.").font(.callout)
                            Toggle("I choose to send brief records to Anthropic", isOn: $consentCloud)
                        }
                        Text("There is no automatic switch from the on-device model to a cloud provider.").font(.callout).foregroundStyle(.secondary)
                        Picker("Credential", selection: $credentialKind) {
                            Text("Anthropic API key").tag("anthropic")
                            Text("Google client secret, if required").tag("google_client_secret")
                        }
                        SecureField("New credential", text: $credential)
                        Button("Store credential in Keychain") {
                            do {
                                guard !credential.isEmpty else { message = "Enter a credential first."; return }
                                try saveSecret(credentialKind, credential); credential = ""; message = "Credential stored in Keychain."
                            } catch { message = "Keychain could not save the credential." }
                        }
                    }
                    Section("Appearance and reminders") {
                        Picker("Palette", selection: $draft.palette.mode) { Text("Rotate daily").tag("auto"); Text("Pin one").tag("pinned") }
                        if draft.palette.mode == "pinned" {
                            Stepper("Pinned palette index: \(draft.palette.pinned ?? 0)", value: Binding(get: { draft.palette.pinned ?? 0 }, set: { draft.palette.pinned = $0 }), in: 0...31)
                        }
                        Toggle("Meeting pop-ups", isOn: $draft.popups.enabled)
                        Toggle("Quiet mode", isOn: Binding(get: { draft.popups.quietMode == true }, set: { draft.popups.quietMode = $0 }))
                        TextField("Quiet hours, such as 22:00-08:00", text: joined($draft.popups.quietHours))
                        Button("Enable notification fallback") {
                            Task { message = await notifications() ? "Notifications enabled." : "Notifications are unavailable. Check System Settings." }
                        }
                        Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: { value in
                            do { try login(value); loginEnabled = value; message = "Login preference updated." }
                            catch { message = "Login item could not change. Check System Settings." }
                        }))
                        Button("Open all preferences in config.yaml", action: openConfig)
                    }
                    Section("Your data") {
                        Text("Unchecked tasks survive retention. Delete all data removes local accounts, briefs, tasks, credentials and cached data, then resets preferences.").font(.callout)
                        HStack {
                            Button("Sign out of Google") { confirmation = "signout" }
                            Button("Delete all data", role: .destructive) { confirmation = "delete" }
                            Button("Quit and uninstall", role: .destructive) { confirmation = "uninstall" }
                        }
                    }
                    if let message { Text(message).foregroundStyle(.secondary).accessibilityLabel(message) }
                }.formStyle(.grouped).padding()
            }
            HStack {
                Button("Close", action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button(onboarding ? "Save and begin" : "Save settings") {
                    do {
                        guard draft.model.provider != "anthropic" || consentCloud else { message = "Confirm your cloud choice before saving."; return }
                        if draft.palette.mode == "pinned", draft.palette.pinned == nil { draft.palette.pinned = 0 }
                        try save(draft); try begin(); message = "Settings saved."; close()
                    } catch { message = "Settings could not save. Check times and preferences." }
                }.keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(minWidth: 580, minHeight: 580).disabled(busy)
        .onAppear { consentCloud = draft.model.provider == "anthropic" }
        .onDisappear { credential = "" }
        .alert("\(confirmationTitle)?", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("Cancel", role: .cancel) { confirmation = nil }
            Button(confirmationTitle, role: .destructive) {
                let action = confirmation; confirmation = nil; busy = true
                Task {
                    defer { busy = false }
                    do {
                        switch action {
                        case "signout": try await signOut(); message = "Google signed out. Its local data was removed."
                        case "delete": try await deleteData(); message = "Local data and credentials removed. Preferences reset."
                        case "uninstall": try await uninstall()
                        default: break
                        }
                    } catch { message = "The operation could not finish. Please try again." }
                }
            }
        } message: { Text(confirmation == "uninstall" ? "Remove the login item, local data and credentials, move this app to Trash, then quit. Credentials cannot be recovered from Trash." : "This removes the selected local data. Your connected services are never changed.") }
    }
    private var confirmationTitle: String {
        switch confirmation { case "signout": "Sign out of Google"; case "delete": "Delete all data"; default: "Quit and uninstall" }
    }
    private func split(_ text: String) -> [String] {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        return text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
    private func joined(_ values: Binding<[String]>) -> Binding<String> { Binding(get: { values.wrappedValue.joined(separator: ", ") }, set: { values.wrappedValue = split($0) }) }
    private func oauthBinding(google: Bool) -> Binding<String> {
        Binding(get: { (google ? draft.oauth?.googleClientID : draft.oauth?.githubClientID) ?? "" }, set: { value in
            var oauth = draft.oauth ?? AppConfig.OAuth()
            if google { oauth.googleClientID = value } else { oauth.githubClientID = value }
            draft.oauth = oauth
        })
    }
    private func saveThen(_ action: () -> Void) {
        do {
            guard draft.model.provider != "anthropic" || consentCloud else { message = "Confirm your cloud choice before saving."; return }
            try save(draft); action()
        } catch { message = "Save valid preferences before signing in." }
    }
}
