import AppKit
import SwiftUI
import CoreText
import Brief
import Models
import Store
import Config
public typealias ViewState<Value> = SwiftUI.State<Value>

@MainActor
public final class BriefWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    public override init() { super.init() }
    public func windowWillClose(_ notification: Notification) { window?.contentView = nil }
    public var isVisible: Bool { window?.isVisible == true }
    public func close() { window?.close() }
    public func show(_ brief: BriefDocument, config: AppConfig, store: BriefStore,
                     retry: @escaping () -> Void, signIn: (() -> Void)? = nil, action: @escaping (String) async -> String) throws {
        let bundle = Bundle.main.url(forResource: "UI_UI", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? Bundle.module
        for name in ["Fraunces", "Fraunces-Italic", "Inter", "IBMPlexMono-Regular"] {
            if let url = bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Resources") { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
        let today = Dates.day(Date())
        let oldDate = try store.meta("paletteDate")
        let old = try store.meta("lastPaletteIndex").flatMap(Int.init)
        let palettes: [BriefPalette]
        switch config.palette.list {
        case .defaults: palettes = BriefPalette.defaults
        case .custom(let colors): palettes = colors.map { BriefPalette(name: $0.name, ground: $0.ground, glow1: $0.glow1, glow2: $0.glow2, accent: $0.accent) }
        }
        let yesterday = Dates.day(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let candidate = oldDate == today && config.palette.mode != "pinned" ? (old ?? 0) : BriefPalette.index(
            dayOfYear: Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1, previous: oldDate == yesterday ? old : nil,
            pinned: config.palette.mode == "pinned" ? config.palette.pinned : nil, count: palettes.count)
        let index = candidate % palettes.count
        try store.setMeta("lastPaletteIndex", String(index)); try store.setMeta("paletteDate", today)
        let window = window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 760, height: 600); window.backgroundColor = NSColor(calibratedWhite: 0.055, alpha: 1)
        window.contentView = NSHostingView(rootView: BriefPage(brief: brief, config: config, store: store,
            palette: palettes[index], allDayKeys: Set(try store.records(source: .calendar).filter(\.allDay).map(\.key)), checked: try store.taskStates(), retry: retry, signIn: signIn, action: action, close: { [weak window] in window?.close() }))
        if self.window == nil { window.center() }
        self.window = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct Starburst: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<32 {
            let angle = Double(i) * .pi / 16
            let radius = min(rect.width, rect.height) / 2 * (i.isMultiple(of: 2) ? 1 : 0.85)
            let point = CGPoint(x: rect.midX + cos(angle) * radius, y: rect.midY + sin(angle) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath(); return path
    }
}

private struct CheckTick: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(); path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.4, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct BriefPage: View {
    let brief: BriefDocument
    let config: AppConfig
    let store: BriefStore
    let palette: BriefPalette
    let allDayKeys: Set<String>
    @ViewState var checked: [String: Bool]
    let retry: () -> Void
    let signIn: (() -> Void)?
    let action: (String) async -> String
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var appeared = false
    @ViewState private var drift = false
    @ViewState private var selected = 0
    @ViewState private var taskIndex = 0
    @ViewState private var note: String?
    @ViewState private var working = false
    @ViewState private var error: String?
    @ViewState private var joinAvailable = false
    private var accent: Color { .hex(palette.accent) }
    private let muted = Color.hex("A8A39B")
    private func serif(_ size: CGFloat, italic: Bool = false) -> Font { .custom(italic ? "Fraunces-LightItalic" : "Fraunces-Regular", size: size) }
    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                Text(displayDate).font(serif(40, italic: true)).rotationEffect(.degrees(-90)).fixedSize().frame(width: 35, height: 260).padding(.top, 210)
                VStack(spacing: 34) {
                    signature.padding(.top, 38)
                    hero
                    HStack {
                        Text(caption).font(serif(19, italic: true))
                        Spacer()
                        Text("A MORNING BRIEF").font(.custom("IBMPlexMono-Regular", size: 10)).foregroundStyle(muted)
                    }
                    if let error { Text(error).foregroundStyle(muted) }
                    if let signIn { Button("Sign in again", action: signIn).buttonStyle(.plain).frame(minHeight: 44).foregroundStyle(muted) }
                    ForEach(brief.failed_sources, id: \.self) { source in
                        Button("\(source.capitalized) could not sync. Tap to retry.", action: retry).buttonStyle(.plain).frame(minHeight: 44).foregroundStyle(muted)
                    }
                    if config.sections.contains("focus") { section("Push your work forward", index: 1) { focus } }
                    if config.sections.contains("todos") { section("Top to-dos", index: 2) { todos } }
                    if !brief.carry_over.isEmpty { section("Carry-over", index: 2) { carryOver } }
                    if config.sections.contains("updates") { section("New updates", index: 3) { updates } }
                    if config.sections.contains("schedule"), !brief.schedule.isEmpty, !Calendar.current.isDateInWeekend(Date()) {
                        section("Your day", index: 4) { schedule }
                    }
                    Text("Made for you using Calendar, Gmail, and GitHub.").font(.custom("IBMPlexMono-Regular", size: 11)).foregroundStyle(muted).padding(.vertical, 45)
                }.frame(maxWidth: 900)
                Text(Date().formatted(date: .omitted, time: .shortened)).font(serif(40, italic: true)).rotationEffect(.degrees(90)).fixedSize().frame(width: 35, height: 260).padding(.top, 210)
            }.padding(.horizontal, 24).frame(maxWidth: .infinity)
        }
        .background(Color.hex("0E0E0E")).foregroundStyle(Color.hex("F2EFEA"))
        .font(.custom("Inter-Regular", size: 16)).lineSpacing(8.8).preferredColorScheme(.dark)
        .focusable().focusEffectDisabled()
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress("j") { taskIndex = min(max(0, brief.todos.count - 1), taskIndex + 1); return .handled }
        .onKeyPress("k") { taskIndex = max(0, taskIndex - 1); return .handled }
        .onKeyPress(.space) { if brief.todos.indices.contains(taskIndex) { toggle(brief.todos[taskIndex]) }; return .handled }
        .onKeyPress("e") {
            if brief.todos.indices.contains(taskIndex) {
                let item = brief.todos[taskIndex]; note = item.title + "\n\n" + item.source.capitalized + "\n" + item.source_url
            }
            return .handled
        }
        .onAppear { appeared = true; if !reduceMotion { drift = true } }
        .onChange(of: reduceMotion) { _, value in drift = !value }
        .task(id: selected) {
            joinAvailable = false
            guard brief.schedule.indices.contains(selected), let start = Dates.parse(brief.schedule[selected].start) else { return }
            let wait = start.addingTimeInterval(-900).timeIntervalSinceNow
            if wait > 0 { do { try await Task.sleep(for: .seconds(wait)) } catch { return } }
            if !Task.isCancelled { joinAvailable = true }
        }
        .sheet(isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            VStack(alignment: .leading, spacing: 20) { Text(note ?? "").textSelection(.enabled); Button("Done") { note = nil }.keyboardShortcut(.cancelAction) }.padding(32).frame(width: 520)
        }
    }
    private var displayDate: String {
        guard let date = Dates.parse(brief.date + "T12:00:00Z") else { return brief.date }
        let formatter = DateFormatter(); formatter.dateFormat = "dd MMM yyyy"; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date).uppercased()
    }
    private var caption: String {
        if Calendar.current.isDateInWeekend(Date()), !brief.schedule.isEmpty { return "A quieter weekend. Your schedule is tucked away." }
        return brief.greeting_line
    }
    @ViewBuilder private var signature: some View {
        if let image = NSImage(contentsOfFile: NSString(string: config.signature).expandingTildeInPath) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 150).accessibilityLabel("Signature")
        } else { Text(config.signature.hasSuffix(".png") ? config.name : config.signature).font(serif(30, italic: true)) }
    }
    private var hero: some View {
        ZStack {
            Color.hex(palette.ground)
            RadialGradient(colors: [.hex(palette.glow1).opacity(0.55), .clear], center: drift ? .topTrailing : .topLeading, startRadius: 0, endRadius: 500)
            RadialGradient(colors: [.hex(palette.glow2).opacity(0.3), .clear], center: drift ? .bottomLeading : .bottomTrailing, startRadius: 0, endRadius: 360)
            Color.black.opacity(palette.heroShade)
            VStack(spacing: 0) { Text("The").font(serif(33, italic: true)); Text("\(brief.weekday) Brief").font(serif(68)).minimumScaleFactor(0.5).lineLimit(1) }.foregroundStyle(accent).padding(32)
        }.frame(height: 420).clipShape(RoundedRectangle(cornerRadius: 4))
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: appeared)
        .animation(reduceMotion ? nil : .easeInOut(duration: 20).repeatForever(autoreverses: true), value: drift)
    }
    private func section<Content: View>(_ title: String, index: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 28) {
            Text(title).font(serif(24, italic: true)).frame(width: 210, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 20).opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(Double(index) * 0.06), value: appeared)
    }
    private var focus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(brief.focus.title.isEmpty ? "Nothing needs your attention yet." : brief.focus.title).font(.custom("Inter-Regular", size: 21)).bold()
            Text(brief.focus.detail).foregroundStyle(muted)
            if !brief.focus.source_id.isEmpty { sticker("Let's do it", id: brief.focus.source_id).offset(x: -28, y: 30).padding(.bottom, 15) }
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Color.hex("1A1A1A")))
    }
    private var todos: some View {
        VStack(alignment: .leading, spacing: 12) {
            if brief.todos.isEmpty { Text("Nothing needs doing right now.").foregroundStyle(muted) }
            ForEach(Array(brief.todos.prefix(config.caps.todos).enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 12) {
                    Button { toggle(item) } label: {
                        ZStack {
                            Circle().fill(checked[item.id] == true ? accent.opacity(0.15) : .clear).frame(width: 23, height: 23)
                            Circle().stroke(accent, lineWidth: 1.5).frame(width: 23, height: 23)
                            CheckTick().trim(from: 0, to: checked[item.id] == true ? 1 : 0).stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).frame(width: 12, height: 10)
                        }.frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("\(checked[item.id] == true ? "Uncheck" : "Complete") \(item.title)")
                    Button { open(item.source_url) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).strikethrough(checked[item.id] == true).opacity(checked[item.id] == true ? 0.55 : 1)
                            HStack { Text(item.label).foregroundStyle(Color.hex("F2EFEA")).padding(.horizontal, 8).padding(.vertical, 3).background(Color.hex(config.labels[item.label] ?? "30302B").opacity(0.18)).clipShape(Capsule()); Text(item.source) }.font(.custom("IBMPlexMono-Regular", size: 10)).foregroundStyle(muted)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityLabel("Open \(item.title)")
                }.background(index == taskIndex ? Color.white.opacity(0.035) : .clear)
            }
        }
    }
    private var updates: some View {
        VStack(alignment: .leading, spacing: 20) {
            if brief.updates.isEmpty { Text("Nothing new overnight.").foregroundStyle(muted) }
            ForEach(Array(brief.updates.prefix(config.caps.updates).enumerated()), id: \.offset) { index, item in
                Button { open(item.source_url) } label: { HStack(alignment: .top) { Text(String(format: "%02d", index + 1)).font(.custom("IBMPlexMono-Regular", size: 13)).foregroundStyle(muted); VStack(alignment: .leading) { Text(item.title); Text(item.detail).foregroundStyle(muted) } }.frame(minHeight: 44) }.buttonStyle(.plain)
            }
        }
    }
    private var carryOver: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(brief.carry_over, id: \.id) { item in
                Button {
                    do {
                        let value = !(checked[item.id] ?? false)
                        try store.setTask(id: item.id, title: item.title, checked: value)
                        checked[item.id] = value
                    } catch { self.error = "Task could not save. Try again." }
                } label: {
                    HStack {
                        Image(systemName: checked[item.id] == true ? "checkmark.circle.fill" : "circle").foregroundStyle(accent).frame(width: 44, height: 44)
                        VStack(alignment: .leading) {
                            Text(item.title).strikethrough(checked[item.id] == true)
                            Text("Backlog · \(item.age_days) days").font(.custom("IBMPlexMono-Regular", size: 11)).foregroundStyle(muted)
                        }
                    }
                }.buttonStyle(.plain).accessibilityLabel("Toggle carry-over task \(item.title)")
            }
        }
    }
    private var schedule: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(brief.schedule.enumerated()), id: \.element.event_id) { index, meeting in
                Button { selected = index } label: {
                    HStack { Text(allDayKeys.contains(meeting.event_id) ? "All day" : (Dates.parse(meeting.start)?.formatted(date: .omitted, time: .shortened) ?? "")).font(.custom("IBMPlexMono-Regular", size: 12)); Text(meeting.title); Spacer() }.padding(10).frame(minHeight: 44).background(index == selected ? Color.hex("25251E") : .clear)
                }.buttonStyle(.plain)
            }
            }.frame(maxWidth: .infinity)
            if brief.schedule.indices.contains(selected) {
                let meeting = brief.schedule[selected]
                VStack(alignment: .leading, spacing: 14) {
                    Text(meeting.title).font(serif(26))
                    ForEach(meeting.prep, id: \.self) { Text("• " + $0).foregroundStyle(muted) }
                    HStack {
                        if joinAvailable, !allDayKeys.contains(meeting.event_id), !meeting.join_url.isEmpty { Button("Join") { open(meeting.join_url) }.frame(minHeight: 44) }
                        if meeting.has_prep_action { sticker("Prep me", id: meeting.event_id) }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.hex("1A1A1A"))
            }
        }
    }
    private func sticker(_ title: String, id: String) -> some View {
        Button {
            guard !working else { return }; working = true
            Task { note = await action(id); working = false }
        } label: { Text(working ? "Preparing" : title).font(.custom("Inter-Regular", size: 13)).bold().foregroundStyle(Color.hex("0E0E0E")).frame(width: 100, height: 100).background(Starburst().fill(accent)).rotationEffect(.degrees(-8)) }
        .buttonStyle(.plain).disabled(working).accessibilityLabel(title)
    }
    private func toggle(_ item: Todo) {
        do {
            let value = !(checked[item.id] ?? false)
            try store.setTask(id: item.id, title: item.title, checked: value)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { checked[item.id] = value }
        } catch { self.error = "Task could not save. Try again." }
    }
    private func open(_ value: String) {
        if let url = URL(string: value), url.scheme == "https" { NSWorkspace.shared.open(url) }
    }
}
