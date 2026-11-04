import AVFoundation
import Combine
import Foundation
import Speech

enum AccessibilityPermissionState {
    case checking, authorized, notGranted, unavailable
    var label: String {
        switch self {
        case .checking: return "正在检测"
        case .authorized: return "已授权"
        case .notGranted: return "未开启"
        case .unavailable: return "检测失败"
        }
    }
}

@MainActor final class PermissionModel: ObservableObject {
    @Published var microphone: AVAuthorizationStatus
    @Published var speech: SFSpeechRecognizerAuthorizationStatus
    @Published private(set) var requestingMicrophone = false
    @Published private(set) var requestingSpeech = false
    @Published var accessibility = AccessibilityPermissionState.checking
    private let actions: PermissionActions
    private var microphoneTask: Task<Bool, Never>?
    private var speechTask: Task<SFSpeechRecognizerAuthorizationStatus, Never>?
    private var accessibilityTask: Task<Void, Never>?
    init(actions: PermissionActions = .system) {
        self.actions = actions
        microphone = actions.microphoneStatus()
        speech = actions.speechStatus()
    }
    func manageMicrophone() async {
        guard !requestingMicrophone else { return }
        microphone = actions.microphoneStatus()
        if microphone == .notDetermined { _ = await requestMicrophoneIfNeeded() } else { open("Privacy_Microphone") }
    }
    func manageSpeech() async {
        guard !requestingSpeech else { return }
        speech = actions.speechStatus()
        if speech == .notDetermined { _ = await requestSpeechIfNeeded() } else { open("Privacy_SpeechRecognition") }
    }
    func requestMicrophoneIfNeeded() async -> Bool {
        if let microphoneTask { return await microphoneTask.value }
        microphone = actions.microphoneStatus()
        guard microphone == .notDetermined else { return microphone == .authorized }
        requestingMicrophone = true
        let task = Task {
            let granted = await actions.requestMicrophone()
            microphone = granted ? .authorized : actions.microphoneStatus()
            microphoneTask = nil
            requestingMicrophone = false
            return granted
        }
        microphoneTask = task
        return await task.value
    }
    func requestSpeechIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        if let speechTask { return await speechTask.value }
        speech = actions.speechStatus()
        guard speech == .notDetermined else { return speech }
        requestingSpeech = true
        let task = Task {
            speech = await actions.requestSpeech()
            speechTask = nil
            requestingSpeech = false
            return speech
        }
        speechTask = task
        return await task.value
    }
    func refresh() {
        refreshMediaPermissions()
        guard accessibilityTask == nil else { return }
        Task { await refreshAccessibility() }
    }
    func refreshMediaPermissions() {
        let microphone = actions.microphoneStatus()
        let speech = actions.speechStatus()
        if self.microphone != microphone { self.microphone = microphone }
        if self.speech != speech { self.speech = speech }
    }
    func refreshAccessibility() async {
        if let accessibilityTask {
            await accessibilityTask.value
            return
        }
        let task = Task {
            if let result = await actions.probeAccessibility() {
                accessibility = result.trusted && result.canPostEvents ? .authorized : .notGranted
            } else {
                accessibility = .unavailable
            }
            accessibilityTask = nil
        }
        accessibilityTask = task
        await task.value
    }
    func open(_ pane: String) { actions.openPane(pane) }
    var microphoneLabel: String {
        switch microphone {
        case .authorized: return "已授权"
        case .notDetermined: return "未申请"
        case .denied: return "已拒绝"
        case .restricted: return "系统限制"
        @unknown default: return "未知状态"
        }
    }
    var speechLabel: String {
        switch speech {
        case .authorized: return "已授权"
        case .notDetermined: return "未申请"
        case .denied: return "已拒绝"
        case .restricted: return "系统限制"
        @unknown default: return "未知状态"
        }
    }
}
