import SwiftUI
import AppKit
import Security

struct ModelDiscoveryInput: Hashable {
    let endpoint: String
    let key: String
}
enum ModelServiceAddress {
    static func modelsURL(_ endpoint: String) throws -> URL {
        guard var parts = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host?.lowercased(), parts.user == nil, parts.password == nil else {
            throw failure("请填写有效的模型服务地址")
        }
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        guard parts.scheme == "https" || (parts.scheme == "http" && local) else { throw failure("模型服务需使用 HTTPS，本机服务可使用 HTTP") }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/chat/completions") { path.removeLast("/chat/completions".count) }
        if path.isEmpty { path = "/v1" }
        if !path.hasSuffix("/models") { path += "/models" }
        parts.path = path; parts.fragment = nil
        guard let url = parts.url else { throw failure("模型服务地址无效") }
        return url
    }
    static func modelIDs(from data: Data) throws -> [String] {
        struct Listing: Decodable { struct Item: Decodable { let id: String }; let data: [Item] }
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        return Set(listing.data.map(\.id).filter { !$0.isEmpty }).sorted()
    }
}
@MainActor final class ModelCatalog: ObservableObject {
    @Published var models: [String] = []
    @Published var loading = false
    @Published var message = ""
    @Published var savedKeyExists = false
    private var generation = UUID()
    private var loadTask: Task<Void, Never>?
    func schedule(_ input: ModelDiscoveryInput) {
        loadTask?.cancel()
        loadTask = Task { await refresh(input) }
        Task {
            let exists = await Task.detached { Vault.containsKey() }.value
            savedKeyExists = exists
        }
    }
    func cancel() { loadTask?.cancel(); loadTask = nil }

    func refresh(_ input: ModelDiscoveryInput) async {
        let requestID = UUID(); generation = requestID
        models = []; message = ""; loading = false
        do {
            try await Task.sleep(nanoseconds: 650_000_000)
            try Task.checkCancellation()
            loading = true
            guard !input.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { loading = false; return }
            let key = input.key
            let url = try ModelServiceAddress.modelsURL(input.endpoint)
            var request = URLRequest(url: url); request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            loading = true
            var (data, response) = try await URLSession.shared.data(for: request)
            if key.isEmpty, let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
                let saved = await Task.detached { Vault.load() }.value
                try Task.checkCancellation()
                guard generation == requestID else { return }
                guard saved.status == errSecSuccess, !saved.value.isEmpty else { throw failure("请保存 API Key 后重试") }
                request.setValue("Bearer \(saved.value)", forHTTPHeaderField: "Authorization")
                (data, response) = try await URLSession.shared.data(for: request)
            }
            try Task.checkCancellation()
            guard generation == requestID else { return }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw failure("模型列表暂不可用，可手动填写模型名称")
            }
            guard data.count <= 2_000_000 else { throw failure("模型列表过大，可手动填写模型名称") }
            models = try ModelServiceAddress.modelIDs(from: data)
            if models.isEmpty { message = "服务未返回模型，可手动填写" }
        } catch is CancellationError { }
        catch {
            if !Task.isCancelled && generation == requestID { message = "未能获取模型列表，可手动填写或重试" }
        }
        if generation == requestID { loading = false }
    }
}
