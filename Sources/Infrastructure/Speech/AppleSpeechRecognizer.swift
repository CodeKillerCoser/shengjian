import AVFoundation
import Foundation
import Speech

@MainActor private final class SpeechCompletion {
    var continuation: CheckedContinuation<String, Error>?
    var timeout: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }
    func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }
}

@MainActor final class AppleSpeechRecognizer {
    private var speechTask: SFSpeechRecognitionTask?
    private var completion: SpeechCompletion?
    func cancel() {
        completion?.finish(.failure(CancellationError()))
        completion = nil
        speechTask?.cancel()
        speechTask = nil
    }
    func transcribe(_ url: URL, prefs: Prefs, onRetry: () -> Void = {}) async throws -> String {
        let prepared = try await Task.detached { try SpeechAudio.prepare(url) }.value
        do { return try await appleAttempt(url, prefs: prefs, buffer: nil) } catch {
            guard SpeechAudio.isNoSpeech(error) else { throw error }
            onRetry()
            do { return try await appleAttempt(url, prefs: prefs, buffer: prepared.buffer) } catch {
                guard SpeechAudio.isNoSpeech(error) else { throw error }
                throw failure(
                    "录音已保存（\(String(format: "%.1f", prepared.duration)) 秒），Apple 未识别出语音。请试听原始音频后重试，或切换 Whisper；这不代表没有采集到音频。"
                )
            }
        }
    }
    private func appleAttempt(_ url: URL, prefs: Prefs, buffer: AVAudioPCMBuffer?) async throws -> String {
        try Task.checkCancellation()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: prefs.language)),
            recognizer.supportsOnDeviceRecognition
        else { throw failure("本地识别不可用") }
        speechTask?.cancel()
        speechTask = nil
        let request: SFSpeechRecognitionRequest
        if buffer != nil {
            request = SFSpeechAudioBufferRecognitionRequest()
        } else {
            request = SFSpeechURLRecognitionRequest(url: url)
        }
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.shouldReportPartialResults = false
        request.contextualStrings = prefs.hotwords.components(separatedBy: .newlines).filter { !$0.isEmpty }
        defer {
            speechTask = nil
            completion = nil
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in
                let completion = SpeechCompletion(c)
                self.completion = completion
                let task = recognizer.recognitionTask(with: request) { result, error in
                    Task { @MainActor in
                        if let result, result.isFinal {
                            completion.finish(.success(result.bestTranscription.formattedString))
                        } else if let error {
                            completion.finish(.failure(error))
                        }
                    }
                }
                speechTask = task
                if let buffer, let stream = request as? SFSpeechAudioBufferRecognitionRequest {
                    stream.append(buffer)
                    stream.endAudio()
                }
                completion.timeout = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: 90_000_000_000) } catch { return }
                    completion.finish(.failure(failure("Apple 本地识别超时，请检查听写服务或改用 Whisper")))
                    task.cancel()
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }
}
