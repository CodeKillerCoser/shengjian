import Foundation

enum AppStorage {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shengjian", isDirectory: true)
    }
    static func prepare(base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) throws {
        let fm = FileManager.default
        let old = base.appendingPathComponent("RimeVoice", isDirectory: true)
        let new = base.appendingPathComponent("Shengjian", isDirectory: true)
        for legacy in [base.appendingPathComponent("声笺", isDirectory: true), old] {
            if fm.fileExists(atPath: legacy.path) && !fm.fileExists(atPath: new.path) {
                try fm.moveItem(at: legacy, to: new)
            }
        }
        try fm.createDirectory(at: new, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}
