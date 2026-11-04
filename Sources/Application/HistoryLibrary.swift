import Combine
import Foundation

// Shared history data and persistence. Search, selection and playback belong
// to the history screen, rather than the recording session.
@MainActor final class HistoryLibrary: ObservableObject {
    @Published private(set) var records: [TranscriptionRecord] = []
    @Published private(set) var status = ""
    private let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store
        do { records = try store.load() } catch { status = "读取历史失败，原文件保留：" + error.localizedDescription }
    }
    func audio(_ id: UUID) -> URL { store.audio(id) }
    func record(_ id: UUID) -> TranscriptionRecord? { records.first { $0.id == id } }
    func archive(_ source: URL, duration: Double) throws -> TranscriptionRecord {
        let record = try store.archive(source, duration: duration)
        records.insert(record, at: 0)
        return record
    }
    func append(_ run: ProcessingRun, to id: UUID, stage: ProcessingStage) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        switch stage {
        case .transcription: records[index].transcriptions.append(run)
        case .rewrite: records[index].cleanups.append(run)
        }
        do {
            try store.save(records[index])
            status = "历史已保存在本机"
        } catch { status = "历史写入失败，当前结果仍在内存：" + error.localizedDescription }
    }
    func trash(_ id: UUID) throws {
        try store.trash(id)
        records.removeAll { $0.id == id }
        status = "已移到废纸篓，可从 Finder 恢复"
    }
}
