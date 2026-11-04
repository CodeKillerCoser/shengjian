import SwiftUI

struct DictationView: View {
    @ObservedObject var model: DictationModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var inputs: AudioInputMonitor
    @ObservedObject var shortcuts: ShortcutModel
    var body: some View {
        VStack(spacing: 12) {
            if model.status != "就绪" {
                Text(model.status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 16) {
                    Editor(title: "热词", text: $settings.prefs.hotwords)
                    Editor(title: "整理规则", text: $settings.prefs.prompt)
                }.frame(minHeight: 120, idealHeight: 160, maxHeight: 220)
                HStack {
                    Text(settings.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("保存") { settings.save() }.help("保存热词与整理规则")
                }
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.recording ? "测试 · 正在聆听" : "测试").font(.headline)
                    if model.recording {
                        Text("\(Int(recorder.elapsed) / 60):\(String(format: "%02d", Int(recorder.elapsed) % 60))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                AudioWaveform(levels: recorder.levels, active: model.recording)
                    .frame(height: 24)
                    .accessibilityLabel(model.recording ? "麦克风波形，音量 \(Int(recorder.meterDB)) 分贝" : "麦克风待机")
                Button(model.recording ? "停止录音" : "开始录音", systemImage: model.recording ? "stop.fill" : "mic.fill") {
                    model.toggle()
                }
                .buttonStyle(.borderedProminent).tint(model.recording ? .red : .teal)
                .disabled(model.busy || shortcuts.capturing || (!inputs.hasInput && !model.recording))
            }.padding(.horizontal, 14).padding(.vertical, 8).background(
                .teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            if !inputs.hasInput {
                Label(AudioInputMonitor.missingMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.hasRetryAudio {
                VStack(alignment: .leading, spacing: 8) {
                    Text("录音已保存在本机转写历史；可修改设置后重新识别。").font(.callout)
                    if model.showSpeechHelp {
                        Text("前往系统设置 → 键盘 → 听写，启用并准备对应语言资源；若仍不可用，可改用独立的 Whisper 本地模型。").font(.caption).foregroundStyle(
                            .secondary)
                    }
                    HStack {
                        if model.showSpeechHelp { Button("打开键盘设置") { SystemSettings.openKeyboard() } }
                        Button("重新识别本次录音") { model.recognizeRecording() }.disabled(model.busy)
                        Button("关闭提示") { model.discardRecording() }.disabled(model.busy)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if !model.technicalError.isEmpty {
                DisclosureGroup("错误详情") {
                    Text(model.technicalError).font(.caption).textSelection(.enabled).frame(
                        maxWidth: .infinity, alignment: .leading)
                }
            }
            if model.transcriptReady {
                Editor(title: "原文", text: $model.raw).frame(minHeight: 90)
            }
            if model.rewriteReady {
                Editor(title: "改写", text: $model.output).frame(minHeight: 90)
            }
            if !model.transcriptReady && !model.rewriteReady { Spacer(minLength: 0) }
        }.padding()
    }
}
