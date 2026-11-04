import AppKit
import SwiftUI

struct BreezeView: View {
    @ObservedObject var model: BreezeController
    let rawText: String
    let rewrittenText: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Breeze · 本地语音合成", systemImage: "speaker.wave.2.fill").font(.headline)
                    Spacer()
                    Button("启动服务") { Task { await model.control("start") } }.disabled(model.busy)
                    Button("检查连接") { Task { await model.check() } }
                    Button("停止服务") { Task { await model.control("stop") } }.disabled(model.busy)
                }
                Text(model.status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Editor(title: "要朗读的文字", text: $model.text).frame(height: 150)
                HStack {
                    Button("使用识别原文") { model.text = rawText }.disabled(rawText.isEmpty)
                    Button("使用改写结果") { model.text = rewrittenText }.disabled(rewrittenText.isEmpty)
                }
                TextField("音色与语气描述（克隆时留空可保留原音风格）", text: $model.instruction)
                    .textFieldStyle(.roundedBorder)
                DisclosureGroup("声音克隆（可选）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("使用不超过 30 秒的清晰人声，支持 WAV、FLAC、OGG。参考文字应与音频中的原话一致，可手动填写或自动识别。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("选择参考音频") {
                                let panel = NSOpenPanel()
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK { model.selectReference(panel.url) }
                            }.disabled(model.busy)
                            Text(model.referenceURL?.lastPathComponent ?? "未选择").lineLimit(1)
                            if model.referenceURL != nil {
                                Button("清除") { model.selectReference(nil) }.disabled(model.busy)
                            }
                        }
                        TextField("参考音频的准确文字稿", text: $model.referenceText).textFieldStyle(.roundedBorder)
                            .disabled(model.busy)
                        HStack {
                            Button("自动识别文字") { model.recognizeReference() }
                                .disabled(!model.canRecognizeReference)
                            if model.recognizingReference {
                                ProgressView().controlSize(.small)
                                Button("取消识别") { model.cancelReferenceRecognition() }
                            }
                        }
                        Text("仅将语音转成文字，不做 AI 整理或改写。识别后可手动校对。")
                            .font(.caption).foregroundStyle(.secondary)
                        if !model.referenceStatus.isEmpty {
                            Text(model.referenceStatus).font(.caption).foregroundStyle(.secondary).textSelection(
                                .enabled)
                        }
                    }.padding(.top, 6)
                }
                HStack {
                    Button(model.busy ? "合成中…" : "生成并播放") { Task { await model.generate() } }
                        .buttonStyle(.borderedProminent).tint(.teal)
                        .disabled(!model.canGenerate)
                    if model.busy { ProgressView().controlSize(.small) }
                    if let url = model.audioURL {
                        Button("再次播放") { model.replay() }
                        Button("停止播放") { model.stopPlayback() }
                        Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Spacer()
                    Button("查看日志") {
                        if let root = model.root {
                            NSWorkspace.shared.open(root.appendingPathComponent("logs/service.log"))
                        }
                    }
                    Button("服务目录") { if let root = model.root { NSWorkspace.shared.open(root) } }
                }
                Text("模型与音频仅供研究和非商业用途。模型就绪后可断网使用。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.task {
            while !Task.isCancelled {
                if !model.busy && !model.ready { await model.check() }
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { break }
            }
        }
    }
}
