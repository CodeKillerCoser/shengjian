import SwiftUI
import AppKit
import AVFoundation

@MainActor final class BreezeController: ObservableObject {
    @Published var text = "你好，欢迎使用声笺本地语音合成。"
    @Published var instruction = "一位声音清晰、语气自然亲切的中文讲述者。"
    @Published var status = "点击检查服务或启动服务"
    @Published var busy = false
    @Published var ready = false
    @Published var audioURL: URL?
    @Published var referenceURL: URL?
    @Published var referenceText = ""
    var player: AVAudioPlayer?
    var root: URL? {
        let url = BreezeEnvironment.shared.directory
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("manage.py").path) ? url : nil
    }
    func control(_ action: String) {
        guard let root else { status = "未找到 Breeze 服务目录，请重新构建声笺"; return }
        do {
            let p = Process(); p.executableURL = root.appendingPathComponent("runtime/.venv/bin/python")
            p.arguments = [root.appendingPathComponent("manage.py").path, action]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            try p.run(); p.waitUntilExit()
            status = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "操作已完成"
            ready = false
        } catch { status = error.localizedDescription }
    }
    func check() async {
        do {
            let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:17860/health")!)
            ready = (response as? HTTPURLResponse)?.statusCode == 200
            status = ready ? "本地服务就绪" : "服务正在加载或加载失败，请查看日志"
        } catch { ready = false; status = "服务未连接，请先启动服务" }
    }
    func generate() async {
        guard let root else { status = "未找到服务目录"; return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; audioURL = nil; status = "正在合成…"; defer { busy = false }
        do {
            let boundary = UUID().uuidString
            var body = Data()
            func field(_ name: String, _ value: String) {
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
            }
            field("text", text); field("seed", "42")
            if !instruction.isEmpty { field("instruction", instruction); field("cfg_scale", "4") }
            if let referenceURL {
                guard !referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("请填写参考音频的准确文字稿") }
                let reference = try Data(contentsOf: referenceURL)
                guard reference.count <= 25 * 1024 * 1024 else { throw failure("参考音频不能超过 25 MB") }
                field("ref_text", referenceText)
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"ref_audio\"; filename=\"reference.\(referenceURL.pathExtension)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
                body.append(reference); body.append(Data("\r\n".utf8))
            }
            body.append(Data("--\(boundary)--\r\n".utf8))
            var request = URLRequest(url: URL(string: "http://127.0.0.1:17860/v1/audio/speech")!)
            request.httpMethod = "POST"; request.timeoutInterval = 600
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let (pcm, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw failure(String(data: pcm, encoding: .utf8) ?? "合成请求失败")
            }
            guard !pcm.isEmpty, pcm.count % 2 == 0 else { throw failure("服务返回了无效音频") }
            var wav = Data()
            func ascii(_ s: String) { wav.append(Data(s.utf8)) }
            func u32(_ x: UInt32) { var v = x.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
            func u16(_ x: UInt16) { var v = x.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
            ascii("RIFF"); u32(UInt32(pcm.count + 36)); ascii("WAVEfmt "); u32(16)
            u16(1); u16(1); u32(24000); u32(48000); u16(2); u16(16); ascii("data"); u32(UInt32(pcm.count)); wav.append(pcm)
            let folder = root.appendingPathComponent("audio")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("声笺-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).wav")
            try wav.write(to: url, options: .atomic); audioURL = url
            player = try AVAudioPlayer(contentsOf: url); player?.play()
            status = "已生成并播放，音频已保存在 Breeze 目录"
        } catch { status = error.localizedDescription }
    }
}

struct BreezeView: View {
    @ObservedObject var voice: Voice
    @StateObject private var model = BreezeController()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Breeze · 本地语音合成", systemImage: "speaker.wave.2.fill").font(.headline)
                    Spacer()
                    Button("启动服务") { model.control("start") }.disabled(model.busy)
                    Button("检查连接") { Task { await model.check() } }
                    Button("停止服务") { model.control("stop") }.disabled(model.busy)
                }
                Text(model.status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Editor(title: "要朗读的文字", text: $model.text).frame(height: 150)
                HStack {
                    Button("使用转写原文") { model.text = voice.raw }.disabled(voice.raw.isEmpty)
                    Button("使用改写结果") { model.text = voice.output }.disabled(voice.output.isEmpty)
                }
                TextField("音色与语气描述（克隆时留空可保留原音风格）", text: $model.instruction)
                    .textFieldStyle(.roundedBorder)
                DisclosureGroup("声音克隆（可选）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("使用不超过 30 秒的清晰人声，支持 WAV、FLAC、OGG，并填写完全匹配的文字稿。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("选择参考音频") {
                                let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK { model.referenceURL = panel.url }
                            }
                            Text(model.referenceURL?.lastPathComponent ?? "未选择").lineLimit(1)
                            if model.referenceURL != nil { Button("清除") { model.referenceURL = nil; model.referenceText = "" } }
                        }
                        TextField("参考音频的准确文字稿", text: $model.referenceText).textFieldStyle(.roundedBorder)
                    }.padding(.top, 6)
                }
                HStack {
                    Button(model.busy ? "合成中…" : "生成并播放") { Task { await model.generate() } }
                        .buttonStyle(.borderedProminent).tint(.teal)
                        .disabled(model.busy || !model.ready || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if model.busy { ProgressView().controlSize(.small) }
                    if let url = model.audioURL {
                        Button("再次播放") { model.player?.currentTime = 0; model.player?.play() }
                        Button("停止播放") { model.player?.stop() }
                        Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Spacer()
                    Button("查看日志") {
                        if let root = model.root { NSWorkspace.shared.open(root.appendingPathComponent("logs/service.log")) }
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
