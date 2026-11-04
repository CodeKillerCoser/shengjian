import Foundation

struct PreferencesStore {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("settings.json") }

    func load() -> Prefs {
        guard let data = try? Data(contentsOf: file),
            let prefs = try? JSONDecoder().decode(Prefs.self, from: data)
        else { return Prefs() }
        return prefs
    }
    func save(_ prefs: Prefs) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(prefs).write(to: file, options: .atomic)
    }
}
