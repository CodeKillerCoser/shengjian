import AppKit
import SwiftUI

// Does not use AX or capture screen pixels: window bounds are enough to place
// the guide near System Settings, even before Accessibility is granted.
final class AuthorizationGuidePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct SettingsGuideWindow {
    let id: Int
    let frame: CGRect
    let isOnscreen: Bool

    init?(info: [String: Any], ownerPID: pid_t) {
        guard (info[kCGWindowOwnerPID as String] as? Int32) == ownerPID,
              (info[kCGWindowLayer as String] as? Int) == 0,
              let id = info[kCGWindowNumber as String] as? Int,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds),
              frame.width >= 400, frame.height >= 300 else { return nil }
        self.id = id; self.frame = frame
        isOnscreen = (info[kCGWindowIsOnscreen as String] as? Bool) == true
    }

    static func target(in windows: [SettingsGuideWindow], preferredID: Int?) -> SettingsGuideWindow? {
        let visible = windows.filter(\.isOnscreen)
        return visible.first { $0.id == preferredID } ?? visible.first
    }
}

enum AuthorizationGuideLayout {
    static func frame(settings: CGRect, visibleArea: CGRect) -> CGRect {
        let listLeft = settings.minX + min(252, settings.width * 0.341)
        let width = min(max(160, settings.maxX - 20 - listLeft),
                        min(settings.width, visibleArea.width) - 24)
        let x = min(max(listLeft, max(settings.minX, visibleArea.minX) + 12),
                    min(settings.maxX, visibleArea.maxX) - 12 - width)
        let y = min(max(settings.maxY - settings.height * 0.57 - 56,
                        max(settings.minY, visibleArea.minY) + 12),
                    min(settings.maxY, visibleArea.maxY) - 12 - 56)
        return CGRect(x: x, y: y, width: width, height: 56)
    }
}

@MainActor final class AuthorizationGuide {
    private let panel: AuthorizationGuidePanel
    private var timer: Timer?
    private weak var permissions: AppPermissions?
    private var lastPermissionRefresh = Date.distantPast
    private var targetWindowID: Int?
    private let started = Date()
    private var lastSeenWindow = Date()
    init(permissions: AppPermissions) {
        self.permissions = permissions
        panel = AuthorizationGuidePanel(contentRect: NSRect(x: 0, y: 0, width: 468, height: 56),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "辅助功能授权引导"
        panel.isExcludedFromWindowsMenu = false
        panel.isFloatingPanel = false; panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: AuthorizationGuideView(close: { [weak permissions] in permissions?.closeGuide() }))
    }
    func show() {
        placeNearSettings()
        NSApp.addWindowsItem(panel, title: panel.title, filename: false)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            // The timer is on the main run loop. Update directly so following
            // does not wait for a Task while AppKit is tracking a drag.
            MainActor.assumeIsolated { self?.update() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func update() {
        guard let permissions else { close(); return }
        if Date().timeIntervalSince(lastPermissionRefresh) >= 1 {
            lastPermissionRefresh = Date(); permissions.refresh()
        }
        if permissions.accessibility == .authorized {
            permissions.closeGuide(); return
        }
        placeNearSettings()
    }
    private func placeNearSettings() {
        guard let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
            panel.orderOut(nil)
            if targetWindowID != nil || Date().timeIntervalSince(started) > 5 { permissions?.closeGuide() }
            return
        }
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            panel.orderOut(nil); return
        }
        let settingsWindows = windows.compactMap { SettingsGuideWindow(info: $0, ownerPID: settings.processIdentifier) }
        guard let window = SettingsGuideWindow.target(in: settingsWindows, preferredID: targetWindowID) else {
            panel.orderOut(nil)
            // Opening an extension can replace the Settings window. Allow it
            // to reappear, but do not leave an invisible guide running forever
            // after the user closes the Settings window.
            if settingsWindows.isEmpty && Date().timeIntervalSince(lastSeenWindow) > 10 {
                permissions?.closeGuide()
            }
            return
        }
        let id = window.id
        targetWindowID = id
        lastSeenWindow = Date()
        // Offscreen includes minimization and moving to another Space. Never
        // leave an orphan card above another app or the desktop.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !settings.isHidden,
              front == "com.apple.systempreferences" || front == Bundle.main.bundleIdentifier else {
            panel.orderOut(nil); return
        }
        let rect = window.frame
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = NSRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height)
        let screen = NSScreen.screens.max(by: { $0.frame.intersection(frame).width * $0.frame.intersection(frame).height < $1.frame.intersection(frame).width * $1.frame.intersection(frame).height })
        let area = screen?.visibleFrame ?? frame
        // System Settings: 232 pt sidebar + 20 pt content inset; the
        // application list ends 20 pt before the right window edge.
        panel.setFrame(AuthorizationGuideLayout.frame(settings: frame, visibleArea: area), display: true)
        // Keep the card immediately above its target, at the normal window
        // level; it must not behave like an always-on-top utility panel.
        panel.order(.above, relativeTo: id)
    }
    func close() { NSApp.removeWindowsItem(panel); timer?.invalidate(); timer = nil; panel.orderOut(nil); panel.contentView = nil }
    deinit { timer?.invalidate() }
}

struct AuthorizationGuideView: View {
    let close: () -> Void
    var body: some View {
        AppFileDragView(onDropAccepted: close)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.98), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.08)).allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accentColor.opacity(0.4)).allowsHitTesting(false))
    }
}

// Native NSDraggingSession carries the actual .app file URL across processes.
struct AppFileDragView: NSViewRepresentable {
    var onDropAccepted: () -> Void = {}
    func makeNSView(context: Context) -> AppFileDragSource {
        let view = AppFileDragSource(); view.onDropAccepted = onDropAccepted
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel("声笺.app，拖入系统设置权限列表")
        return view
    }
    func updateNSView(_ view: AppFileDragSource, context: Context) { view.onDropAccepted = onDropAccepted }
}
final class AppFileDragSource: NSView, NSDraggingSource {
    var onDropAccepted: () -> Void = {}
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.draw(in: NSRect(x: 12, y: 10, width: 36, height: 36))
        ("声笺.app" as NSString).draw(at: NSPoint(x: 60, y: 29), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
        ("按住此处拖入权限列表 ↗" as NSString).draw(at: NSPoint(x: 60, y: 12), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40), contents: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard !operation.isEmpty else { return }
        onDropAccepted()
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
