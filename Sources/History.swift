import Foundation

struct TokenUsage: Codable {
    var input: Int?
    var output: Int?
    var total: Int?
}
struct ProcessingRun: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var model: String
    var service: String
    var elapsed: Double
    var text: String
    var inputText: String? = nil
    var usage: TokenUsage? = nil
    var error: String? = nil
    var language: String? = nil
    var modelReported = false
    var success: Bool { error == nil }
}
struct TranscriptionRecord: Codable, Identifiable {
    var id: UUID
    var created: Date
    var duration: Double
    var transcriptions: [ProcessingRun] = []
    var cleanups: [ProcessingRun] = []
    var transcript: ProcessingRun? { transcriptions.last(where: { $0.success }) }
    var cleanup: ProcessingRun? { cleanups.last(where: { $0.success }) }
    var title: String {
        let text = transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "尚未完成转写" : String(text.prefix(48))
    }
}
struct PolishResult {
    var text: String
    var model: String
    var reported: Bool
    var usage: TokenUsage?
}
struct HistoryStore {
    let root: URL
    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func audio(_ id: UUID) -> URL { folder(id).appendingPathComponent("audio.wav") }
    func load() throws -> [TranscriptionRecord] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .map { try JSONDecoder().decode(TranscriptionRecord.self, from: Data(contentsOf: $0.appendingPathComponent("record.json"))) }
            .sorted { $0.created > $1.created }
    }
    func save(_ record: TranscriptionRecord) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: folder(record.id).appendingPathComponent("record.json"), options: .atomic)
    }
    func archive(_ source: URL, duration: Double) throws -> TranscriptionRecord {
        let record = TranscriptionRecord(id: UUID(), created: Date(), duration: duration)
        try FileManager.default.createDirectory(at: folder(record.id), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            try FileManager.default.copyItem(at: source, to: audio(record.id))
            try save(record)
            return record
        } catch {
            try? FileManager.default.removeItem(at: folder(record.id))
            throw error
        }
    }
}
