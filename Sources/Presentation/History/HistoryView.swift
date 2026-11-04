import AppKit
import SwiftUI

func seconds(_ value: Double) -> String { String(format: "%.2f 秒", value) }
struct RunMetrics: View {
    let run: ProcessingRun
    let audioDuration: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("模型：" + run.model).font(.callout.weight(.medium)).textSelection(.enabled)
            Text("服务：" + run.service + (run.language.map { " · " + $0 } ?? ""))
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack(spacing: 12) {
                Label(seconds(run.elapsed), systemImage: "timer")
                if let audioDuration, audioDuration > 0 {
                    Text(String(format: "实时率 RTF %.3f", run.elapsed / audioDuration))
                }
            }.font(.caption).foregroundStyle(.secondary)
            if let usage = run.usage, usage.input != nil || usage.output != nil || usage.total != nil {
                Text(
                    "用量：输入 \(usage.input.map(String.init) ?? "未返回") / 输出 \(usage.output.map(String.init) ?? "未返回") / 合计 \(usage.total.map(String.init) ?? "未返回") tokens"
                )
                .font(.caption).foregroundStyle(.secondary)
                if let output = usage.output, output > 0, run.elapsed > 0 {
                    Text(String(format: "端到端输出速率 %.1f tokens/s（包含等待和网络时间）", Double(output) / run.elapsed))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(audioDuration == nil ? "用量：接口未返回 token 统计" : "用量：本地识别不提供 token 统计")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("CPU / GPU 算力、能耗：引擎未提供，未估算")
                .font(.caption).foregroundStyle(.secondary)
            if audioDuration == nil {
                Text(run.modelReported ? "模型名称由服务返回" : "模型名称来自请求配置，服务未确认实际版本")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct RunCard: View {
    let title: String
    let run: ProcessingRun?
    let audioDuration: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let run {
                    Text(run.success ? "完成" : "失败").font(.caption).foregroundStyle(run.success ? .teal : .orange)
                }
            }
            if let run {
                RunMetrics(run: run, audioDuration: audioDuration)
                Text(run.date.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                Divider()
                if let error = run.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                if !run.text.isEmpty {
                    Text(run.text).font(.system(size: 14)).textSelection(.enabled).frame(
                        maxWidth: .infinity, alignment: .leading)
                }
                if let input = run.inputText {
                    DisclosureGroup("本次整理使用的识别原文") {
                        Text(input).font(.callout).textSelection(.enabled).frame(
                            maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("尚未处理").foregroundStyle(.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}
struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("转写历史 · \(model.records.count)").font(.headline)
                TextField("搜索文字或模型", text: $model.query).textFieldStyle(.roundedBorder)
                if model.records.isEmpty {
                    ContentUnavailableView("还没有录音", systemImage: "waveform", description: Text("新录音会自动保存在本机，包含失败记录。"))
                } else {
                    List(model.filtered, selection: $model.selectedID) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.title).lineLimit(2)
                            Text(record.created.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                .foregroundStyle(.secondary)
                            Text(
                                String(
                                    format: "音频 %.1f 秒 · 转写 %d 次 · 整理 %d 次", record.duration,
                                    record.transcriptions.count, record.cleanups.count)
                            )
                            .font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).tag(record.id)
                    }.listStyle(.plain)
                }
                Text(model.status.isEmpty ? "音频与结果保存在本机，不自动上传。" : model.status)
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(width: 240)
            Divider()
            if let record = model.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(record.created.formatted(date: .complete, time: .standard)).font(.headline)
                        HStack {
                            Label(String(format: "原始音频 · %.1f 秒 · WAV", record.duration), systemImage: "waveform")
                            Spacer()
                            Button(
                                model.playingID == record.id ? "停止播放" : "播放音频",
                                systemImage: model.playingID == record.id ? "stop.fill" : "play.fill"
                            ) { model.play(record.id) }
                            .disabled(model.recording)
                            Button("显示文件") {
                                NSWorkspace.shared.activateFileViewerSelecting([model.audioURL(record.id)])
                            }
                        }.font(.callout)
                        HStack {
                            Button("重新转写") { model.reprocess(record.id, stage: .transcription) }
                            Button("重新整理") { model.reprocess(record.id, stage: .rewrite) }.disabled(
                                record.transcript == nil)
                            Spacer()
                            Button("移到废纸篓", role: .destructive) { model.trash(record.id) }
                        }.disabled(model.busy || model.recording)
                        Text("重试使用当前设置中的模型、热词和整理规则；每次结果单独保存。重新整理使用最近一次成功转写。")
                            .font(.caption).foregroundStyle(.secondary)
                        RunCard(title: "最新识别结果", run: record.transcriptions.last, audioDuration: record.duration)
                        RunCard(title: "最新整理结果", run: record.cleanups.last, audioDuration: nil)
                        if record.transcriptions.count > 1 || record.cleanups.count > 1 {
                            DisclosureGroup("查看之前的处理记录") {
                                VStack(spacing: 12) {
                                    ForEach(Array(record.transcriptions.dropLast().reversed())) { run in
                                        RunCard(title: "历史识别", run: run, audioDuration: record.duration)
                                    }
                                    ForEach(Array(record.cleanups.dropLast().reversed())) { run in
                                        RunCard(title: "历史整理", run: run, audioDuration: nil)
                                    }
                                }.padding(.top, 10)
                            }
                        }
                        Text("耗时按实际经过时间记录；RTF = 识别耗时 ÷ 音频时长，越低越快。Token 是处理用量，不等于硬件算力。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(18)
                }
            } else {
                ContentUnavailableView(
                    "选择一条历史", systemImage: "clock.arrow.circlepath", description: Text("播放原始音频、查看模型用量，或重新处理。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
