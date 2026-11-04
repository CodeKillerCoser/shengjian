import Combine
import Foundation

enum RecordingOverlayPhase { case recording, processing, success, error }

@MainActor final class DictationModel: ObservableObject {
    @Published var raw = ""
    @Published var output = ""
    @Published private(set) var transcriptReady = false
    @Published private(set) var rewriteReady = false
    @Published private(set) var status = "就绪"
    @Published private(set) var hasRetryAudio = false
    @Published private(set) var showSpeechHelp = false
    @Published private(set) var technicalError = ""
    @Published private(set) var overlayVisible = false
    @Published private(set) var overlayPhase: RecordingOverlayPhase = .recording
    @Published private(set) var overlayMessage = ""
    private(set) var overlaySession = UUID()
    @Published private(set) var currentRecordID: UUID?
    private var pendingAudio: RecordedAudio?
    private var preparation = UUID()
    private var task: Task<Void, Never>?
    private var activitySubscription: AnyCancellable?
    private var historySubscription: AnyCancellable?
    private let settings: AppSettings
    private let activity: ActivityState
    private let permissions: PermissionModel
    private let inputs: AudioInputMonitor
    private let recorder: AudioRecorder
    private let playback: AudioPlayback
    private let history: HistoryLibrary
    private let processing: ProcessingService
    private let delivery: TextDelivery?

    var recording: Bool { activity.recording }
    var busy: Bool { activity.busy }
    var shouldAutoInsert: Bool { delivery?.cancelled != true && settings.prefs.autoInsert }
    var shouldAutoCopy: Bool { delivery?.cancelled != true && settings.prefs.copiesResult }

