import CFNetwork
import Foundation

struct BreezeEnvironmentReport {
    let message: String
    let log: String
}

@MainActor final class BreezeEnvironmentService {
    let directory: URL
    private let resources: URL?
    private var process: Process?
    var python: URL { directory.appendingPathComponent("runtime/.venv/bin/python") }
    init(directory: URL, resources: URL? = Bundle.main.resourceURL?.appendingPathComponent("BreezeBootstrap")) {
        self.directory = directory
        self.resources = resources
    }
    static var systemProxy: String {
        if let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
            settings[kCFNetworkProxiesHTTPSEnable as String] as? Int == 1,
            let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String,
            let port = settings[kCFNetworkProxiesHTTPSPort as String] as? Int
        {
            return "http://\(host):\(port)"
        }
        return ""
    }
    private func execute(_ executable: URL, arguments: [String], environment: [String: String] = [:], logURL: URL)
        async throws -> Int32
    {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        defer {
            try? handle.close()
            process = nil
        }
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        task.standardOutput = handle
        task.standardError = handle
        task.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process = task
        return try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            do { try task.run() } catch { continuation.resume(throwing: error) }
        }
    }
    func detect() async throws -> BreezeEnvironmentReport {
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            return BreezeEnvironmentReport(message: "未找到独立 Python / MLX 环境，请点击安装。", log: "")
        }
        let logs = directory.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let result = logs.appendingPathComponent("environment-check.log")
        let script =
            "import sys, mlx.core as mx, mlx_audio; from importlib.metadata import version; print('Python: '+sys.executable); print('MLX: '+version('mlx')); print('模块路径: '+mx.__file__); print('设备: '+str(mx.default_device()))"
        let code = try await execute(python, arguments: ["-I", "-c", script], logURL: result)
        let log = (try? String(contentsOf: result, encoding: .utf8)) ?? ""
        let model = directory.appendingPathComponent(
            "data/huggingface/hub/models--mlx-community--Breeze-TTS-2-mlx/snapshots/3c8829fb7fd335818f085cd2ef49b4100c0e46c8"
        )
        let complete = [
            "model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors", "audio_tokenizer/model.safetensors",
        ].allSatisfy {
            FileManager.default.fileExists(atPath: model.appendingPathComponent($0).path)
        }
        let message = code == 0 ? (complete ? "MLX 环境与模型已就绪" : "MLX 可用，模型尚未下载完整；请安装或修复") : "MLX 加载失败，请查看检测详情后安装或修复"
        return BreezeEnvironmentReport(message: message, log: log)
    }
    func install(proxy: String) async throws -> BreezeEnvironmentReport {
        if !proxy.isEmpty {
            guard let url = URL(string: proxy), ["http", "https", "socks5"].contains(url.scheme ?? ""), url.host != nil
            else {
                throw failure("请输入有效代理地址，如 http://127.0.0.1:7897")
            }
        }
        guard let resources else { throw failure("缺少内置安装文件，请重新构建声笺") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["setup.sh", "environment.sh", "manage.py", "start.sh"] {
            let target = directory.appendingPathComponent(name)
            // Existing deployment scripts remain intact during repair.
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.copyItem(at: resources.appendingPathComponent(name), to: target)
            }
        }
        let logs = directory.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logURL = logs.appendingPathComponent("install.log")
        var environment: [String: String] = [:]
        if !proxy.isEmpty {
            environment["HTTPS_PROXY"] = proxy
            environment["HTTP_PROXY"] = proxy
        }
        let code = try await execute(
            URL(fileURLWithPath: "/bin/bash"), arguments: [directory.appendingPathComponent("setup.sh").path],
            environment: environment, logURL: logURL)
        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let message = code == 0 ? "安装完成，点击检测环境验证后前往语音合成页启动服务" : "安装失败（\(code)），可查看日志后重试；下载缓存会保留"
        return BreezeEnvironmentReport(message: message, log: log)
    }
    func installationLog() -> String? {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("logs/install.log"), encoding: .utf8)
        else { return nil }
        return String(text.suffix(16000))
    }
}
