import Foundation

struct HistoryStore {
    let root: URL
    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func audio(_ id: UUID) -> URL { folder(id).appendingPathComponent("audio.wav") }
    func load() throws -> [TranscriptionRecord] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .map {
                try JSONDecoder().decode(
                    TranscriptionRecord.self, from: Data(contentsOf: $0.appendingPathComponent("record.json")))
            }
            .sorted { $0.created > $1.created }
    }
    func save(_ record: TranscriptionRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: folder(record.id).appendingPathComponent("record.json"), options: .atomic)
    }
    func trash(_ id: UUID) throws {
        try FileManager.default.trashItem(at: folder(id), resultingItemURL: nil)
    }
    func archive(_ source: URL, duration: Double) throws -> TranscriptionRecord {
        let record = TranscriptionRecord(id: UUID(), created: Date(), duration: duration)
        try FileManager.default.createDirectory(
            at: folder(record.id), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            try FileManager.default.copyItem(at: source, to: audio(record.id))
            try save(record)
            try? FileManager.default.removeItem(at: source)
            return record
        } catch {
            try? FileManager.default.removeItem(at: folder(record.id))
            throw error
        }
    }
}
