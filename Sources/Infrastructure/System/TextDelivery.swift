import AppKit

struct DeliveryResult {
    let message: String
    let success: Bool
}

// A session captures the original target. Every async boundary checks the
// session again so a cancelled or superseded dictation cannot type elsewhere.
@MainActor final class TextDelivery {
    private(set) var sessionID = UUID()
    private(set) var cancelled = false
    private(set) var backgroundSession = false
    private var target: NSRunningApplication?
    private var targetElement: AXUIElement?

    func begin() {
        sessionID = UUID()
        cancelled = false
        targetElement = nil
        let front = NSWorkspace.shared.frontmostApplication
        backgroundSession = front != nil && front?.processIdentifier != ProcessInfo.processInfo.processIdentifier
        target = backgroundSession ? front : nil
    }
    func captureFocusedElement() { targetElement = focusedElement(of: target) }
    func cancel() {
        cancelled = true
        sessionID = UUID()
    }
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    func focusedElement(of app: NSRunningApplication?) -> AXUIElement? {
        guard let app else { return nil }
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute as CFString, &value)
                == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }
    func canAcceptText(_ element: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if subrole as? String == "AXSecureTextField" { return false }
        var writable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writable) == .success,
            writable.boolValue
        {
            return true
        }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        return ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role as? String ?? "")
    }
    func editableValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
    func insert(_ text: String, preserveClipboard: Bool = false) async -> DeliveryResult? {
        guard !text.isEmpty, !cancelled else { return nil }
        let clipboardFeedback = preserveClipboard ? "剪贴板未更改" : "结果已复制"
        let successFeedback = preserveClipboard ? "已填写" : "已填写并复制到剪贴板"
        guard let target, !target.isTerminated else {
            return DeliveryResult(message: "未找到原输入框，\(clipboardFeedback)", success: false)
        }
        let expectedElement = targetElement
        let session = sessionID
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier { target.activate() }
        guard let executable = Bundle.main.executableURL else { return nil }
        let permission = await Task.detached { AccessibilityProbe.fresh(executable: executable) }.value
        guard sessionID == session, !cancelled else { return nil }
        guard let permission else {
            return DeliveryResult(message: "权限检测失败，\(clipboardFeedback)，请稍后重试", success: false)
        }
        guard permission.trusted && permission.canPostEvents else {
            return DeliveryResult(message: "辅助功能未开启，\(clipboardFeedback)；请在设置页完成授权", success: false)
        }
        // Wait for app activation and release of shortcut modifiers before posting Cmd+V.
        for _ in 0..<30 {
            guard sessionID == session, !cancelled else { return nil }
            let modifiers = CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
                && modifiers.isEmpty
            {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard sessionID == session, !cancelled else { return nil }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
            let focused = focusedElement(of: target), canAcceptText(focused)
        else {
            return DeliveryResult(message: "当前没有可输入区域，\(clipboardFeedback)", success: false)
        }
        if let expectedElement, !CFEqual(expectedElement, focused) {
            return DeliveryResult(message: "输入框已改变，\(clipboardFeedback)，请手动粘贴", success: false)
        }
        let modifiers = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        guard modifiers.isEmpty else {
            return DeliveryResult(message: "快捷键尚未松开，\(clipboardFeedback)，请松开后重试", success: false)
        }
        let previousValue = editableValue(focused)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return DeliveryResult(message: "无法发送粘贴，\(clipboardFeedback)", success: false)
        }
        let previousClipboard = preserveClipboard ? ClipboardSnapshot() : nil
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let pasteboardWriteCount = NSPasteboard.general.changeCount
        defer { previousClipboard?.restore(ifUnchanged: pasteboardWriteCount) }
        down.flags = .maskCommand
        up.flags = .maskCommand
        // Standard paste updates the editor's own document/input state.
        // AXSelectedText may acknowledge writes without changing web/Electron editors.
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 40_000_000)
        up.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard sessionID == session, !cancelled else { return nil }
        if let previousValue, let newValue = editableValue(focused) {
            if newValue != previousValue {
                return DeliveryResult(message: successFeedback, success: true)
            } else {
                try? await Task.sleep(nanoseconds: 400_000_000)
                let verified = editableValue(focused).map { $0 != previousValue } ?? false
                return DeliveryResult(
                    message: verified ? successFeedback : "已发送粘贴，但未检测到输入变化；\(clipboardFeedback)", success: verified)
            }
        } else {
            return DeliveryResult(message: "已发送粘贴（目标应用不支持核验）", success: true)
        }
    }
}
