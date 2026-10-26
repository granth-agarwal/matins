import AppKit
import SwiftUI
import Models

private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PopupWindow: NSObject {
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    func show(_ record: SourceRecord, action: @escaping (String) -> Void) {
        dismiss()
        let panel = ReminderPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 215),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ReminderCard(record: record, action: action))
        self.panel = panel
        position()
        let final = panel.frame
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0; panel.setFrameOrigin(NSPoint(x: final.minX - 24, y: final.minY))
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35; panel.animator().alphaValue = 1; panel.animator().setFrame(final, display: true)
            }
        }
    }
    func position() {
        guard let panel else { return }
        let screen = activeScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.minX + 20, y: frame.minY + 20))
    }
    private func activeScreen() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary),
                  let top = NSScreen.screens.first?.frame.maxY else { continue }
            let rect = CGRect(x: bounds.minX, y: top - bounds.maxY, width: bounds.width, height: bounds.height)
            return NSScreen.screens.max { left, right in
                let a = left.frame.intersection(rect), b = right.frame.intersection(rect)
                return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
            }
        }
        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }
    func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
    }
}

private struct ReminderCard: View {
    let record: SourceRecord
    let action: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.title).font(.system(size: 20, weight: .semibold)).lineLimit(2)
            HStack {
                Text(record.start?.formatted(date: .omitted, time: .shortened) ?? "")
                Text("\(record.attendeeCount) attendees")
            }.font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int((record.start ?? context.date).timeIntervalSince(context.date)))
                Text(seconds > 0 ? "Starts in \(seconds / 60):\(String(format: "%02d", seconds % 60))" : "Meeting has started")
                    .font(.system(size: 13, design: .monospaced))
            }
            HStack {
                Button("Join") { action("join") }.disabled(record.joinURL == nil).accessibilityLabel("Join \(record.title)")
                Button("Snooze 2 min") { action("snooze") }.accessibilityLabel("Snooze for two minutes")
                Button("Ignore") { action("ignore") }.accessibilityLabel("Ignore this meeting")
            }.buttonStyle(.bordered).controlSize(.large).frame(minHeight: 44)
        }.padding(20).frame(width: 430, height: 215, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.10, blue: 0.10)))
        .foregroundStyle(Color(red: 0.95, green: 0.94, blue: 0.92)).preferredColorScheme(.dark)
    }
}
