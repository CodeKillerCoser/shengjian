import SwiftUI
import AppKit
import CFNetwork

@MainActor final class BreezeEnvironment: ObservableObject {
    static let shared = BreezeEnvironment()
    @Published var path: String
    @Published var message = "尚未检测"
    @Published var running = false
    @Published var installing = false
    @Published var log = ""
    @Published var proxy = ""
    var directory: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var python: URL { directory.appendingPathComponent("runtime/.venv/bin/python") }
    private var process: Process?
    init() {
        path = AppStorage.root.appendingPathComponent("Engines/Breeze").path
        if let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
           settings[kCFNetworkProxiesHTTPSEnable as String] as? Int == 1,
           let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPSPort as String] as? Int {
            proxy = "http://\(host):\(port)"
        }
    }
    private func execute(_ executable: URL, arguments: [String], environment: [String: String] = [:], logURL: URL) async throws -> Int32 {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close(); process = nil }
        let task = Process(); task.executableURL = executable; task.arguments = arguments
        task.standardOutput = handle; task.standardError = handle
        task.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process = task
        return try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            do { try task.run() } catch { continuation.resume(throwing: error) }
        }
    }
    func detect() async {
        guard !running else { return }
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            message = "未找到独立 Python / MLX 环境，请点击安装。"; return
        }
        running = true; defer { running = false }
        do {
            let logs = directory.appendingPathComponent("logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let result = logs.appendingPathComponent("environment-check.log")
            let script = "import sys, mlx.core as mx, mlx_audio; from importlib.metadata import version; print('Python: '+sys.executable); print('MLX: '+version('mlx')); print('模块路径: '+mx.__file__); print('设备: '+str(mx.default_device()))"
            let code = try await execute(python, arguments: ["-I", "-c", script], logURL: result)
            log = (try? String(contentsOf: result, encoding: .utf8)) ?? ""
            let model = directory.appendingPathComponent("data/huggingface/hub/models--mlx-community--Breeze-TTS-2-mlx/snapshots/3c8829fb7fd335818f085cd2ef49b4100c0e46c8")
            let complete = ["model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors", "audio_tokenizer/model.safetensors"].allSatisfy { FileManager.default.fileExists(atPath: model.appendingPathComponent($0).path) }
            message = code == 0 ? (complete ? "MLX 环境与模型已就绪" : "MLX 可用，模型尚未下载完整；请安装或修复") : "MLX 加载失败，请查看检测详情后安装或修复"
        } catch { message = error.localizedDescription }
    }
    func install() async {
        guard !running else { return }
        guard !path.isEmpty else { message = "请先选择存放目录"; return }
        if !proxy.isEmpty {
            guard let url = URL(string: proxy), ["http", "https", "socks5"].contains(url.scheme ?? ""), url.host != nil else { message = "请输入有效代理地址，如 http://127.0.0.1:7897"; return }
        }
        running = true; installing = true; log = ""; message = "正在准备安装…"
        defer { running = false; installing = false }
        do {
            guard let resources = Bundle.main.resourceURL?.appendingPathComponent("BreezeBootstrap") else { throw failure("缺少内置安装文件，请重新构建声笺") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in ["setup.sh", "environment.sh", "manage.py", "start.sh"] {
                let target = directory.appendingPathComponent(name)
                // Existing deployment scripts remain intact during repair.
                if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: resources.appendingPathComponent(name), to: target) }
            }
            let logs = directory.appendingPathComponent("logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let logURL = logs.appendingPathComponent("install.log")
            var environment: [String: String] = [:]
            if !proxy.isEmpty { environment["HTTPS_PROXY"] = proxy; environment["HTTP_PROXY"] = proxy }
            message = "正在安装，首次下载模型约 7 GB；请保持声笺打开"
            let code = try await execute(URL(fileURLWithPath: "/bin/bash"), arguments: [directory.appendingPathComponent("setup.sh").path], environment: environment, logURL: logURL)
            log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            message = code == 0 ? "安装完成，点击检测环境验证后前往语音合成页启动服务" : "安装失败（\(code)），可查看日志后重试；下载缓存会保留"
        } catch { message = error.localizedDescription }
    }
    func refreshLog() {
        let file = directory.appendingPathComponent("logs/install.log")
        if let text = try? String(contentsOf: file, encoding: .utf8) { log = String(text.suffix(16000)) }
    }
}

struct MLXSettingsSection: View {
    @ObservedObject private var environment = BreezeEnvironment.shared
    var body: some View {
        Section("本地推理引擎 · MLX") {
            Text("MLX 是推理框架，语音识别、文字整理和语音合成需要各自的模型。目前此环境已接入 Breeze 语音合成。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("统一存放目录")
                Spacer()
                Text(environment.path).font(.caption).lineLimit(2).textSelection(.enabled)

            }
            Text("Python：\(environment.python.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(environment.message).font(.callout).textSelection(.enabled)
            TextField("下载代理（可选，自动读取系统代理）", text: $environment.proxy)
                .disabled(environment.running)
            HStack {
                Button("检测环境") { Task { await environment.detect() } }.disabled(environment.running)
                Button("安装 / 修复 MLX 与模型") { Task { await environment.install() } }.disabled(environment.running)
                if environment.running { ProgressView().controlSize(.small) }
                if environment.installing { Button("刷新安装进度") { environment.refreshLog() } }
                Button("打开目录") { NSWorkspace.shared.open(environment.directory) }
            }
            Text("首次安装需要联网，模型约 7 GB；Python、依赖和缓存均保存在所选目录。修复前请停止语音服务。")
                .font(.caption).foregroundStyle(.secondary)
            if !environment.log.isEmpty {
                DisclosureGroup("检测详情 / 安装日志") {
                    ScrollView { Text(environment.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 150)
                }
            }
        }.task { await environment.detect() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if environment.installing { environment.refreshLog() }
        }
    }
}
