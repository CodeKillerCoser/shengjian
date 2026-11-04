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

enum ProcessingStage { case transcription, rewrite }

struct RecordedAudio {
    let url: URL
    let duration: TimeInterval
}
