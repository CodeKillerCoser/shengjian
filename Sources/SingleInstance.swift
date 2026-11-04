import AppKit
import Darwin

/// A process-held lock shared by all copies of this app for the current user.
/// The OS releases it on normal exit or crash; the file must never be unlinked.
final class SingleInstance {
    static let shared = SingleInstance()
    private var descriptor: Int32 = -1
    func acquire(at url: URL) throws -> Bool {
        if descriptor >= 0 { return true }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno; Darwin.close(fd)
            if code == EWOULDBLOCK { return false }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        descriptor = fd
        return true
    }
    static func enforce() {
        let url = AppStorage.root.appendingPathComponent("instance.lock")
        do { try AppStorage.prepare() } catch {
            let alert = NSAlert(); alert.messageText = "数据目录迁移失败"
            alert.informativeText = error.localizedDescription; alert.runModal(); exit(1)
        }
        do {
            guard try shared.acquire(at: url) else {
                let currentPID = ProcessInfo.processInfo.processIdentifier
                if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.shengjian.app").first(where: { $0.processIdentifier != currentPID }) {
                    existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                    if let bundle = existing.bundleURL {
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.createsNewApplicationInstance = false
                        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { _, _ in exit(0) }
                        // Keep this process alive only to deliver the reopen request.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
                        RunLoop.main.run()
                    }
                }
                exit(0)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法启动 声笺"
            alert.informativeText = "无法建立单实例锁：" + error.localizedDescription
            alert.runModal()
            exit(1)
        }
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}
