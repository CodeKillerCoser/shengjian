import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppSettings
    @ObservedObject var shortcuts: ShortcutModel
    @ObservedObject var activity: ActivityState
    @ObservedObject var permissions: PermissionModel
    @ObservedObject var catalog: ModelCatalog
    @ObservedObject var inputs: AudioInputMonitor
    let guide: AuthorizationGuideController
    @ObservedObject var breezeEnvironment: BreezeEnvironment
    var body: some View {
        VStack(spacing: 0) {
            Form {
                PermissionSettings(
                    audioInputs: inputs, permissions: permissions, appleEngine: model.prefs.engine == "apple",
                    guide: guide)
                Section("录音与快捷键") {
                    HStack {
                        Text("全局录音快捷键")
                        Spacer()
                        if shortcuts.capturing {
                            ShortcutRecorder(model: shortcuts).frame(width: 210, height: 30)
                            Button("取消") { shortcuts.cancelCapture() }
                        } else {
                            Button(shortcuts.shortcut.label + " · 点击修改") { shortcuts.beginCapture() }
                                .disabled(activity.recording || activity.busy)
                        }
                        Button("恢复默认") { shortcuts.apply(VoiceShortcut()) }
                            .disabled(activity.recording || activity.busy || shortcuts.capturing)
                    }
                    Picker(
                        "触发方式",
                        selection: Binding(
                            get: { model.prefs.triggerMode ?? "toggle" },
                            set: {
                                model.prefs.triggerMode = $0
                                shortcuts.changeMode()
                            })
                    ) {
                        Text("按一次开始／停止").tag("toggle")
                        Text("按住说话，松开结束").tag("hold")
                    }.disabled(activity.recording || activity.busy || shortcuts.capturing)
                    Text(shortcuts.hint).font(.callout)
                    if !shortcuts.status.isEmpty { Text(shortcuts.status).font(.caption).foregroundStyle(.secondary) }
                }
                Section("文字输出") {
                    Toggle(
                        "转写后复制到剪贴板",
                        isOn: Binding(
                            get: { model.prefs.copiesResult }, set: { model.prefs.copyAfterTranscription = $0 }))
                    Toggle("转写后自动填写到输入框", isOn: $model.prefs.autoInsert)
                }
                MLXSettingsSection(environment: breezeEnvironment)
                Section("语音转写") {
                    Picker("识别引擎", selection: $model.prefs.engine) {
                        Text("Apple 本地识别").tag("apple")
                        Text("Whisper.cpp 本地模型").tag("whisper")
                    }
                    Picker("语言", selection: $model.prefs.language) {
                        Text("简体中文").tag("zh-CN")
                        Text("English").tag("en-US")
                    }
                    if model.prefs.engine == "whisper" {
                        HStack {
                            TextField("whisper-cli 路径", text: $model.prefs.whisper)
                            Button("选择") { pickFile { model.prefs.whisper = $0 } }
                        }
                        HStack {
                            TextField("GGML 模型路径", text: $model.prefs.modelPath)
                            Button("选择") { pickFile { model.prefs.modelPath = $0 } }
                        }
                        Text("支持 whisper.cpp 的 GGML 模型；需自行安装 whisper-cli 和下载模型。").font(.caption).foregroundStyle(
                            .secondary)
                    } else {
                        HStack {
                            Text("系统听写")
                            Spacer()
                            Button {
                                SystemSettings.openKeyboard()
                            } label: {
                                Image(systemName: "arrow.up.forward.square").frame(width: 28, height: 28)
                            }.buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("打开键盘与听写设置").accessibilityLabel("打开系统听写设置")
                        }
                    }
                }
                Section("内容整理") {
                    Toggle("转写后自动整理", isOn: $model.prefs.online)
                    TextField("模型服务地址", text: $model.prefs.endpoint)
                    HStack {
                        Text("模型名称")
                        Spacer(minLength: 16)
                        TextField("模型名称", text: $model.prefs.model)
                            .labelsHidden().multilineTextAlignment(.trailing)
                            .frame(minWidth: 180, idealWidth: 310, maxWidth: 360)
                        ModelPopoverButton(
                            models: catalog.models, selected: model.prefs.model, loading: catalog.loading
                        ) {
                            model.prefs.model = $0
                        }.frame(width: 22, height: 22)
                        if catalog.loading { ProgressView().controlSize(.small) }
                        Button {
                            catalog.schedule(ModelDiscoveryInput(endpoint: model.prefs.endpoint, key: model.key))
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain).help("重新探测模型").accessibilityLabel("重新探测模型")
                    }
                    SecureField("API Key", text: $model.key, prompt: Text(catalog.savedKeyExists ? "••••••••" : ""))
                    if !catalog.message.isEmpty { Text(catalog.message).font(.caption).foregroundStyle(.secondary) }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("保存设置") {
                    model.save()
                    catalog.schedule(ModelDiscoveryInput(endpoint: model.prefs.endpoint, key: model.key))
                }
                .buttonStyle(.borderedProminent)
            }.padding(.horizontal, 20).padding(.vertical, 12)
                .background(.bar)
        }
        .onAppear {
            permissions.refresh()
            catalog.schedule(ModelDiscoveryInput(endpoint: model.prefs.endpoint, key: model.key))
        }
        .onChange(of: ModelDiscoveryInput(endpoint: model.prefs.endpoint, key: model.key)) { _, input in
            catalog.schedule(input)
        }
        .onDisappear { catalog.cancel() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }
    func pickFile(_ selected: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { selected(url.path) }
    }
}
