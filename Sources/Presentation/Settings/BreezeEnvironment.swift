import Combine
import Foundation

@MainActor final class BreezeEnvironment: ObservableObject {
    @Published private(set) var message = "尚未检测"
    @Published private(set) var running = false
    @Published private(set) var installing = false
    @Published private(set) var log = ""
    @Published var proxy: String
    private let service: BreezeEnvironmentService
    var path: String { service.directory.path }
    var directory: URL { service.directory }
    var python: URL { service.python }

    init(service: BreezeEnvironmentService) {
        self.service = service
        proxy = BreezeEnvironmentService.systemProxy
    }
    func detect() async {
        guard !running else { return }
        running = true
        defer { running = false }
        do {
            let report = try await service.detect()
            message = report.message
            log = report.log
        } catch { message = error.localizedDescription }
    }
    func install() async {
        guard !running else { return }
        running = true
        installing = true
        log = ""
        message = "正在安装，首次下载模型约 7 GB；请保持声笺打开"
        defer {
            running = false
            installing = false
        }
        do {
            let report = try await service.install(proxy: proxy)
            message = report.message
            log = report.log
        } catch { message = error.localizedDescription }
    }
    func refreshLog() { if let text = service.installationLog() { log = text } }
}
