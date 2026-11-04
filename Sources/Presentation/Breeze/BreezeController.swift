import Combine
import Foundation

@MainActor final class BreezeController: ObservableObject {
    @Published var text = "你好，欢迎使用声笺本地语音合成。"
    @Published var instruction = "一位声音清晰、语气自然亲切的中文讲述者。"
    @Published private(set) var status = "点击检查服务或启动服务"
    @Published private(set) var busy = false
    @Published private(set) var ready = false
    @Published private(set) var audioURL: URL?
    @Published var referenceURL: URL?
    @Published var referenceText = ""
    private let service: BreezeService
    private let playback = AudioPlayback()
    var root: URL? { service.root }

    init(service: BreezeService) { self.service = service }
    func control(_ action: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            status = try await service.control(action)
            ready = false
        } catch { status = error.localizedDescription }
    }
    func check() async {
        do {
            ready = try await service.check()
            status = ready ? "本地服务就绪" : "服务正在加载或加载失败，请查看日志"
        } catch {
            ready = false
            status = "服务未连接，请先启动服务"
        }
    }
    func generate() async {
        guard !busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true
        audioURL = nil
        status = "正在合成…"
        defer { busy = false }
        do {
            let url = try await service.generate(
                text: text, instruction: instruction,
                referenceURL: referenceURL, referenceText: referenceText)
            audioURL = url
            try playback.play(url, id: UUID())
            status = "已生成并播放，音频已保存在 Breeze 目录"
        } catch { status = error.localizedDescription }
    }
    func replay() {
        guard let audioURL else { return }
        do { try playback.play(audioURL, id: UUID()) } catch { status = error.localizedDescription }
    }
    func stopPlayback() { playback.stop() }
}
