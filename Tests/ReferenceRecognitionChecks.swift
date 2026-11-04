import Darwin
import Foundation

enum ReferenceRecognitionChecks {
    @MainActor private static func wait(_ model: BreezeController) async throws {
        for _ in 0..<300 {
            if !model.recognizingReference { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw failure("Reference recognition timed out")
    }

    @MainActor static func run(root: URL, port: String) async throws {
        let fm = FileManager.default
        let fixture = FeatureFixture(directory: root.appendingPathComponent("reference-feature"))
        let scratch = root.appendingPathComponent("reference-temporary")
        let serviceDirectory = root.appendingPathComponent("reference-service")
        try fm.createDirectory(at: serviceDirectory, withIntermediateDirectories: true)
        try Data().write(to: serviceDirectory.appendingPathComponent("manage.py"))
        let service = BreezeService(directory: serviceDirectory, baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        let model = BreezeController(
            service: service,
            speechRecognition: SpeechRecognitionService(
                settings: fixture.settings, permissions: fixture.permissions,
                temporaryDirectory: scratch), activity: fixture.activity)
        let source = root.appendingPathComponent("reference.wav")
        let original = try Data(contentsOf: source)
        let adjacentText = source.deletingPathExtension().appendingPathExtension("txt")
        let adjacentLog = source.deletingPathExtension().appendingPathExtension("log")
        try Data("user transcript".utf8).write(to: adjacentText)
        try Data("user log".utf8).write(to: adjacentLog)
        let executable = root.appendingPathComponent("reference-whisper.py")
        let verbatim = "嗯，我我今天去上海，啊。"
        try Data(
            """
            #!/usr/bin/env python3
            import sys
            from pathlib import Path
            base = sys.argv[sys.argv.index('-of') + 1]
            Path(base + '.txt').write_text('\(verbatim)')
            with Path(__file__).with_suffix('.calls').open('a') as calls:
                calls.write('called\\n')
            """.utf8
        ).write(to: executable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        fixture.settings.prefs.engine = "whisper"
        fixture.settings.prefs.whisper = executable.path
        fixture.settings.prefs.online = true
        fixture.settings.prefs.prompt = "把内容全部改写为其他文字"
        fixture.settings.prefs.endpoint = "http://127.0.0.1:\(port)/must-not-rewrite"
        fixture.settings.prefs.model = "must-not-rewrite"
        await model.check()
        model.selectReference(source)
        precondition(model.canRecognizeReference && !model.canGenerate)
        model.recognizeReference()
        model.recognizeReference()  // Duplicate gestures must not start another CLI.
        precondition(model.recognizingReference && fixture.activity.busy && !model.canGenerate)
        try await wait(model)
        let calls = try String(contentsOf: executable.deletingPathExtension().appendingPathExtension("calls"))
        precondition(calls == "called\n")
        precondition(model.referenceText == verbatim && model.canGenerate)
        precondition(fixture.activity.idle && fixture.library.records.isEmpty)
        let sourceAfter = try Data(contentsOf: source)
        let adjacentTextAfter = try String(contentsOf: adjacentText)
        let adjacentLogAfter = try String(contentsOf: adjacentLog)
        let scratchAfter = try fm.contentsOfDirectory(atPath: scratch.path)
        precondition(
            sourceAfter == original && adjacentTextAfter == "user transcript" && adjacentLogAfter == "user log")
        precondition(scratchAfter.isEmpty)
        // Send the recognized original words, not an AI rewrite, as ref_text.
        _ = try await service.generate(
            text: "合成测试", instruction: "清晰", referenceURL: source,
            referenceText: model.referenceText)

        model.selectReference(source)
        precondition(model.referenceText.isEmpty)
        model.recognizeReference()
        model.referenceText = "我手动校对的原话"
        try await wait(model)
        precondition(model.referenceText == "我手动校对的原话" && model.referenceStatus.contains("保留你的编辑"))
        fixture.settings.prefs.whisper = "/does-not-exist"
        model.recognizeReference()
        try await wait(model)
        precondition(model.referenceStatus.hasPrefix("语音识别失败") && model.referenceText == "我手动校对的原话")
        precondition(fixture.activity.idle)

        fixture.activity.phase = .recording
        precondition(!model.canRecognizeReference)
        model.recognizeReference()
        precondition(!model.recognizingReference && fixture.activity.recording)
        fixture.activity.phase = .idle
        fixture.settings.prefs.whisper = root.appendingPathComponent("slow-whisper.py").path
        model.recognizeReference()
        var workerPID: Int32?
        for _ in 0..<200 {
            for directory in (try? fm.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)) ?? [] {
                let marker = directory.appendingPathComponent("audio.pid")
                if let text = try? String(contentsOf: marker) { workerPID = Int32(text) }
            }
            if workerPID != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let workerPID else { throw failure("Reference worker did not start") }
        let replacement = root.appendingPathComponent("other-reference.wav")
        try original.write(to: replacement)
        model.selectReference(replacement)
        try await wait(model)
        precondition(model.referenceURL == replacement && model.referenceText.isEmpty && model.referenceStatus.isEmpty)
        let scratchAfterCancel = try fm.contentsOfDirectory(atPath: scratch.path)
        precondition(fixture.activity.idle && scratchAfterCancel.isEmpty)
        for _ in 0..<100 {
            if kill(workerPID, 0) != 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(kill(workerPID, 0) != 0)
        model.selectReference(nil)
        precondition(model.referenceURL == nil && !model.canRecognizeReference)
        model.shutdown()
        print(
            "PASS: optional reference speech-to-text, verbatim ref_text delivery, source preservation, edit protection, failures, cancellation and activity exclusion"
        )
    }
}
