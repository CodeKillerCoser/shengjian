import SwiftUI

@main struct ShengjianApp: App {
    @StateObject private var app: AppModel
    init() {
        LaunchDiagnostics.runIfRequested()
        SingleInstance.enforce()
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--history-preview"), args.indices.contains(index + 1) {
            let preview = AppModel(directory: URL(fileURLWithPath: args[index + 1]), systemIntegration: false)
            _app = StateObject(wrappedValue: preview)
            if args.contains("--overlay-preview") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { preview.dictation.showOverlayPreview() }
            }
        } else {
            _app = StateObject(wrappedValue: AppModel())
        }
    }
    var body: some Scene {
        WindowGroup("声笺", id: "main") { ContentView(app: app) }.defaultSize(width: 820, height: 620)
        MenuBarExtra {
            MenuContent(model: app.dictation, shortcuts: app.shortcuts)
        } label: {
            RecordingMenuLabel(model: app.dictation)
        }
    }
}

private struct RecordingMenuLabel: View {
    @ObservedObject var model: DictationModel
    var body: some View { Label("声笺", systemImage: model.recording ? "mic.fill" : "waveform") }
}

private struct MenuContent: View {
    @ObservedObject var model: DictationModel
    @ObservedObject var shortcuts: ShortcutModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.status)
        Text(shortcuts.hint)
        Button("打开设置与听写") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("退出") { NSApp.terminate(nil) }
    }
}
