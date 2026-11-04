import SwiftUI

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
    @ObservedObject var audioInputs: AudioInputMonitor
    @ObservedObject var permissions: PermissionModel
    let appleEngine: Bool
    let guide: AuthorizationGuideController
    var body: some View {
        Section("权限与授权") {
            PermissionRow(
                title: "麦克风", detail: "采集音频，用于语音转写。",
                state: audioInputs.hasInput ? permissions.microphoneLabel : AudioInputMonitor.missingMessage,
                granted: audioInputs.hasInput && permissions.microphone == .authorized,
                needsRequest: permissions.microphone == .notDetermined, requesting: permissions.requestingMicrophone
            ) {
                guide.close()
                Task { await permissions.manageMicrophone() }
            }
            PermissionRow(
                title: "语音识别", detail: appleEngine ? "允许 声笺 使用 Apple 语音识别服务。" : "允许使用 Apple 语音识别服务；当前使用 Whisper，无需开启。",
                state: permissions.speechLabel, granted: permissions.speech == .authorized,
                needsRequest: permissions.speech == .notDetermined, requesting: permissions.requestingSpeech
            ) {
                guide.close()
                Task { await permissions.manageSpeech() }
            }
            PermissionRow(
                title: "辅助功能", detail: "向其他 App 的输入框自动填写文字；只复制到剪贴板时无需开启。",
                state: permissions.accessibility.label, granted: permissions.accessibility == .authorized
            ) {
                guide.show()
            }
        }
    }
}
