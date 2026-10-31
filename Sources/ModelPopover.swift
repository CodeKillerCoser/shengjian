import AppKit
import SwiftUI

/// A real AppKit popover anchored to the click, rather than the entire form row.
struct ModelPopoverButton: NSViewRepresentable {
    var models: [String]
    var selected: String
    var loading: Bool
    var select: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "选择模型")!, target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.setAccessibilityLabel("选择模型")
        button.toolTip = "选择服务提供的模型"
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.input = self
    }
    static func dismantleNSView(_ view: NSButton, coordinator: Coordinator) { coordinator.popover?.close() }

    final class Coordinator: NSObject {
        var input: ModelPopoverButton?
        fileprivate var popover: ModelSelectionPopover?
        @objc func open(_ sender: NSButton) {
            if let popover, popover.isShown { popover.close(); return }
            guard let input, let window = sender.window else { return }
            // Mouse position is in the source window's coordinates; show() requires
            // a rect in the source view's local coordinates. Keep a tiny anchor so
            // the arrow points at the click rather than the row's midpoint.
            let event = NSApp.currentEvent
            let mouse = event?.window === window ? event!.locationInWindow : window.mouseLocationOutsideOfEventStream
            let local = sender.convert(mouse, from: nil)
            let anchor = NSRect(x: local.x - 1, y: local.y - 1, width: 2, height: 2)
            let screenPoint = window.convertPoint(toScreen: mouse)
            let bounds = window.convertToScreen(window.contentView!.bounds).insetBy(dx: 16, dy: 16)
            let font = NSFont.systemFont(ofSize: 13)
            let labels = input.models.isEmpty ? [input.loading ? "正在探测模型…" : "未发现模型，可手动填写"] : input.models
            let naturalWidth = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 180
            let width = min(max(180, ceil(naturalWidth) + 52), min(520, bounds.width - 24))
            var height = min(CGFloat(labels.count) * 30 + 12, 240)
            let above = bounds.maxY - screenPoint.y - 14
            let below = screenPoint.y - bounds.minY - 14
            // Vertical placement only. The native popover keeps the click anchor
            // while choosing the side with enough vertical space.
            let opensAbove = above >= height || above >= below
            // NSRectEdge is expressed in the source view's coordinate system.
            let upperEdge: NSRectEdge = sender.isFlipped ? .minY : .maxY
            let lowerEdge: NSRectEdge = sender.isFlipped ? .maxY : .minY
            let edge = opensAbove ? upperEdge : lowerEdge
            height = min(height, max(60, opensAbove ? above : below))
            let stack = NSStackView()
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0
            stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
            for (index, label) in labels.enumerated() {
                let row = NSButton(title: label, target: self, action: #selector(choose(_:)))
                row.font = font; row.isBordered = false; row.alignment = .left
                row.lineBreakMode = .byTruncatingMiddle
                row.tag = index; row.isEnabled = !input.models.isEmpty
                if label == input.selected { row.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "当前模型"); row.imagePosition = .imageTrailing }
                row.widthAnchor.constraint(equalToConstant: width - 12).isActive = true
                row.heightAnchor.constraint(equalToConstant: 30).isActive = true
                stack.addArrangedSubview(row)
            }
            stack.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat(labels.count) * 30 + 12)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            scroll.drawsBackground = false; scroll.hasVerticalScroller = stack.frame.height > height
            scroll.documentView = stack
            let popover = ModelSelectionPopover(content: scroll, size: NSSize(width: width, height: height))
            self.popover = popover
            popover.show(relativeTo: anchor, of: sender, preferredEdge: edge)

        }
        @objc func choose(_ sender: NSButton) {
            guard let input, input.models.indices.contains(sender.tag) else { return }
            input.select(input.models[sender.tag]); popover?.close()
        }
    }
}

/// Owner-window constrained popover. NSPopover only constrains to the screen;
/// moving its window also moves its arrow. This shell controls both together.
private final class ModelSelectionPopover {
    private let panel: NSPanel
    private let contentSize: NSSize
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    var isShown: Bool { panel.isVisible }
    init(content: NSView, size: NSSize) {
        contentSize = size
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height + 10)),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isReleasedWhenClosed = false
        let shell = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        shell.material = .popover; shell.state = .active; shell.blendingMode = .behindWindow
        shell.wantsLayer = true
        shell.addSubview(content)
        panel.contentView = shell
    }
    func show(relativeTo rect: NSRect, of source: NSView, preferredEdge: NSRectEdge) {
        guard let owner = source.window, let shell = panel.contentView, let content = shell.subviews.first else { return }
        let anchor = owner.convertPoint(toScreen: source.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil))
        let bounds = owner.convertToScreen(owner.contentView!.bounds).insetBy(dx: 12, dy: 12)
        let above = preferredEdge == (source.isFlipped ? .minY : .maxY)
        let totalHeight = contentSize.height + 10
        let x = min(max(anchor.x - contentSize.width / 2, bounds.minX), bounds.maxX - contentSize.width)
        let y = above ? anchor.y + 2 : anchor.y - totalHeight - 2
        panel.setFrame(NSRect(x: x, y: y, width: contentSize.width, height: totalHeight), display: false)
        shell.frame = NSRect(origin: .zero, size: panel.frame.size)
        content.frame = NSRect(x: 0, y: above ? 10 : 0, width: contentSize.width, height: contentSize.height)
        let arrowX = min(max(anchor.x - x, 18), contentSize.width - 18)
        let path = CGMutablePath()
        path.addRoundedRect(in: content.frame, cornerWidth: 12, cornerHeight: 12)
        let baseY: CGFloat = above ? 10 : contentSize.height
        path.move(to: CGPoint(x: arrowX - 9, y: baseY))
        path.addLine(to: CGPoint(x: arrowX, y: above ? 0 : totalHeight))
        path.addLine(to: CGPoint(x: arrowX + 9, y: baseY)); path.closeSubpath()
        let mask = CAShapeLayer(); mask.path = path; shell.layer?.mask = mask
        owner.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }
            } else if event.window !== self.panel { self.close() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.close() }
    }
    func close() {
        panel.parent?.removeChildWindow(panel); panel.orderOut(nil)
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
    }
    deinit { close() }
}
