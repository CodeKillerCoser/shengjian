import Combine
import Foundation

@MainActor final class BreezeController: ObservableObject {
    @Published var text = "你好，欢迎使用声笺本地语音合成。"
    @Published var instruction = "一位声音清晰、语气自然亲切的中文讲述者。"
    @Published private(set) var status = "点击检查服务或启动服务"
    @Published private(set) var busy = false
    @Published private(set) var ready = false
    @Published private(set) var audioURL: URL?
    @Published private(set) var referenceURL: URL?
    @Published var referenceText = ""
    @Published private(set) var recognizingReference = false
    @Published private(set) var referenceStatus = ""
    private let service: BreezeService
    private let speechRecognition: SpeechRecognitionService
    private let activity: ActivityState
    private var activitySubscription: AnyCancellable?
    private var referenceTask: Task<Void, Never>?
    private var referenceRequest = UUID()
    private let playback = AudioPlayback()
    var root: URL? { service.root }

    var canRecognizeReference: Bool {
        referenceURL != nil && !busy && !recognizingReference && activity.idle
    }
    var canGenerate: Bool {
        !busy && !recognizingReference && ready && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (referenceURL == nil || !referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    init(
        service: BreezeService, speechRecognition: SpeechRecognitionService,
        activity: ActivityState
    ) {
        self.service = service
        self.speechRecognition = speechRecognition
        self.activity = activity
        activitySubscription = activity.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    func selectReference(_ url: URL?) {
        guard !busy else { return }
        cancelReferenceRecognition()
        referenceURL = url
        referenceText = ""
        referenceStatus = ""
    }
    func recognizeReference() {
        guard !busy, !recognizingReference, let referenceURL else { return }
        guard activity.idle else {
            referenceStatus = "请先结束录音或等待当前语音识别完成"
            return
        }
        let request = UUID()
        referenceRequest = request
        let previousText = referenceText
        recognizingReference = true
        activity.phase = .processing
        referenceStatus = "正在识别参考音频中的原话…"
        referenceTask = Task {
            defer {
                recognizingReference = false
                activity.phase = .idle
                referenceTask = nil
            }
            do {
                let result = try await speechRecognition.recognize(referenceURL)
                guard referenceRequest == request, self.referenceURL == referenceURL else { return }
                guard referenceText == previousText else {
                    referenceStatus = "文字已手动修改，已保留你的编辑"
                    return
                }
                referenceText = result
                referenceStatus = "识别完成，请核对是否与参考音频一致"
            } catch is CancellationError {} catch {
                guard referenceRequest == request else { return }
                referenceStatus = "语音识别失败：" + error.localizedDescription
            }
        }
    }
    func cancelReferenceRecognition() {
        referenceRequest = UUID()
        referenceTask?.cancel()
        speechRecognition.cancel()
        if recognizingReference { referenceStatus = "已取消识别，可手动填写文字" }
    }
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
        guard !busy, !recognizingReference, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
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
    func shutdown() {
        cancelReferenceRecognition()
        playback.stop()
    }
}
