import Foundation
import AVFoundation
import AppKit

@main struct HistoryChecks {
    @MainActor static func wait(_ voice: Voice) async throws {
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
            ("https://example.com/v1/models/", "https://example.com/v1/models")
        ] {
            let url = try ModelServiceAddress.modelsURL(endpoint)
            precondition(url.absoluteString == expected)
        }
        do {
            _ = try ModelServiceAddress.modelsURL("http://example.com/v1")
            preconditionFailure("Remote plaintext model discovery must be rejected")
        } catch { }
        let list = try ModelServiceAddress.modelIDs(from: Data(#"{"data":[{"id":"z"},{"id":"a"},{"id":"z"},{"id":""}]}"#.utf8))
        precondition(list == ["a", "z"])
        var availableInput = false
        var probes = 0
        let inputMonitor = AudioInputMonitor(probe: { probes += 1; return availableInput }, subscribe: false)
        precondition(!inputMonitor.hasInput && probes == 1)
        availableInput = true
        inputMonitor.deviceConfigurationChanged()
        precondition(inputMonitor.hasInput && probes == 2)
        availableInput = false
        inputMonitor.deviceConfigurationChanged()
        precondition(!inputMonitor.hasInput && probes == 3)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let voice = Voice(directory: root.appendingPathComponent("data"), systemHooks: false)
        voice.prefs.engine = "whisper"
        voice.prefs.whisper = root.appendingPathComponent("fake-whisper.py").path
        voice.prefs.modelPath = root.appendingPathComponent("test-ggml.bin").path
        voice.prefs.online = false
        let audioURL = root.appendingPathComponent("sample.wav")
        let originalAudio = try Data(contentsOf: audioURL)
        let prepared = try SpeechAudio.prepare(audioURL)
        precondition(abs(prepared.duration - 2) < 0.01)
        precondition(prepared.buffer.frameLength == 38400)
        let unchangedAudio = try Data(contentsOf: audioURL)
        precondition(unchangedAudio == originalAudio)
        precondition(SpeechAudio.isNoSpeech(NSError(domain: "kAFAssistantErrorDomain", code: 1110)))
        precondition(!SpeechAudio.isNoSpeech(NSError(domain: "test", code: 123)))
        voice.audio = audioURL
        voice.elapsed = 2
        precondition(!voice.transcriptReady && !voice.rewriteReady)
        voice.recognizeRecording()
        try await wait(voice)
        precondition(voice.history.count == 1)
        let id = voice.history[0].id
        precondition(voice.raw == "这是转写测试。")
        precondition(voice.transcriptReady && !voice.rewriteReady)
        precondition(FileManager.default.fileExists(atPath: voice.historyStore.audio(id).path))
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("sample.wav").path))
        let player = try AVAudioPlayer(contentsOf: voice.historyStore.audio(id))
        precondition(abs(player.duration - 2) < 0.1)
        precondition(voice.history[0].transcriptions[0].elapsed > 0)
        precondition(voice.history[0].transcriptions[0].model == "test-ggml.bin")

        voice.reprocess(id, tidyOnly: false)
        try await wait(voice)
        precondition(voice.history[0].transcriptions.count == 2)
        voice.prefs.whisper = "/does-not-exist"
        voice.reprocess(id, tidyOnly: false)
        try await wait(voice)
        precondition(voice.history[0].transcriptions.count == 3)
        precondition(voice.history[0].transcriptions.last?.error != nil)
        precondition(voice.history[0].transcript?.text == "这是转写测试。")
        precondition(FileManager.default.fileExists(atPath: voice.historyStore.audio(id).path))

