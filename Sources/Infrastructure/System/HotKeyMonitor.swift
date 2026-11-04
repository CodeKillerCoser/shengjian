import Carbon
import Foundation

@MainActor final class HotKeyMonitor {
    var onChange: ((Bool) -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func install() -> OSStatus {
        guard handler == nil else { return noErr }
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        return InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                Task { @MainActor in monitor.onChange?(pressed) }
                return noErr
            }, 2, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: VoiceShortcut) -> OSStatus {
        unregister()
        return RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: 0x5256_4F49, id: 1), GetApplicationEventTarget(), 0, &hotKey)
    }
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
    func stop() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        onChange = nil
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
