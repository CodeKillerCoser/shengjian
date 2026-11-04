import AVFoundation
import AppKit
import Foundation

@main struct HistoryChecks {
    @MainActor static func wait(_ voice: DictationModel) async throws {
        for _ in 0..<300 {
            if !voice.busy { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw failure("Test timed out")
    }
    @MainActor static func main() async throws {
        await PermissionChecks.run()
        for (endpoint, expected) in [
            ("http://localhost:11234/v1", "http://localhost:11234/v1/models"),
            ("https://example.com", "https://example.com/v1/models"),
            ("https://example.com/api/v1/chat/completions", "https://example.com/api/v1/models"),
            ("https://example.com/v1/models/", "https://example.com/v1/models"),
        ] {
            let url = try ModelServiceAddress.modelsURL(endpoint)
            precondition(url.absoluteString == expected)
        }
        do {
            _ = try ModelServiceAddress.modelsURL("http://example.com/v1")
            preconditionFailure("Remote plaintext model discovery must be rejected")
        } catch {}
        let list = try ModelServiceAddress.modelIDs(
            from: Data(#"{"data":[{"id":"z"},{"id":"a"},{"id":"z"},{"id":""}]}"#.utf8))
        precondition(list == ["a", "z"])
        var availableInput = false
        var probes = 0
        let inputMonitor = AudioInputMonitor(
            probe: {
                probes += 1
                return availableInput
            }, subscribe: false)
        precondition(!inputMonitor.hasInput && probes == 1)
        availableInput = true
        inputMonitor.deviceConfigurationChanged()
        precondition(inputMonitor.hasInput && probes == 2)
        availableInput = false
        inputMonitor.deviceConfigurationChanged()
        precondition(!inputMonitor.hasInput && probes == 3)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixture = FeatureFixture(directory: root.appendingPathComponent("data"))
        let voice = fixture.dictation
        fixture.settings.prefs.copyAfterTranscription = false
        fixture.settings.prefs.engine = "whisper"
        fixture.settings.prefs.whisper = root.appendingPathComponent("fake-whisper.py").path
        fixture.settings.prefs.modelPath = root.appendingPathComponent("test-ggml.bin").path
        fixture.settings.prefs.online = false
        let audioURL = root.appendingPathComponent("sample.wav")
        let originalAudio = try Data(contentsOf: audioURL)
        let prepared = try SpeechAudio.prepare(audioURL)
        precondition(abs(prepared.duration - 2) < 0.01)
        precondition(prepared.buffer.frameLength == 38400)
        let unchangedAudio = try Data(contentsOf: audioURL)
        precondition(unchangedAudio == originalAudio)
        precondition(SpeechAudio.isNoSpeech(NSError(domain: "kAFAssistantErrorDomain", code: 1110)))
        precondition(!SpeechAudio.isNoSpeech(NSError(domain: "test", code: 123)))
        precondition(!voice.transcriptReady && !voice.rewriteReady)
        voice.process(RecordedAudio(url: audioURL, duration: 2))
        // A history retry and shortcut edit cannot enter an active session.
        fixture.history.reprocess(voice.currentRecordID!, stage: .transcription)
        fixture.shortcuts.beginCapture()
        precondition(!fixture.shortcuts.capturing)
        try await wait(voice)
        precondition(fixture.library.records.count == 1)
        let id = fixture.library.records[0].id
        precondition(voice.raw == "这是转写测试。")
        precondition(voice.transcriptReady && !voice.rewriteReady)
        precondition(fixture.library.records[0].transcriptions.count == 1)
        fixture.history.query = "这是转写"
        precondition(fixture.history.filtered.count == 1)
        fixture.history.query = "no-match"
        precondition(fixture.history.filtered.isEmpty)
        fixture.history.query = ""
        let dictationStatus = voice.status
        fixture.settings.save()
        precondition(voice.status == dictationStatus && fixture.settings.status == "设置已保存")
        precondition(FileManager.default.fileExists(atPath: fixture.library.audio(id).path))
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("sample.wav").path))
        let player = try AVAudioPlayer(contentsOf: fixture.library.audio(id))
        precondition(abs(player.duration - 2) < 0.1)
        precondition(fixture.library.records[0].transcriptions[0].elapsed > 0)
        precondition(fixture.library.records[0].transcriptions[0].model == "test-ggml.bin")

        fixture.history.reprocess(id, stage: .transcription)
        try await wait(voice)
        precondition(fixture.library.records[0].transcriptions.count == 2)
        fixture.settings.prefs.whisper = "/does-not-exist"
        fixture.history.reprocess(id, stage: .transcription)
        try await wait(voice)
        precondition(fixture.library.records[0].transcriptions.count == 3)
        precondition(fixture.library.records[0].transcriptions.last?.error != nil)
        precondition(fixture.library.records[0].transcript?.text == "这是转写测试。")
        precondition(FileManager.default.fileExists(atPath: fixture.library.audio(id).path))

        fixture.settings.prefs.endpoint = "http://127.0.0.1:" + CommandLine.arguments[2] + "/v1"
        fixture.settings.prefs.model = "requested-model"
        fixture.history.reprocess(id, stage: .rewrite)
        try await wait(voice)
        let first = fixture.library.records[0].cleanups[0]
        precondition(first.text == "这是整理结果。")
        precondition(first.model == "actual-test-model" && first.modelReported)
        precondition(first.usage?.input == 12 && first.usage?.output == 8 && first.usage?.total == 20)
        precondition(first.inputText == "这是转写测试。")
        fixture.settings.prefs.model = "no-usage"
        fixture.history.reprocess(id, stage: .rewrite)
        try await wait(voice)
        precondition(fixture.library.records[0].cleanups.count == 2)
        precondition(fixture.library.records[0].cleanups.last?.usage == nil)
        fixture.settings.prefs.model = "server-error"
        fixture.history.reprocess(id, stage: .rewrite)
        try await wait(voice)
        precondition(fixture.library.records[0].cleanups.count == 3)
        precondition(fixture.library.records[0].cleanups.last?.error != nil)
        precondition(fixture.library.records[0].cleanup?.success == true)
        // Output options apply equally to background and foreground sessions.
        fixture.settings.prefs.copyAfterTranscription = true
        fixture.settings.prefs.autoInsert = false
        precondition(!voice.shouldAutoInsert && voice.shouldAutoCopy)
        fixture.settings.prefs.autoInsert = true
        precondition(voice.shouldAutoInsert)
        fixture.settings.prefs.copyAfterTranscription = false
        precondition(!voice.shouldAutoCopy && voice.shouldAutoInsert)
        let session = voice.overlaySession
        fixture.activity.phase = .processing
        voice.closeOverlay()
        precondition(!voice.shouldAutoInsert && voice.overlaySession != session)
        fixture.activity.phase = .idle
        // Cancellation changes only the current session, never archived audio.
        fixture.activity.phase = .recording
        voice.closeOverlay()
        precondition(!voice.recording && fixture.library.records.count == 1)
        precondition(FileManager.default.fileExists(atPath: fixture.library.audio(id).path))
        fixture.delivery.begin()
        fixture.settings.prefs.autoInsert = false
        precondition(!voice.shouldAutoInsert)
        fixture.settings.prefs.autoInsert = true
        precondition(voice.shouldAutoInsert)
        // Clipboard restoration preserves rich data and does not overwrite a
        // new clipboard change made while paste delivery was in flight.
        let clipboard = NSPasteboard.withUniqueName()
        clipboard.setString("before", forType: .string)
        let snapshot = ClipboardSnapshot(pasteboard: clipboard)
        clipboard.clearContents()
        clipboard.setString("temporary result", forType: .string)
        snapshot.restore(ifUnchanged: clipboard.changeCount, pasteboard: clipboard)
        precondition(clipboard.string(forType: .string) == "before")
        clipboard.clearContents()
        clipboard.setString("temporary result", forType: .string)
        let written = clipboard.changeCount
        clipboard.clearContents()
        clipboard.setString("new user copy", forType: .string)
        snapshot.restore(ifUnchanged: written, pasteboard: clipboard)
        precondition(clipboard.string(forType: .string) == "new user copy")
        clipboard.releaseGlobally()
        _ = NSApplication.shared
        let overlay = RecordingOverlay(model: voice, recorder: fixture.recorder, openMainWindow: {})
        overlay.show(on: NSScreen.main)
        precondition(overlay.panel.isVisible)
        precondition(
            overlay.panel.frame.width == OverlayGeometry.width && overlay.panel.frame.height == OverlayGeometry.height)
        precondition(OverlayGeometry.width == 240 && OverlayGeometry.height == 44)
        precondition(OverlayGeometry.buttonRadius + OverlayGeometry.inset == OverlayGeometry.radius)
        precondition(!overlay.panel.canBecomeKey && !overlay.panel.canBecomeMain)
        precondition(overlay.panel.styleMask.contains(.nonactivatingPanel))
        if let screen = NSScreen.main {
            precondition(abs(overlay.panel.frame.midX - screen.visibleFrame.midX) < 1)
            precondition(abs(overlay.panel.frame.minY - screen.visibleFrame.minY - 24) < 1)
        }
        overlay.hide()
        precondition(!overlay.panel.isVisible)
        voice.prepareExit()
        await checkDeferredRecording(root: root)
        let reloaded = HistoryLibrary(store: HistoryStore(root: root.appendingPathComponent("data/History")))
        precondition(reloaded.records.count == 1)
        precondition(reloaded.records[0].transcriptions.count == 3 && reloaded.records[0].cleanups.count == 3)
        precondition(FileManager.default.fileExists(atPath: reloaded.audio(id).path))
        print(
            "PASS: audio archive/playback decoding, transcription success/retry/failure, cleanup model/usage/missing usage/failure, input lineage, restart persistence, background delivery policy, cancel/discard, nonactivating bottom-center overlay"
        )
    }
    @MainActor private static func checkDeferredRecording(root: URL) async {
        var status: AVAuthorizationStatus = .notDetermined
        var reply: CheckedContinuation<Bool, Never>?
        var requests = 0
        let actions = PermissionActions(
            microphoneStatus: { status }, speechStatus: { .denied },
            requestMicrophone: {
                requests += 1
                return await withCheckedContinuation { reply = $0 }
            },
            requestSpeech: { preconditionFailure("Unexpected speech request") }, openPane: { _ in },
            probeAccessibility: { nil })
        let fixture = FeatureFixture(
            directory: root.appendingPathComponent("deferred"),
            permissionActions: actions, inputAvailable: true)
        let held = Task { await fixture.dictation.start(fromHold: true, isHeld: { false }) }
        for _ in 0..<100 {
            if reply != nil { break }
            await Task.yield()
        }
        precondition(reply != nil && fixture.activity.phase == .preparingRecording)
        await fixture.dictation.start()
        precondition(requests == 1)
        status = .authorized
        reply?.resume(returning: true)
        await held.value
        precondition(fixture.activity.idle && fixture.library.records.isEmpty)
        precondition(fixture.dictation.status == "准备完成，请重新按住快捷键说话")

        status = .notDetermined
        reply = nil
        let cancelled = Task { await fixture.dictation.start() }
        for _ in 0..<100 {
            if reply != nil { break }
            await Task.yield()
        }
        precondition(reply != nil)
        fixture.dictation.closeOverlay()
        status = .authorized
        reply?.resume(returning: true)
        await cancelled.value
        precondition(fixture.activity.idle && !fixture.dictation.recording && fixture.library.records.isEmpty)
        precondition(fixture.delivery.cancelled)
    }
}

@MainActor final class FeatureFixture {
    let settings: AppSettings
    let permissions: PermissionModel
    let activity = ActivityState()
    let inputs: AudioInputMonitor
    let recorder = AudioRecorder()
    let playback = AudioPlayback()
    let library: HistoryLibrary
    let processing: ProcessingService
    let delivery = TextDelivery()
    let dictation: DictationModel
    let history: HistoryModel
    let shortcuts: ShortcutModel
    init(directory: URL, permissionActions: PermissionActions? = nil, inputAvailable: Bool = false) {
        inputs = AudioInputMonitor(probe: { inputAvailable }, subscribe: false)
        settings = AppSettings(store: PreferencesStore(directory: directory))
        permissions = PermissionModel(
            actions: permissionActions
                ?? PermissionActions(
                    microphoneStatus: { .denied }, speechStatus: { .denied },
                    requestMicrophone: { preconditionFailure("Unexpected microphone request") },
                    requestSpeech: { preconditionFailure("Unexpected speech request") },
                    openPane: { _ in preconditionFailure("Unexpected system settings navigation") },
                    probeAccessibility: { nil }
                ))
        library = HistoryLibrary(store: HistoryStore(root: directory.appendingPathComponent("History")))
        let transcription = TranscriptionService(permissions: permissions)
        let client = ModelClient(savedKey: { "" }, hasSavedKey: { false })
        processing = ProcessingService(transcription: transcription, models: client, history: library)
        dictation = DictationModel(
            settings: settings, activity: activity, permissions: permissions,
            inputs: inputs, recorder: recorder, playback: playback, history: library,
            processing: processing, delivery: delivery)
        history = HistoryModel(
            library: library, processing: processing, settings: settings, activity: activity, playback: playback)
        shortcuts = ShortcutModel(settings: settings, activity: activity, monitor: nil)
    }
}
