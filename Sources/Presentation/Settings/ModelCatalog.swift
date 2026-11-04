import Combine
import Foundation

@MainActor final class ModelCatalog: ObservableObject {
    @Published private(set) var models: [String] = []
    @Published private(set) var loading = false
    @Published private(set) var message = ""
    @Published private(set) var savedKeyExists = false
    private let client: ModelClient
    private var generation = UUID()
    private var loadTask: Task<Void, Never>?

    init(client: ModelClient) { self.client = client }
    func schedule(_ input: ModelDiscoveryInput) {
        cancel()
        let request = generation
        loadTask = Task {
            async let exists = client.hasSavedKey()
            do {
                try await Task.sleep(nanoseconds: 650_000_000)
                try Task.checkCancellation()
                models = []
                message = ""
                if !input.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    loading = true
                    let result = try await client.models(input)
                    try Task.checkCancellation()
                    guard generation == request else { return }
                    models = result
                    if models.isEmpty { message = "服务未返回模型，可手动填写" }
                }
            } catch is CancellationError {} catch {
                if !Task.isCancelled && generation == request { message = "未能获取模型列表，可手动填写或重试" }
            }
            let keyExists = await exists
            guard generation == request else { return }
            savedKeyExists = keyExists
            loading = false
        }
    }
    func cancel() {
        generation = UUID()
        loadTask?.cancel()
        loadTask = nil
        loading = false
    }
}
