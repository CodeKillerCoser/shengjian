import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var voice: Voice
    @StateObject private var permissions = AppPermissions()
    @StateObject private var catalog = ModelCatalog()
    var body: some View {
        VStack(spacing: 0) {
        Form {
            PermissionSettings(permissions: permissions, appleEngine: voice.prefs.engine == "apple")
            Section("录音与快捷键") {
                HStack {
                    Text("全局录音快捷键")
                    Spacer()
                    if voice.capturingShortcut {
                        ShortcutRecorder(voice: voice).frame(width: 210, height: 30)
                        Button("取消") { voice.cancelCapture() }
                    } else {
                        Button(voice.shortcut.label + " · 点击修改") { voice.beginCapture() }
                            .disabled(voice.recording || voice.busy)
                    }
                    Button("恢复默认") { voice.applyShortcut(VoiceShortcut()) }
                        .disabled(voice.recording || voice.busy || voice.capturingShortcut)
                }
                Picker("触发方式", selection: Binding(get: { voice.prefs.triggerMode ?? "toggle" }, set: { voice.prefs.triggerMode = $0; voice.changeMode() })) {
                    Text("按一次开始／停止").tag("toggle")
                    Text("按住说话，松开结束").tag("hold")
                }.disabled(voice.recording || voice.busy || voice.capturingShortcut)
                Text(voice.shortcutHint).font(.callout)
                if !voice.shortcutStatus.isEmpty { Text(voice.shortcutStatus).font(.caption).foregroundStyle(.secondary) }
            }
            Section("文字输出") {
                Toggle("转写后复制到剪贴板", isOn: Binding(get: { voice.prefs.copiesResult }, set: { voice.prefs.copyAfterTranscription = $0 }))
                Toggle("转写后自动填写到输入框", isOn: $voice.prefs.autoInsert)
            }
            Section("语音转写") {
                Picker("识别引擎", selection: $voice.prefs.engine) { Text("Apple 本地识别").tag("apple"); Text("Whisper.cpp 本地模型").tag("whisper") }
                Picker("语言", selection: $voice.prefs.language) { Text("简体中文").tag("zh-CN"); Text("English").tag("en-US") }
                if voice.prefs.engine == "whisper" {
                    HStack { TextField("whisper-cli 路径", text: $voice.prefs.whisper); Button("选择") { pickFile { voice.prefs.whisper = $0 } } }
                    HStack { TextField("GGML 模型路径", text: $voice.prefs.modelPath); Button("选择") { pickFile { voice.prefs.modelPath = $0 } } }
                    Text("支持 whisper.cpp 的 GGML 模型；需自行安装 whisper-cli 和下载模型。").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("系统听写")
                        Spacer()
                        Button { voice.openKeyboardSettings() } label: {
                            Image(systemName: "arrow.up.forward.square").frame(width: 28, height: 28)
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("打开键盘与听写设置").accessibilityLabel("打开系统听写设置")
                    }
                }
            }
            Section("内容整理") {
                Toggle("转写后自动整理", isOn: $voice.prefs.online)
                TextField("模型服务地址", text: $voice.prefs.endpoint)
                HStack {
                    Text("模型名称")
                    Spacer(minLength: 16)
                    TextField("模型名称", text: $voice.prefs.model)
                        .labelsHidden().multilineTextAlignment(.trailing)
                        .frame(minWidth: 180, idealWidth: 310, maxWidth: 360)
                    ModelPopoverButton(models: catalog.models, selected: voice.prefs.model, loading: catalog.loading) {
                        voice.prefs.model = $0
                    }.frame(width: 22, height: 22)
                    if catalog.loading { ProgressView().controlSize(.small) }
                    Button { catalog.schedule(ModelDiscoveryInput(endpoint: voice.prefs.endpoint, key: voice.key)) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("重新探测模型").accessibilityLabel("重新探测模型")
                }
                SecureField("API Key", text: $voice.key, prompt: Text(catalog.savedKeyExists ? "••••••••" : ""))
                if !catalog.message.isEmpty { Text(catalog.message).font(.caption).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped)
        Divider()
        HStack {
            Spacer()
            Button("保存设置") { voice.save(); catalog.schedule(ModelDiscoveryInput(endpoint: voice.prefs.endpoint, key: voice.key)) }
                .buttonStyle(.borderedProminent)
        }.padding(.horizontal, 20).padding(.vertical, 12)
            .background(.bar)
        }
        .onAppear {
            permissions.refresh()
            catalog.schedule(ModelDiscoveryInput(endpoint: voice.prefs.endpoint, key: voice.key))
        }
        .onChange(of: ModelDiscoveryInput(endpoint: voice.prefs.endpoint, key: voice.key)) { input in catalog.schedule(input) }
        .onDisappear { catalog.cancel() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
    }
    func pickFile(_ selected: (String) -> Void) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { selected(url.path) }
    }
}
