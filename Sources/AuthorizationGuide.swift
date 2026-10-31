import AppKit
import SwiftUI

// Does not use AX or capture screen pixels: window bounds are enough to place
// the guide near System Settings, even before Accessibility is granted.
final class AuthorizationGuidePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AuthorizationGuide {
    private let panel: AuthorizationGuidePanel
    private var timer: Timer?
    private weak var permissions: AppPermissions?
    private var lastPermissionRefresh = Date.distantPast
    private var targetWindowID: Int?
    private let started = Date()
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
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
        let settingsWindows = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == settings.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }
        let window: [String: Any]?
        if let targetWindowID {
            window = settingsWindows.first { ($0[kCGWindowNumber as String] as? Int) == targetWindowID }
            if window == nil { permissions?.closeGuide(); return }
        } else {
            window = settingsWindows.first {
                guard let bounds = $0[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
                return frame.width >= 400 && frame.height >= 300 && ($0[kCGWindowIsOnscreen as String] as? Bool) == true
            }
        }
        guard let window, let id = window[kCGWindowNumber as String] as? Int else { panel.orderOut(nil); return }
        targetWindowID = id
        // Offscreen includes minimization and moving to another Space. Never
        // leave an orphan card above another app or the desktop.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !settings.isHidden, (window[kCGWindowIsOnscreen as String] as? Bool) == true,
              front == "com.apple.systempreferences" || front == Bundle.main.bundleIdentifier else {
            panel.orderOut(nil); return
        }
        guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds) else { panel.orderOut(nil); return }
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = NSRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height)
        let screen = NSScreen.screens.max(by: { $0.frame.intersection(frame).width * $0.frame.intersection(frame).height < $1.frame.intersection(frame).width * $1.frame.intersection(frame).height })
        let area = screen?.visibleFrame ?? frame
        // System Settings: 232 pt sidebar + 20 pt content inset; the
        // application list ends 20 pt before the right window edge.
        let listLeft = frame.minX + min(252, frame.width * 0.341)
        let listWidth = max(160, frame.maxX - 20 - listLeft)
        panel.setContentSize(NSSize(width: listWidth, height: 56))
        let anchor = NSPoint(x: listLeft, y: frame.maxY - frame.height * 0.57 - panel.frame.height)
        var origin = anchor
        origin.x = min(max(origin.x, max(frame.minX + 12, area.minX + 12)), min(frame.maxX - 12, area.maxX - 12) - panel.frame.width)
        origin.y = min(max(origin.y, max(frame.minY + 12, area.minY + 12)), min(frame.maxY - 12, area.maxY - 12) - panel.frame.height)
        panel.setFrameOrigin(origin)
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
