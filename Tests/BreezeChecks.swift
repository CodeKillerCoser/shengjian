import AVFoundation
import Foundation

enum BreezeChecks {
    @MainActor static func run(root: URL, port: String) async throws {
        let fm = FileManager.default
        let migration = root.appendingPathComponent("migration")
        let legacy = migration.appendingPathComponent("RimeVoice")
        let unified = migration.appendingPathComponent("Shengjian")
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("original settings".utf8).write(to: legacy.appendingPathComponent("settings.json"))
        try AppStorage.prepare(base: migration)
        let saved = try String(contentsOf: unified.appendingPathComponent("settings.json"))
        precondition(saved == "original settings" && !fm.fileExists(atPath: legacy.path))
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try AppStorage.prepare(base: migration)
        precondition(fm.fileExists(atPath: legacy.path), "An existing unified directory must not be overwritten")

        let directory = root.appendingPathComponent("breeze")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("existing deployment".utf8).write(to: directory.appendingPathComponent("manage.py"))
        let service = BreezeService(directory: directory, baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        let healthy = try await service.check()
        precondition(healthy)
        let audio = try await service.generate(text: "合成测试", instruction: "清晰", referenceURL: nil, referenceText: "")
        let file = try AVAudioFile(forReading: audio)
        precondition(file.processingFormat.sampleRate == 24000 && file.length == 2400)
        precondition(audio.deletingLastPathComponent() == directory.appendingPathComponent("audio", isDirectory: true))
        do {
            _ = try await service.generate(text: "合成测试", instruction: "", referenceURL: audio, referenceText: "")
            preconditionFailure("Reference audio requires a transcript")
        } catch {}

        let resources = root.appendingPathComponent("bootstrap-fixture")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        for name in ["setup.sh", "environment.sh", "manage.py", "start.sh"] {
            try Data("#!/bin/bash\nprintf '%s' \"$HTTPS_PROXY\"\n".utf8).write(
                to: resources.appendingPathComponent(name))
        }
        let environment = BreezeEnvironmentService(directory: directory, resources: resources)
        let detection = try await environment.detect()
        precondition(detection.message.contains("未找到独立 Python"))
        do {
            _ = try await environment.install(proxy: "ftp://invalid.example")
            preconditionFailure("Unsupported proxy must fail before installation")
        } catch {}
        let installation = try await environment.install(proxy: "http://127.0.0.1:9999")
        precondition(installation.message.contains("安装完成") && installation.log == "http://127.0.0.1:9999")
        let deployment = try String(contentsOf: directory.appendingPathComponent("manage.py"))
        let bundled = try String(contentsOf: resources.appendingPathComponent("manage.py"))
        precondition(deployment == bundled, "Repair must update app-owned bootstrap scripts")
        print(
            "PASS: unified storage migration, mocked Breeze synthesis/WAV, reference validation, isolated bootstrap and proxy forwarding"
        )
    }
}
