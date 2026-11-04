import AppKit
import Carbon
import SwiftUI

final class KeyCaptureView: NSView {
    var capture: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { capture?(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        capture?(event)
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        ("按下新组合键…" as NSString).draw(
            at: NSPoint(x: 12, y: 6),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
    }
}
struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: ShortcutModel
    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.capture = { event in
            if event.keyCode == UInt16(kVK_Escape) {
                model.cancelCapture()
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                model.status = "请加上 ⌘、⌥ 或 ⌃，避免占用普通打字按键。"
                return
            }
            var carbon: UInt32 = 0
            var label = ""
            if flags.contains(.control) {
                carbon |= UInt32(controlKey)
                label += "⌃"
            }
            if flags.contains(.option) {
                carbon |= UInt32(optionKey)
                label += "⌥"
            }
            if flags.contains(.shift) {
                carbon |= UInt32(shiftKey)
                label += "⇧"
            }
            if flags.contains(.command) {
                carbon |= UInt32(cmdKey)
                label += "⌘"
            }
            let names: [UInt16: String] = [
                49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑",
            ]
            let key = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            label += key
            model.apply(VoiceShortcut(keyCode: UInt32(event.keyCode), modifiers: carbon, label: label))
        }
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }
    func updateNSView(_ view: KeyCaptureView, context: Context) {}
}
