import AppKit

enum LaunchDiagnostics {
    @MainActor static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--permission-probe") {
            write(AccessibilityProbe.current())
            exit(0)
        }
        guard let index = args.firstIndex(of: "--speech-diagnostic"), args.indices.contains(index + 1) else { return }
        let audio = URL(fileURLWithPath: args[index + 1])
        Task { @MainActor in
            let service = TranscriptionService(permissions: PermissionModel())
            let started = ProcessInfo.processInfo.systemUptime
            var retried = false
            var report: [String: Any]
            do {
                let text = try await service.transcribe(audio, prefs: Prefs(), onRetry: { retried = true })
                report = ["success": true, "characters": text.count]
            } catch { report = ["success": false, "error": error.localizedDescription] }
            report["seconds"] = ProcessInfo.processInfo.systemUptime - started
            report["bufferRetry"] = retried
            if let data = try? JSONSerialization.data(withJSONObject: report) { FileHandle.standardOutput.write(data) }
            exit(0)
        }
        RunLoop.main.run()
        exit(1)
    }
    private static func write(_ value: AccessibilityProbe) {
        guard let data = try? JSONEncoder().encode(value) else { exit(1) }
        FileHandle.standardOutput.write(data)
    }
}