    init(
        settings: AppSettings, activity: ActivityState, permissions: PermissionModel,
        inputs: AudioInputMonitor, recorder: AudioRecorder, playback: AudioPlayback,
        history: HistoryLibrary, processing: ProcessingService, delivery: TextDelivery?
    ) {
        self.settings = settings
        self.activity = activity
        self.permissions = permissions
        self.inputs = inputs
        self.recorder = recorder
        self.playback = playback
        self.history = history
        self.processing = processing
        self.delivery = delivery
        activitySubscription = activity.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        historySubscription = history.$records.sink { [weak self] records in
            guard let self, let id = currentRecordID, !records.contains(where: { $0.id == id }) else { return }
            currentRecordID = nil
            hasRetryAudio = false
        }
        recorder.onDurationLimit = { [weak self] in self?.stop() }
    }
    func prepareCapture(reset: Bool = false) {
        guard !recording else { return }
        permissions.refreshMediaPermissions()
        // Check silently; only an explicit user action may request access.
        guard inputs.hasInput, permissions.microphone == .authorized else {
            recorder.clearPrepared()
            return
        }
        recorder.prepare(reset: reset)
    }
    func toggle() {
        guard !busy else { return }
        if recording { stop() } else { task = Task { await start() } }
    }
    func start(fromHold: Bool = false, isHeld: () -> Bool = { true }) async {
        guard activity.idle else { return }
        guard inputs.hasInput else {
            status = AudioInputMonitor.missingMessage
            return
        }
        let triggeredAt = ProcessInfo.processInfo.systemUptime
        let request = UUID()
        preparation = request
        activity.phase = .preparingRecording
        defer { if preparation == request && activity.phase == .preparingRecording { activity.phase = .idle } }
        delivery?.begin()
        overlaySession = UUID()
        do {
            playback.stop()
            let granted = await permissions.requestMicrophoneIfNeeded()
            guard preparation == request, !Task.isCancelled else { return }
            guard granted else { throw failure("请在系统设置 → 隐私与安全性 → 麦克风中允许声笺") }
            if fromHold && !isHeld() {
                status = "准备完成，请重新按住快捷键说话"
                return
            }
            try recorder.start(triggeredAt: triggeredAt)
            pendingAudio = nil
            currentRecordID = nil
            hasRetryAudio = false
            showSpeechHelp = false
            technicalError = ""
            raw = ""
            output = ""
            transcriptReady = false
            rewriteReady = false
            activity.phase = .recording
            overlayPhase = .recording
            overlayMessage = ""
            overlayVisible = delivery?.backgroundSession == true
            status = fromHold ? "正在本地录音 · 松开快捷键结束" : "正在本地录音 · 点击停止或再次按快捷键"
            // Start capture before potentially slow cross-process AX calls.
            if delivery?.backgroundSession == true {
                let session = overlaySession
                Task { @MainActor [weak self] in
                    guard let self, recording, overlaySession == session else { return }
                    delivery?.captureFocusedElement()
                }
            }
        } catch {
            status = error.localizedDescription
            showOverlayError(status)
        }
    }
    func stop() {
        guard recording else { return }
        let audio = recorder.stop()
        activity.phase = .idle
        if let audio { process(audio) }
        prepareCapture()
    }
    func process(_ audio: RecordedAudio) {
        guard activity.idle else { return }
        pendingAudio = audio
        currentRecordID = nil
        recognizeRecording()
    }
    private func archivePendingAudio() throws {
        guard let audio = pendingAudio else { return }
        let record = try history.archive(audio.url, duration: audio.duration)
        currentRecordID = record.id
        pendingAudio = nil
    }
    func recognizeRecording() {
        guard activity.idle else { return }
        do { try archivePendingAudio() } catch {
            status = "录音已保留，但历史保存失败：" + error.localizedDescription
            hasRetryAudio = true
            showOverlayError(status)
            return
        }
        guard let id = currentRecordID, history.record(id) != nil else { return }
        transcriptReady = false
        rewriteReady = false
        activity.phase = .processing
        overlayPhase = .processing
        status = "本地识别中…"
        showSpeechHelp = false
        technicalError = ""
        let prefs = settings.prefs
        let key = settings.key
        task = Task {
            defer { activity.phase = .idle }
            do {
                let text = try await processing.transcribe(history.audio(id), prefs: prefs, recordID: id) {
                    self.status = "音频已录制，正在以音频缓冲模式重试本地识别…"
                }
                try Task.checkCancellation()
                raw = text
                output = text
                transcriptReady = true
                hasRetryAudio = false
                if prefs.online {
                    status = "正在发送转写文字进行整理…"
                    do {
                        output = try await processing.rewrite(text, prefs: prefs, key: key, recordID: id)
                        rewriteReady = true
                    } catch {
                        status = "本地识别已完成，在线整理失败；原文已保留。"
                        technicalError = error.localizedDescription
                        showOverlayError(status)
                        return
                    }
                }
                status = "完成 · 可编辑后复制或输入"
                await deliverResult(prefs: prefs)
            } catch is CancellationError {} catch {
                hasRetryAudio = true
                technicalError =
                    "\((error as NSError).domain) / \((error as NSError).code): " + error.localizedDescription
                let message = error.localizedDescription.lowercased()
                showSpeechHelp = prefs.engine == "apple"
                status =
                    prefs.engine == "apple"
                        && (message.contains("siri") || message.contains("dictation") || message.contains("disabled"))
                    ? "Apple 系统听写服务未启用，录音已完成但未能识别。" : "本地识别失败：" + error.localizedDescription
                showOverlayError(status)
            }
        }
    }
    private func deliverResult(prefs: Prefs) async {
        guard let delivery, !delivery.cancelled else { return }
        if prefs.copiesResult {
            delivery.copy(output)
            status = "已复制结果"
        }
        if prefs.autoInsert {
            overlayVisible = false
            if let result = await delivery.insert(output, preserveClipboard: !prefs.copiesResult) { feedback(result) }
        } else if delivery.backgroundSession {
            feedback(DeliveryResult(message: prefs.copiesResult ? "已复制结果" : "转写完成，已保存到历史", success: true))
        }
    }
    func discardRecording() {
        guard activity.idle else { return }
        if let pendingAudio { recorder.discard(pendingAudio) }
        pendingAudio = nil
        hasRetryAudio = false
        showSpeechHelp = false
        technicalError = ""
        status = "已关闭重试提示；录音保留在转写历史中"
    }
    func closeOverlay() {
        delivery?.cancel()
        preparation = UUID()
        overlaySession = UUID()
        if recording {
            recorder.cancel()
            activity.phase = .idle
            pendingAudio = nil
            hasRetryAudio = false
            status = "已取消录音"
        } else if activity.phase == .preparingRecording {
            activity.phase = .idle
            status = "已取消录音"
        } else if busy {
            status = "已取消自动输入；处理完成后仍保存到历史"
        }
        overlayVisible = false
    }
    func hideOverlay() { overlayVisible = false }
    private func showOverlayError(_ message: String) {
        guard delivery?.backgroundSession == true, delivery?.cancelled == false else { return }
        overlayPhase = .error
        overlayMessage = message
        overlayVisible = true
    }
    private func feedback(_ result: DeliveryResult) {
        status = result.message
        guard delivery?.backgroundSession == true, delivery?.cancelled == false else { return }
        overlayPhase = result.success ? .success : .error
        overlayMessage = result.message
        overlayVisible = true
        if result.success {
            let session = overlaySession
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                guard let self, overlaySession == session else { return }
                overlayVisible = false
            }
        }
    }
    func prepareExit() {
        preparation = UUID()
        delivery?.cancel()
        task?.cancel()
        overlayVisible = false
        if recording, let audio = recorder.stop() {
            pendingAudio = audio
            try? archivePendingAudio()
        }
        recorder.clearPrepared()
        activity.phase = .idle
    }
    func showOverlayPreview() {
        activity.phase = .recording
        overlaySession = UUID()
        overlayPhase = .recording
        overlayMessage = "界面预览 · 未访问麦克风"
        status = "悬浮条界面预览，不会录音或发送数据"
        overlayVisible = true
    }
}
