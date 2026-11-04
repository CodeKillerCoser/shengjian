import AppKit
import SwiftUI

struct MLXSettingsSection: View {
    @ObservedObject var environment: BreezeEnvironment
    var body: some View {
        Section("本地推理引擎 · MLX") {
            Text("MLX 是推理框架，语音识别、文字整理和语音合成需要各自的模型。目前此环境已接入 Breeze 语音合成。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("运行环境目录")
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
            Text("首次安装需要联网，模型约 7 GB。模型与运行环境保存在应用数据目录，下载缓存位于系统缓存目录。修复前请停止语音服务。")
                .font(.caption).foregroundStyle(.secondary)
            if !environment.log.isEmpty {
                DisclosureGroup("检测详情 / 安装日志") {
                    ScrollView {
                        Text(environment.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 150)
                }
            }
        }.task { await environment.detect() }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                if environment.installing { environment.refreshLog() }
            }
    }
}
