import AppKit
import Combine

// Composition and application lifecycle only. Screens receive their own
// models; platform services never reference this object.
@MainActor final class AppModel: ObservableObject {
    let settings: AppSettings
    let history: HistoryModel
    let dictation: DictationModel
    let shortcuts: ShortcutModel
    let permissions: PermissionModel
    let catalog: ModelCatalog
    let inputs: AudioInputMonitor
    let recorder: AudioRecorder
    let activity = ActivityState()
    let guide: AuthorizationGuideController
    let breeze: BreezeController
    let breezeEnvironment: BreezeEnvironment
    let speechRecognition: SpeechRecognitionService
    private let transcription: TranscriptionService
    private let playback = AudioPlayback()
    private var overlay: RecordingOverlay?
    private var overlayScreen: NSScreen?
    private var overlaySession: UUID?
    private var subscriptions = Set<AnyCancellable>()

    init(directory: URL? = nil, systemIntegration: Bool = true) {
        let directory = directory ?? AppStorage.root
        settings = AppSettings(store: PreferencesStore(directory: directory))
        permissions = PermissionModel()
        inputs = AudioInputMonitor()
        recorder = AudioRecorder(temporaryDirectory: directory.appendingPathComponent("Temporary", isDirectory: true))
        let breezeDirectory = directory.appendingPathComponent("Engines/Breeze", isDirectory: true)
        speechRecognition = SpeechRecognitionService(
            settings: settings, permissions: permissions,
            temporaryDirectory: directory.appendingPathComponent("Temporary", isDirectory: true))
        breeze = BreezeController(
            service: BreezeService(directory: breezeDirectory),
            speechRecognition: speechRecognition, activity: activity)
        breezeEnvironment = BreezeEnvironment(service: BreezeEnvironmentService(directory: breezeDirectory))
        transcription = TranscriptionService(permissions: permissions)
        let client = ModelClient()
        let library = HistoryLibrary(
            store: HistoryStore(root: directory.appendingPathComponent("History", isDirectory: true)))
        let processing = ProcessingService(transcription: transcription, models: client, history: library)
        catalog = ModelCatalog(client: client)
        guide = AuthorizationGuideController(permissions: permissions)
        history = HistoryModel(
            library: library, processing: processing, settings: settings, activity: activity, playback: playback)
        dictation = DictationModel(
            settings: settings, activity: activity, permissions: permissions,
            inputs: inputs, recorder: recorder, playback: playback, history: library,
            processing: processing, delivery: systemIntegration ? TextDelivery() : nil)
        shortcuts = ShortcutModel(
            settings: settings, activity: activity, monitor: systemIntegration ? HotKeyMonitor() : nil)
        overlay = RecordingOverlay(
            model: dictation, recorder: recorder, openMainWindow: { [weak self] in self?.openMainWindow() })
        dictation.$overlayVisible.sink { [weak self] visible in self?.updateOverlay(visible: visible) }.store(
            in: &subscriptions)
        dictation.$currentRecordID.compactMap { $0 }.sink { [weak self] id in
            self?.history.selectedID = id
        }.store(in: &subscriptions)
        guard systemIntegration else { return }
        shortcuts.onPress = { [weak self] in
            guard let self else { return }
            if shortcuts.holdMode {
                Task { await self.dictation.start(fromHold: true, isHeld: { self.shortcuts.held }) }
            } else {
                dictation.toggle()
            }
        }
        shortcuts.onRelease = { [weak self] in
            guard let self, shortcuts.holdMode, dictation.recording else { return }
            dictation.stop()
        }
        shortcuts.start()
        inputs.$hasInput.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.dictation.prepareCapture(reset: true) }
        }.store(in: &subscriptions)
        permissions.$microphone.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.dictation.prepareCapture() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .sink { [weak self] _ in self?.shortcuts.cancelCapture() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.permissions.refresh()
                self?.dictation.prepareCapture()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.shutdown() }.store(in: &subscriptions)
        dictation.prepareCapture()
    }
    private func updateOverlay(visible: Bool) {
        guard visible else {
            overlay?.hide()
            return
        }
        if overlaySession != dictation.overlaySession {
            overlaySession = dictation.overlaySession
            overlayScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        }
        overlay?.show(on: overlayScreen)
    }
    func openMainWindow() {
        dictation.hideOverlay()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
    }
    func shutdown() {
        breeze.shutdown()
        shortcuts.stop()
        guide.close()
        catalog.cancel()
        dictation.prepareExit()
        history.prepareExit()
        transcription.cancel()
    }
}
