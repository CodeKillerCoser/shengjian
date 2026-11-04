import Foundation

// Records successful and failed attempts for both live dictation and history
// retries. It has no knowledge of views, panels or clipboard delivery.
@MainActor final class ProcessingService {
    private let transcription: TranscriptionService
    private let models: ModelClient
    private let history: HistoryLibrary

    init(transcription: TranscriptionService, models: ModelClient, history: HistoryLibrary) {
        self.transcription = transcription
        self.models = models
        self.history = history
    }
    func transcribe(
        _ audio: URL, prefs: Prefs, recordID: UUID,
        onRetry: () -> Void = {}
    ) async throws -> String {
        let start = ProcessInfo.processInfo.systemUptime
        let model =
            prefs.engine == "apple"
            ? "Apple 本地语音识别（系统未公开模型版本）" : URL(fileURLWithPath: prefs.modelPath).lastPathComponent
        do {
            let text = try await transcription.transcribe(audio, prefs: prefs, onRetry: onRetry)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw failure("未识别到文字，请检查麦克风音量或重新录音")
            }
            let service = prefs.engine == "apple" ? "Apple 设备端" : "Whisper.cpp · " + prefs.modelPath
            history.append(
                ProcessingRun(
                    model: model, service: service,
                    elapsed: ProcessInfo.processInfo.systemUptime - start, text: text, language: prefs.language),
                to: recordID, stage: .transcription)
            return text
        } catch {
            history.append(
                ProcessingRun(
                    model: model, service: prefs.engine,
                    elapsed: ProcessInfo.processInfo.systemUptime - start, text: "",
                    error: error.localizedDescription, language: prefs.language), to: recordID, stage: .transcription)
            throw error
        }
    }
    func rewrite(_ text: String, prefs: Prefs, key: String, recordID: UUID?) async throws -> String {
        let start = ProcessInfo.processInfo.systemUptime
        let service = URLComponents(string: prefs.endpoint)?.host ?? "未设置服务"
        do {
            let result = try await models.rewrite(text, prefs: prefs, key: key)
            if let recordID {
                history.append(
                    ProcessingRun(
                        model: result.model, service: service,
                        elapsed: ProcessInfo.processInfo.systemUptime - start, text: result.text,
                        inputText: text, usage: result.usage, modelReported: result.reported), to: recordID,
                    stage: .rewrite)
            }
            return result.text
        } catch {
            if let recordID {
                history.append(
                    ProcessingRun(
                        model: prefs.model, service: service,
                        elapsed: ProcessInfo.processInfo.systemUptime - start, text: "", inputText: text,
                        error: error.localizedDescription), to: recordID, stage: .rewrite)
            }
            throw error
        }
    }
}
