import Darwin
import Foundation

// Compiled with Domain, Application and Infrastructure only. Any dependency
// from those layers back into a screen or view model fails this build.
@main struct CoreChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let port = CommandLine.arguments[2]
        try await BreezeChecks.run(root: root, port: port)
        let store = PreferencesStore(directory: root.appendingPathComponent("core"))
        let defaults = store.load()
        precondition(defaults.copiesResult && defaults.shortcut == nil)
        let legacy = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(defaults))
        precondition(legacy.copiesResult && legacy.engine == "apple")
        var prefs = defaults
        prefs.engine = "whisper"
        prefs.whisper = root.appendingPathComponent("fake-whisper.py").path
        prefs.modelPath = root.appendingPathComponent("test-ggml.bin").path
        prefs.endpoint = "http://127.0.0.1:\(port)/v1"
        prefs.model = "requested-model"
        try store.save(prefs)
        precondition(store.load().model == prefs.model)
        let permissions = PermissionModel(
            actions: PermissionActions(
                microphoneStatus: { .denied }, speechStatus: { .authorized },
                requestMicrophone: { preconditionFailure("Unexpected microphone request") },
                requestSpeech: { preconditionFailure("Unexpected speech request") },
                openPane: { _ in preconditionFailure("Unexpected Settings navigation") },
                probeAccessibility: { nil }
            ))
        let historyStore = HistoryStore(root: store.directory.appendingPathComponent("History"))
        let library = HistoryLibrary(store: historyStore)
        let record = try library.archive(root.appendingPathComponent("core.wav"), duration: 2)
        precondition(FileManager.default.fileExists(atPath: library.audio(record.id).path))
        // The public speech API has no configuration argument. The same API
        // instance must pick up configuration changes inside its own module.
        let recognitionSettings = AppSettings(store: store)
        recognitionSettings.prefs.online = true
        recognitionSettings.prefs.prompt = "不要保留原文，全部改写"
        let recognitionTemporary = root.appendingPathComponent("speech-api-temporary")
        let speech = SpeechRecognitionService(
            settings: recognitionSettings, permissions: permissions,
            temporaryDirectory: recognitionTemporary)
        let heard = try await speech.recognize(library.audio(record.id))
        precondition(heard == "这是转写测试。")
        let otherEngine = root.appendingPathComponent("other-whisper.py")
        try Data(
            """
            #!/usr/bin/env python3
            import sys
            from pathlib import Path
            assert sys.argv[sys.argv.index('-l') + 1] == 'en'
            Path(sys.argv[sys.argv.index('-of') + 1] + '.txt').write_text('configured speech API result')
            """.utf8
        ).write(to: otherEngine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: otherEngine.path)
        recognitionSettings.prefs.whisper = otherEngine.path
        recognitionSettings.prefs.language = "en-US"
        let changed = try await speech.recognize(library.audio(record.id))
        precondition(changed == "configured speech API result")
        precondition(library.records.count == 1 && library.records[0].transcriptions.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: recognitionTemporary.path)
        precondition(leftovers.isEmpty)
        print(
            "PASS: standalone audio-to-text API, module-owned live configuration, no rewriting or history side effects")
        let client = ModelClient(savedKey: { "saved-key" }, hasSavedKey: { true })
        let processing = ProcessingService(
            transcription: TranscriptionService(permissions: permissions), models: client, history: library)
        let text = try await processing.transcribe(library.audio(record.id), prefs: prefs, recordID: record.id)
        precondition(text == "这是转写测试。")
        var invalid = prefs
        invalid.whisper = "/does-not-exist"
        do {
            _ = try await processing.transcribe(library.audio(record.id), prefs: invalid, recordID: record.id)
            preconditionFailure("Invalid recognizer must fail")
        } catch {}
        precondition(library.records[0].transcriptions.count == 2)
        precondition(library.records[0].transcriptions.last?.success == false)
        precondition(library.records[0].transcript?.text == text)
        let rewritten = try await processing.rewrite(text, prefs: prefs, key: "", recordID: record.id)
        precondition(rewritten == "这是整理结果。")
        let run = library.records[0].cleanups[0]
        precondition(run.inputText == text && run.model == "actual-test-model" && run.usage?.total == 20)
        var failed = prefs
        failed.model = "server-error"
        do {
            _ = try await processing.rewrite(text, prefs: failed, key: "", recordID: record.id)
            preconditionFailure("Server error must fail")
        } catch {}
        precondition(library.records[0].cleanups.count == 2 && library.records[0].cleanup?.success == true)
        let restored = HistoryLibrary(store: historyStore)
        precondition(restored.records[0].transcriptions.count == 2 && restored.records[0].cleanups.count == 2)
        let models = try await client.models(ModelDiscoveryInput(endpoint: "http://127.0.0.1:\(port)/auth/v1", key: ""))
        precondition(models == ["a", "z"])
        var authenticated = prefs
        authenticated.endpoint = "http://127.0.0.1:\(port)/auth/v1"
        let authenticatedResult = try await client.rewrite(text, prefs: authenticated, key: "")
        precondition(authenticatedResult.text == rewritten)

        // Cancelling the parent must stop the detached CLI worker and child.
        var slow = prefs
        slow.whisper = root.appendingPathComponent("slow-whisper.py").path
        let task = Task { try await WhisperRecognizer.transcribe(library.audio(record.id), prefs: slow) }
        let marker = library.audio(record.id).deletingPathExtension().appendingPathExtension("pid")
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: marker.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let pid = Int32(try String(contentsOf: marker).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw failure("Missing recognizer process ID")
        }
        task.cancel()
        do {
            _ = try await task.value
            preconditionFailure("Cancellation must reach the child worker")
        } catch is CancellationError {}
        for _ in 0..<100 {
            if kill(pid, 0) != 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(kill(pid, 0) != 0, "Cancelled recognizer process must terminate")
        precondition(FileManager.default.fileExists(atPath: library.audio(record.id).path))
        print(
            "PASS: UI-independent core, preferences compatibility, history persistence, processing failures, model authentication, recognizer cancellation"
        )
    }
}
