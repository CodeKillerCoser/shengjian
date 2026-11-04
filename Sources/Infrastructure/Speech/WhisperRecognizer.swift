import Foundation

enum WhisperRecognizer {
    static func transcribe(_ url: URL, prefs: Prefs) async throws -> String {
        let worker = Task.detached {
            try Task.checkCancellation()
            let base = url.deletingPathExtension().path
            let logURL = URL(fileURLWithPath: base + ".log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            defer {
                try? log.close()
                try? FileManager.default.removeItem(at: logURL)
                try? FileManager.default.removeItem(atPath: base + ".txt")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: prefs.whisper)
            process.arguments = [
                "-m", prefs.modelPath, "-f", url.path, "-l", prefs.language == "en-US" ? "en" : "zh", "-otxt", "-of",
                base, "--prompt", prefs.hotwords.replacingOccurrences(of: "\n", with: ", "),
            ]
            process.standardOutput = log
            process.standardError = log
            try process.run()
            defer { if process.isRunning { process.terminate() } }
            let deadline = Date().addingTimeInterval(180)
            while process.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
            if process.isRunning {
                process.terminate()
                throw failure("Whisper 识别超时，请检查模型或缩短录音")
            }
            guard process.terminationStatus == 0, let text = try? String(contentsOfFile: base + ".txt", encoding: .utf8)
            else { throw failure("Whisper 识别失败，请检查模型和程序版本") }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
