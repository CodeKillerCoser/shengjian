import AVFoundation
import AppKit
import Speech

@MainActor private final class PermissionFixture {
    var microphone: AVAuthorizationStatus = .notDetermined
    var speech: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    var microphoneResult: AVAuthorizationStatus = .authorized
    var speechResult: SFSpeechRecognizerAuthorizationStatus = .authorized
    var microphoneRequests = 0
    var speechRequests = 0
    var opened: [String] = []
    var holdMicrophone = false
    var microphoneReply: CheckedContinuation<Bool, Never>?

    var actions: PermissionActions {
        PermissionActions(
            microphoneStatus: { self.microphone }, speechStatus: { self.speech },
            requestMicrophone: {
                self.microphoneRequests += 1
                if self.holdMicrophone {
                    return await withCheckedContinuation { self.microphoneReply = $0 }
                }
                self.microphone = self.microphoneResult
                return self.microphone == .authorized
            },
            requestSpeech: {
                self.speechRequests += 1
                self.speech = self.speechResult
                return self.speech
            },
            openPane: { self.opened.append($0) }
        )
    }
}

enum PermissionChecks {
    @MainActor static func run() async {
        // A fresh installation must request access before sending the user to
        // a Settings list that cannot contain this app yet. No real TCC calls.
        for granted in [true, false] {
            let fixture = PermissionFixture()
            fixture.microphoneResult = granted ? .authorized : .denied
            fixture.speechResult = granted ? .authorized : .denied
            let permissions = PermissionModel(actions: fixture.actions)
            await permissions.manageMicrophone()
            await permissions.manageSpeech()
            precondition(fixture.microphoneRequests == 1 && fixture.speechRequests == 1)
            precondition(fixture.opened.isEmpty)
            precondition(permissions.microphone == fixture.microphoneResult)
            precondition(permissions.speech == fixture.speechResult)
            precondition(!permissions.requestingMicrophone && !permissions.requestingSpeech)
            await permissions.manageMicrophone()
            await permissions.manageSpeech()
            precondition(fixture.microphoneRequests == 1 && fixture.speechRequests == 1)
            precondition(fixture.opened == ["Privacy_Microphone", "Privacy_SpeechRecognition"])
        }
        let restricted = PermissionFixture()
        restricted.microphone = .restricted
        restricted.speech = .restricted
        let limited = PermissionModel(actions: restricted.actions)
        await limited.manageMicrophone()
        await limited.manageSpeech()
        precondition(restricted.microphoneRequests == 0 && restricted.speechRequests == 0)

        // Re-read status at click time, including grants made outside the app.
        let changed = PermissionFixture()
        let stale = PermissionModel(actions: changed.actions)
        changed.microphone = .authorized
        changed.speech = .authorized
        await stale.manageMicrophone()
        await stale.manageSpeech()
        precondition(changed.microphoneRequests == 0 && changed.speechRequests == 0)
        precondition(stale.microphone == .authorized && stale.speech == .authorized)

        let pending = PermissionFixture()
        pending.holdMicrophone = true
        let waiting = PermissionModel(actions: pending.actions)
        let first = Task { await waiting.manageMicrophone() }
        for _ in 0..<100 {
            if pending.microphoneReply != nil { break }
            await Task.yield()
        }
        precondition(waiting.requestingMicrophone && pending.microphoneReply != nil)
        await waiting.manageMicrophone()
        precondition(pending.microphoneRequests == 1 && pending.opened.isEmpty)
        let shared = Task { await waiting.requestMicrophoneIfNeeded() }
        pending.microphone = .authorized
        pending.microphoneReply?.resume(returning: true)
        await first.value
        let granted = await shared.value
        precondition(granted && pending.microphoneRequests == 1)
        precondition(waiting.microphone == .authorized && !waiting.requestingMicrophone)

        // Only documented, non-sensitive window metadata is supplied: no AX,
        // screen recording, window title, or captured pixels are needed.
        func window(
            _ id: Int, x: CGFloat = 0, onscreen: Bool = true, pid: Int32 = 42,
            layer: Int = 0, width: CGFloat = 740
        ) -> SettingsGuideWindow? {
            SettingsGuideWindow(
                info: [
                    kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid,
                    kCGWindowLayer as String: layer, kCGWindowIsOnscreen as String: onscreen,
                    kCGWindowBounds as String: CGRect(x: x, y: 100, width: width, height: 620).dictionaryRepresentation,
                ], ownerPID: 42)
        }
        let original = window(1)!
        let replacement = window(2, x: 250)!
        precondition(window(3, pid: 43) == nil && window(3, layer: 3) == nil && window(3, width: 200) == nil)
        precondition(SettingsGuideWindow.target(in: [original, replacement], preferredID: 1)?.id == 1)
        precondition(SettingsGuideWindow.target(in: [replacement], preferredID: 1)?.id == 2)
        precondition(
            SettingsGuideWindow.target(in: [window(1, onscreen: false)!, replacement], preferredID: 1)?.id == 2)
        precondition(SettingsGuideWindow.target(in: [window(1, onscreen: false)!], preferredID: 1) == nil)
        precondition(SettingsGuideWindow.target(in: [], preferredID: 1) == nil)
        precondition(SettingsGuideWindow.target(in: [replacement], preferredID: nil)?.id == 2)

        let desktop = CGRect(x: -1600, y: -900, width: 4000, height: 2400)
        let start = CGRect(x: 100, y: 100, width: 740, height: 620)
        let card = AuthorizationGuideLayout.frame(settings: start, visibleArea: desktop)
        let moved = AuthorizationGuideLayout.frame(settings: start.offsetBy(dx: -900, dy: 300), visibleArea: desktop)
        precondition(moved == card.offsetBy(dx: -900, dy: 300))
        let smallScreen = CGRect(x: 0, y: 0, width: 500, height: 800)
        let clipped = AuthorizationGuideLayout.frame(settings: start, visibleArea: smallScreen)
        precondition(smallScreen.contains(clipped))
        print(
            "PASS: permission requests, settings navigation, duplicate requests, guide window replacement and movement")
    }
}
