import SwiftUI

struct ContentView: View {
    let app: AppModel
    @ObservedObject private var dictation: DictationModel
    init(app: AppModel) {
        self.app = app
        _dictation = ObservedObject(wrappedValue: app.dictation)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: Brand.logo).resizable().scaledToFit().frame(width: 42, height: 42)
                VStack(alignment: .leading) {
                    Text("声笺").font(.title2.bold())
                    Text("让表达，自然成文").foregroundStyle(.secondary)
                }
                Spacer()
            }
            TabView {
                DictationView(
                    model: app.dictation, settings: app.settings, recorder: app.recorder,
                    inputs: app.inputs, shortcuts: app.shortcuts
                )
                .tabItem { Label("听写", systemImage: "mic") }
                BreezeView(model: app.breeze, rawText: dictation.raw, rewrittenText: dictation.output)
                    .tabItem { Label("语音合成", systemImage: "speaker.wave.2") }
                HistoryView(model: app.history).tabItem { Label("转写历史", systemImage: "clock.arrow.circlepath") }
                SettingsView(
                    model: app.settings, shortcuts: app.shortcuts, activity: app.activity,
                    permissions: app.permissions, catalog: app.catalog, inputs: app.inputs, guide: app.guide,
                    breezeEnvironment: app.breezeEnvironment
                )
                .tabItem { Label("设置", systemImage: "gearshape") }
            }
        }.padding(24).frame(minWidth: 760, minHeight: 560)
    }
}
