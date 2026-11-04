import Foundation

struct BreezeService {
    let directory: URL
    let baseURL: URL
    private let session: URLSession
    var root: URL? {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("manage.py").path) ? directory : nil
    }
    init(directory: URL, baseURL: URL = URL(string: "http://127.0.0.1:17860")!, session: URLSession = .shared) {
        self.directory = directory
        self.baseURL = baseURL
        self.session = session
    }
    func control(_ action: String) async throws -> String {
        guard let root else { throw failure("未找到 Breeze 服务目录，请重新构建声笺") }
        return try await Task.detached {
            let process = Process()
            process.executableURL = root.appendingPathComponent("runtime/.venv/bin/python")
            process.arguments = [root.appendingPathComponent("manage.py").path, action]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? "操作已完成"
        }.value
    }
    func check() async throws -> Bool {
        let (_, response) = try await session.data(from: baseURL.appendingPathComponent("health"))
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
    func generate(text: String, instruction: String, referenceURL: URL?, referenceText: String) async throws -> URL {
        guard let root else { throw failure("未找到服务目录") }
        let boundary = UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(
                Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("text", text)
        field("seed", "42")
        if !instruction.isEmpty {
            field("instruction", instruction)
            field("cfg_scale", "4")
        }
        if let referenceURL {
            guard !referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw failure("请填写参考音频的准确文字稿")
            }
            let reference = try Data(contentsOf: referenceURL)
            guard reference.count <= 25 * 1024 * 1024 else { throw failure("参考音频不能超过 25 MB") }
            field("ref_text", referenceText)
            body.append(
                Data(
                    "--\(boundary)\r\nContent-Disposition: form-data; name=\"ref_audio\"; filename=\"reference.\(referenceURL.pathExtension)\"\r\nContent-Type: application/octet-stream\r\n\r\n"
                        .utf8))
            body.append(reference)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/audio/speech"))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (pcm, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw failure(String(data: pcm, encoding: .utf8) ?? "合成请求失败")
        }
        guard !pcm.isEmpty, pcm.count % 2 == 0 else { throw failure("服务返回了无效音频") }
        var wav = Data()
        func ascii(_ s: String) { wav.append(Data(s.utf8)) }
        func u32(_ x: UInt32) {
            var v = x.littleEndian
            withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) }
        }
        func u16(_ x: UInt16) {
            var v = x.littleEndian
            withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) }
        }
        ascii("RIFF")
        u32(UInt32(pcm.count + 36))
        ascii("WAVEfmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(24000)
        u32(48000)
        u16(2)
        u16(16)
        ascii("data")
        u32(UInt32(pcm.count))
        wav.append(pcm)
        let folder = root.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(
            "声笺-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).wav")
        try wav.write(to: url, options: .atomic)
        return url
    }
}
