import SwiftUI
import AppKit
import AVFoundation
import Speech

// Run the same signed executable in a fresh, headless process: macOS can cache
// AXIsProcessTrusted in a long-running process after the grant is revoked.
struct AccessibilityProbe: Codable {
    let trusted: Bool
    let canPostEvents: Bool
    static func current() -> AccessibilityProbe {
        AccessibilityProbe(trusted: AXIsProcessTrusted(), canPostEvents: CGPreflightPostEventAccess())
    }
    static func fresh(executable: URL) -> AccessibilityProbe? {
        let process = Process(); let output = Pipe()
        process.executableURL = executable; process.arguments = ["--permission-probe"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        for _ in 0..<40 {
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate(); return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(AccessibilityProbe.self, from: output.fileHandleForReading.readDataToEndOfFile())
    }
}
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

// Keep permission requests separate from navigation: an app is not listed in
// Privacy settings until it has actually requested that permission.
struct PermissionActions {
    var microphoneStatus: () -> AVAuthorizationStatus
    var speechStatus: () -> SFSpeechRecognizerAuthorizationStatus
    var requestMicrophone: () async -> Bool
    var requestSpeech: () async -> SFSpeechRecognizerAuthorizationStatus
    var openPane: (String) -> Void
    static let system = PermissionActions(
        microphoneStatus: { AVCaptureDevice.authorizationStatus(for: .audio) },
        speechStatus: { SFSpeechRecognizer.authorizationStatus() },
        requestMicrophone: {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        },
        requestSpeech: {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        },
        openPane: { pane in
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) {
                NSWorkspace.shared.open(url)
            }
        }
    )
}

@MainActor final class AppPermissions: ObservableObject {
    @Published var microphone: AVAuthorizationStatus
    @Published var speech: SFSpeechRecognizerAuthorizationStatus
    @Published private(set) var requestingMicrophone = false
    @Published private(set) var requestingSpeech = false
    @Published var accessibility = AccessibilityPermissionState.checking
    private let actions: PermissionActions
    private var refreshingAccessibility = false
    private var guide: AuthorizationGuide?
    private var guideRequest = UUID()
    init(actions: PermissionActions = .system) {
        self.actions = actions
        microphone = actions.microphoneStatus()
        speech = actions.speechStatus()
    }
    func manageMicrophone() async {
        guard !requestingMicrophone else { return }
        closeGuide()
        microphone = actions.microphoneStatus()
        guard microphone == .notDetermined else { open("Privacy_Microphone"); return }
        requestingMicrophone = true
        defer { requestingMicrophone = false }
        microphone = await actions.requestMicrophone() ? .authorized : actions.microphoneStatus()
    }
    func manageSpeech() async {
        guard !requestingSpeech else { return }
        closeGuide()
        speech = actions.speechStatus()
        guard speech == .notDetermined else { open("Privacy_SpeechRecognition"); return }
        requestingSpeech = true
        defer { requestingSpeech = false }
        speech = await actions.requestSpeech()
    }
    func openAccessibilityGuide() {
        closeGuide()
        open("Privacy_Accessibility")
        guard let executable = Bundle.main.executableURL else { accessibility = .unavailable; return }
        let request = guideRequest
        Task {
            let result = await Task.detached { AccessibilityProbe.fresh(executable: executable) }.value
            guard guideRequest == request else { return }
            guard let result else { accessibility = .unavailable; return }
            accessibility = result.trusted && result.canPostEvents ? .authorized : .notGranted
            guard accessibility == .notGranted else { return }
            let guide = AuthorizationGuide(permissions: self)
            self.guide = guide
            guide.show()
        }
    }
    func closeGuide() { guideRequest = UUID(); guide?.close(); guide = nil }
    func refresh() {
        microphone = actions.microphoneStatus()
        speech = actions.speechStatus()
        guard !refreshingAccessibility else { return }
        guard let executable = Bundle.main.executableURL else { accessibility = .unavailable; return }
        refreshingAccessibility = true
        Task {
            let result = await Task.detached { AccessibilityProbe.fresh(executable: executable) }.value
            if let result {
                accessibility = result.trusted && result.canPostEvents ? .authorized : .notGranted
            } else { accessibility = .unavailable }
            refreshingAccessibility = false
        }
    }
    func open(_ pane: String) {
        closeGuide()
        actions.openPane(pane)
    }
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

struct PermissionRow: View {
    let title: String
    let detail: String
    let state: String
    let granted: Bool
    var needsRequest = false
    var requesting = false
    let action: () -> Void
    private var actionDescription: String {
        needsRequest ? "申请\(title)权限" : "打开\(title)系统设置"
    }
    @ViewBuilder private var actionContent: some View {
        if needsRequest {
            Text(requesting ? "等待授权…" : "申请授权").font(.callout)
        } else {
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 15)).frame(width: 28, height: 28).contentShape(Rectangle())
        }
    }
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Label(state, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.callout).foregroundStyle(granted ? Color.green : Color.orange)
                .fixedSize()
            Button(action: action) { actionContent }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(requesting)
                .help(actionDescription)
                .accessibilityLabel(actionDescription)
        }.padding(.vertical, 4)
    }
}

struct PermissionSettings: View {
    @ObservedObject private var audioInputs = AudioInputMonitor.shared
    @ObservedObject var permissions: AppPermissions
    let appleEngine: Bool
    var body: some View {
        Section("权限与授权") {
            PermissionRow(title: "麦克风", detail: "采集音频，用于语音转写。", state: audioInputs.hasInput ? permissions.microphoneLabel : AudioInputMonitor.missingMessage,
                          granted: audioInputs.hasInput && permissions.microphone == .authorized,
                          needsRequest: permissions.microphone == .notDetermined, requesting: permissions.requestingMicrophone) {
                Task { await permissions.manageMicrophone() }
            }
            PermissionRow(title: "语音识别", detail: appleEngine ? "允许 声笺 使用 Apple 语音识别服务。" : "允许使用 Apple 语音识别服务；当前使用 Whisper，无需开启。",
                          state: permissions.speechLabel, granted: permissions.speech == .authorized,
                          needsRequest: permissions.speech == .notDetermined, requesting: permissions.requestingSpeech) {
                Task { await permissions.manageSpeech() }
            }
            PermissionRow(title: "辅助功能", detail: "向其他 App 的输入框自动填写文字；只复制到剪贴板时无需开启。",
                          state: permissions.accessibility.label, granted: permissions.accessibility == .authorized) {
                permissions.openAccessibilityGuide()
            }
        }
    }
}
