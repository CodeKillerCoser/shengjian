import AVFoundation
import AppKit
import Foundation
import Speech

// Run the same signed executable in a fresh, headless process: macOS can cache
// AXIsProcessTrusted in a long-running process after the grant is revoked.
struct AccessibilityProbe: Codable {
    let trusted: Bool
    let canPostEvents: Bool
    static func current() -> AccessibilityProbe {
        AccessibilityProbe(trusted: AXIsProcessTrusted(), canPostEvents: CGPreflightPostEventAccess())
    }
    static func fresh(executable: URL) -> AccessibilityProbe? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--permission-probe"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        for _ in 0..<40 {
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(
            AccessibilityProbe.self, from: output.fileHandleForReading.readDataToEndOfFile())
    }
}
// Keep permission requests separate from navigation: an app is not listed in
// Privacy settings until it has actually requested that permission.
struct PermissionActions {
    var microphoneStatus: () -> AVAuthorizationStatus
    var speechStatus: () -> SFSpeechRecognizerAuthorizationStatus
    var requestMicrophone: () async -> Bool
    var requestSpeech: () async -> SFSpeechRecognizerAuthorizationStatus
    var openPane: (String) -> Void
    var probeAccessibility: () async -> AccessibilityProbe? = {
        guard let executable = Bundle.main.executableURL else { return nil }
        return await Task.detached { AccessibilityProbe.fresh(executable: executable) }.value
    }
    static let system = PermissionActions(
        microphoneStatus: { AVCaptureDevice.authorizationStatus(for: .audio) },
        speechStatus: { SFSpeechRecognizer.authorizationStatus() },
        requestMicrophone: {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        },
        requestSpeech: {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        },
        openPane: { pane in
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) {
                NSWorkspace.shared.open(url)
            }
        }
    )
}