        voice.prefs.endpoint = "http://127.0.0.1:" + CommandLine.arguments[2] + "/v1"
        voice.prefs.model = "requested-model"
        voice.reprocess(id, tidyOnly: true)
        try await wait(voice)
        let first = voice.history[0].cleanups[0]
        precondition(first.text == "这是整理结果。")
        precondition(first.model == "actual-test-model" && first.modelReported)
        precondition(first.usage?.input == 12 && first.usage?.output == 8 && first.usage?.total == 20)
        precondition(first.inputText == "这是转写测试。")
        voice.prefs.model = "no-usage"
        voice.reprocess(id, tidyOnly: true)
        try await wait(voice)
        precondition(voice.history[0].cleanups.count == 2)
        precondition(voice.history[0].cleanups.last?.usage == nil)
        voice.prefs.model = "server-error"
        voice.reprocess(id, tidyOnly: true)
        try await wait(voice)
        precondition(voice.history[0].cleanups.count == 3)
        precondition(voice.history[0].cleanups.last?.error != nil)
        precondition(voice.history[0].cleanup?.success == true)
        // Output options apply equally to background and foreground sessions.
        voice.backgroundSession = true
        voice.prefs.autoInsert = false
        precondition(!voice.shouldAutoInsert && voice.shouldAutoCopy)
        voice.prefs.autoInsert = true
        precondition(voice.shouldAutoInsert)
        voice.prefs.copyAfterTranscription = false
        precondition(!voice.shouldAutoCopy && voice.shouldAutoInsert)
        let session = voice.overlaySession
        voice.busy = true
        voice.closeOverlay()
        precondition(!voice.shouldAutoInsert && voice.overlaySession != session)
        voice.busy = false
        // Closing a live recording discards only the unconfirmed temporary audio.
        let cancelled = root.appendingPathComponent("cancelled.wav")
        try Data(contentsOf: voice.historyStore.audio(id)).write(to: cancelled)
        voice.audio = cancelled; voice.currentHistoryID = nil; voice.recording = true
        voice.closeOverlay()
        precondition(!voice.recording && voice.audio == nil)
        precondition(!FileManager.default.fileExists(atPath: cancelled.path))
        precondition(voice.history.count == 1)
        voice.backgroundSession = false; voice.deliveryCancelled = false; voice.prefs.autoInsert = false
        precondition(!voice.shouldAutoInsert)
        voice.prefs.autoInsert = true
        precondition(voice.shouldAutoInsert)
        // Clipboard restoration preserves rich data and does not overwrite a
        // new clipboard change made while paste delivery was in flight.
        let clipboard = NSPasteboard.withUniqueName()
        clipboard.setString("before", forType: .string)
        let snapshot = ClipboardSnapshot(pasteboard: clipboard)
        clipboard.clearContents(); clipboard.setString("temporary result", forType: .string)
        snapshot.restore(ifUnchanged: clipboard.changeCount, pasteboard: clipboard)
        precondition(clipboard.string(forType: .string) == "before")
        clipboard.clearContents(); clipboard.setString("temporary result", forType: .string)
        let written = clipboard.changeCount
        clipboard.clearContents(); clipboard.setString("new user copy", forType: .string)
        snapshot.restore(ifUnchanged: written, pasteboard: clipboard)
        precondition(clipboard.string(forType: .string) == "new user copy")
        clipboard.releaseGlobally()
        _ = NSApplication.shared
        let overlay = RecordingOverlay(voice: voice)
        overlay.show(on: NSScreen.main)
        precondition(overlay.panel.isVisible)
        precondition(overlay.panel.frame.width == OverlayGeometry.width && overlay.panel.frame.height == OverlayGeometry.height)
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
        let reloaded = Voice(directory: root.appendingPathComponent("data"), systemHooks: false)
        precondition(reloaded.history.count == 1)
        precondition(reloaded.history[0].transcriptions.count == 3 && reloaded.history[0].cleanups.count == 3)
        precondition(FileManager.default.fileExists(atPath: reloaded.historyStore.audio(id).path))
        print("PASS: audio archive/playback decoding, transcription success/retry/failure, cleanup model/usage/missing usage/failure, input lineage, restart persistence, background delivery policy, cancel/discard, nonactivating bottom-center overlay")
    }
}
