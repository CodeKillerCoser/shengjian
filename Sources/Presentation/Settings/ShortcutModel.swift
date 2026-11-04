import Combine
import Foundation

@MainActor final class ShortcutModel: ObservableObject {
    @Published private(set) var capturing = false
    @Published var status = ""
    private(set) var held = false
    private let settings: AppSettings
    private let activity: ActivityState
    private let monitor: HotKeyMonitor?
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var shortcut: VoiceShortcut { settings.prefs.shortcut ?? VoiceShortcut() }
    var holdMode: Bool { settings.prefs.triggerMode == "hold" }
    var hint: String { shortcut.label + (holdMode ? " · 按住说话，松开结束" : " · 按一次开始，再按一次结束") }

    init(settings: AppSettings, activity: ActivityState, monitor: HotKeyMonitor?) {
        self.settings = settings
        self.activity = activity
        self.monitor = monitor
    }
    func start() {
        guard let monitor else { return }
        monitor.onChange = { [weak self] in self?.handle(pressed: $0) }
        if monitor.install() != 0 || monitor.register(shortcut) != 0 {
            status = "快捷键被占用或注册失败，请重新设置"
        }
    }
    func beginCapture() {
        guard activity.idle else { return }
        monitor?.unregister()
        held = false
        capturing = true
        status = "请按组合键；Esc 取消。至少包含 ⌘、⌥、⌃ 中的一个。"
    }
    func cancelCapture() {
        guard capturing else { return }
        capturing = false
        status = register(shortcut) ? "已取消，原快捷键保留" : "原快捷键注册失败，请重新设置"
    }
    func apply(_ candidate: VoiceShortcut) {
        guard activity.idle else { return }
        let previous = shortcut
        capturing = false
        if register(candidate) {
            settings.prefs.shortcut = candidate
            do {
                try settings.persist()
                status = "快捷键已保存：" + candidate.label
            } catch { status = "已启用，但保存失败：" + error.localizedDescription }
        } else {
            status = "该组合键被占用或不可注册，请换一个。"
            if !register(previous) { status += "原快捷键也不可用。" }
        }
    }
    func changeMode() {
        do {
            try settings.persist()
            status = "触发方式已保存"
        } catch { status = error.localizedDescription }
    }
    func handle(pressed: Bool) {
        guard !capturing else { return }
        if pressed {
            guard !held else { return }
            held = true
            onPress?()
        } else {
            held = false
            onRelease?()
        }
    }
    func stop() {
        held = false
        monitor?.stop()
    }
    private func register(_ value: VoiceShortcut) -> Bool { (monitor?.register(value) ?? 0) == 0 }
}
