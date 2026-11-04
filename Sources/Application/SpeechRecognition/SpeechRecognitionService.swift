import Foundation

// Audio-to-text API for callers outside the recognition module. Configuration,
// engine selection, permissions and safe input copies stay inside this module.
// This API does not archive, rewrite, copy or deliver the recognized text.
@MainActor final class SpeechRecognitionService {
    private let transcription: TranscriptionService
    private let settings: AppSettings
    private let temporaryDirectory: URL

    init(settings: AppSettings, permissions: PermissionModel, temporaryDirectory: URL) {
        self.settings = settings
        transcription = TranscriptionService(permissions: permissions)
        self.temporaryDirectory = temporaryDirectory
    }
    func recognize(_ source: URL) async throws -> String {
        try Task.checkCancellation()
        let prefs = settings.prefs
        let workspace = temporaryDirectory.appendingPathComponent("recognition-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let copy = workspace.appendingPathComponent("audio").appendingPathExtension(source.pathExtension)
        try FileManager.default.copyItem(at: source, to: copy)
        try Task.checkCancellation()
        let text = try await transcription.transcribe(copy, prefs: prefs)
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw failure("未识别到语音")
        }
        return text
    }
    func cancel() { transcription.cancel() }
}
