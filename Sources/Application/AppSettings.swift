import Combine
import Foundation

// Shared persisted preferences, not a page model. Dictation and history read
// the same configuration without depending on the settings screen.
@MainActor final class AppSettings: ObservableObject {
    @Published var prefs: Prefs
    @Published var key = ""
    @Published private(set) var status = ""
    private let store: PreferencesStore

    init(store: PreferencesStore) {
        self.store = store
        prefs = store.load()
    }
    func persist() throws { try store.save(prefs) }
    func save() {
        do {
            if !key.isEmpty { try CredentialStore.save(key) }
            try persist()
            status = "设置已保存"
        } catch { status = error.localizedDescription }
    }
}
