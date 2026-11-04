import Foundation

@MainActor final class TranscriptionService {
    private let permissions: PermissionModel
    private let apple = AppleSpeechRecognizer()
    init(permissions: PermissionModel) { self.permissions = permissions }

    func transcribe(_ audio: URL, prefs: Prefs, onRetry: () -> Void = {}) async throws -> String {
        switch prefs.engine {
        case "apple":
            guard await permissions.requestSpeechIfNeeded() == .authorized else {
                throw failure("请在系统设置中允许语音识别；录音已经保存")
            }
            return try await apple.transcribe(audio, prefs: prefs, onRetry: onRetry)
        case "whisper": return try await WhisperRecognizer.transcribe(audio, prefs: prefs)
        default: throw failure("不支持的识别引擎：" + prefs.engine)
        }
    }
    func cancel() { apple.cancel() }
}
