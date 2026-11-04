import Combine
import Foundation

@MainActor final class HistoryModel: ObservableObject {
    @Published private(set) var records: [TranscriptionRecord] = []
    @Published var selectedID: UUID?
    @Published var query = ""
    @Published private(set) var status = ""
    @Published private(set) var playingID: UUID?
    private let library: HistoryLibrary
    private let processing: ProcessingService
    private let settings: AppSettings
    private let activity: ActivityState
    private let playback: AudioPlayback
    private var task: Task<Void, Never>?
    private var activitySubscription: AnyCancellable?
    var busy: Bool { activity.busy }
    var recording: Bool { activity.recording }
    var filtered: [TranscriptionRecord] {
        guard !query.isEmpty else { return records }
        return records.filter { record in
            (record.transcriptions + record.cleanups).contains {
                $0.text.localizedCaseInsensitiveContains(query) || $0.model.localizedCaseInsensitiveContains(query)
            }
        }
    }
    var selected: TranscriptionRecord? { records.first { $0.id == selectedID } }

    init(
        library: HistoryLibrary, processing: ProcessingService, settings: AppSettings,
        activity: ActivityState, playback: AudioPlayback
    ) {
        self.library = library
        self.processing = processing
        self.settings = settings
        self.activity = activity
        self.playback = playback
        library.$records.assign(to: &$records)
        library.$status.assign(to: &$status)
        playback.$playingID.assign(to: &$playingID)
        activitySubscription = activity.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    func audioURL(_ id: UUID) -> URL { library.audio(id) }
    func play(_ id: UUID) {
        guard !recording else { return }
        do { try playback.play(library.audio(id), id: id) } catch { status = "播放失败：" + error.localizedDescription }
    }
    func reprocess(_ id: UUID, stage: ProcessingStage) {
        guard activity.idle, let record = library.record(id) else { return }
        if stage == .rewrite && record.transcript == nil { return }
        let prefs = settings.prefs
        let key = settings.key
        activity.phase = .processing
        status = stage == .rewrite ? "正在重新整理历史文字…" : "正在重新转写历史录音…"
        task = Task {
            defer { activity.phase = .idle }
            do {
                switch stage {
                case .transcription: _ = try await processing.transcribe(library.audio(id), prefs: prefs, recordID: id)
                case .rewrite:
                    if let text = record.transcript?.text {
                        _ = try await processing.rewrite(text, prefs: prefs, key: key, recordID: id)
                    }
                }
                status = "历史处理完成，新结果已保存"
            } catch is CancellationError {} catch { status = "历史处理失败：" + error.localizedDescription }
        }
    }
    func trash(_ id: UUID) {
        guard activity.idle else { return }
        do {
            if playingID == id { playback.stop() }
            try library.trash(id)
            if selectedID == id { selectedID = nil }
        } catch { status = "移到废纸篓失败：" + error.localizedDescription }
    }
    func prepareExit() {
        task?.cancel()
        playback.stop()
    }
}
