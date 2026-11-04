import AVFoundation
import Combine

@MainActor final class AudioRecorder: ObservableObject {
    @Published private(set) var levels = Array(repeating: Float(0), count: 72)
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var meterDB: Float = -160
    @Published private(set) var captureStartMilliseconds: Double = 0
    var onDurationLimit: (() -> Void)?
    private var recorder: AVAudioRecorder?
    private var prepared: AVAudioRecorder?
    private var timer: Timer?
    private let temporaryDirectory: URL

    init(temporaryDirectory: URL = AppStorage.root.appendingPathComponent("Temporary", isDirectory: true)) {
        self.temporaryDirectory = temporaryDirectory
    }

    private func makeRecorder() throws -> AVAudioRecorder {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let url = temporaryDirectory.appendingPathComponent("rimevoice-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord() else {
            try? FileManager.default.removeItem(at: url)
            throw failure("无法准备音频采集，请检查输入设备")
        }
        return recorder
    }
    func prepare(reset: Bool = false) {
        guard recorder == nil else { return }
        if reset { clearPrepared() }
        if prepared == nil { prepared = try? makeRecorder() }
    }
    func start(triggeredAt: TimeInterval) throws {
        let next = try prepared ?? makeRecorder()
        prepared = nil
        guard next.record() else {
            try? FileManager.default.removeItem(at: next.url)
            throw failure("无法启动录音，请检查麦克风")
        }
        recorder = next
        elapsed = 0
        levels = Array(repeating: 0, count: 72)
        meterDB = -160
        captureStartMilliseconds = (ProcessInfo.processInfo.systemUptime - triggeredAt) * 1000
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMeter() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stop() -> RecordedAudio? {
        timer?.invalidate()
        timer = nil
        guard let recorder else { return nil }
        elapsed = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        return RecordedAudio(url: recorder.url, duration: elapsed)
    }
    func cancel() {
        if let audio = stop() { discard(audio) }
        levels = Array(repeating: 0, count: 72)
    }
    func discard(_ audio: RecordedAudio) { try? FileManager.default.removeItem(at: audio.url) }
    func clearPrepared() {
        if let prepared {
            prepared.stop()
            try? FileManager.default.removeItem(at: prepared.url)
        }
        prepared = nil
    }
    private func updateMeter() {
        guard let recorder else { return }
        recorder.updateMeters()
        meterDB = recorder.averagePower(forChannel: 0)
        elapsed = recorder.currentTime
        levels.removeFirst()
        levels.append(max(0, min(1, (meterDB + 55) / 55)))
        if elapsed >= 120 { onDurationLimit?() }
    }
    deinit { timer?.invalidate() }
}
