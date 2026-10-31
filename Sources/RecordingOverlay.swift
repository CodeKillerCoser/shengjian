import AppKit
import SwiftUI

final class PassiveRecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class RecordingOverlay {
    let panel: PassiveRecordingPanel
    init(voice: Voice) {
        panel = PassiveRecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: RecordingOverlayView(voice: voice))
    }
    func show(on screen: NSScreen?) {
        let visible = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 24))
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
}
enum OverlayGeometry {
    static let width: CGFloat = 240
    static let height: CGFloat = 44
    static let inset: CGFloat = 8
    static let radius: CGFloat = 12
    static let buttonRadius = radius - inset
    static let buttonSize: CGFloat = 28
}
@MainActor final class OverlayHoverState: ObservableObject {
    @Published var hovered = false
}
struct OverlayIconButton: View {
    let symbol: String
    let label: String
    var enabled = true
    let action: () -> Void
    @StateObject private var interaction = OverlayHoverState()
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: OverlayGeometry.buttonSize, height: OverlayGeometry.buttonSize)
                .contentShape(RoundedRectangle(cornerRadius: OverlayGeometry.buttonRadius))
        }
        .buttonStyle(OverlayIconButtonStyle(hovered: interaction.hovered && enabled))
        .disabled(!enabled)
        .onHover { interaction.hovered = $0 }
        .help(label).accessibilityLabel(label)
    }
}
struct OverlayIconButtonStyle: ButtonStyle {
    let hovered: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.primary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : (hovered ? 0.08 : 0)),
                        in: RoundedRectangle(cornerRadius: OverlayGeometry.buttonRadius))
    }
}
struct RecordingOverlayView: View {
    @ObservedObject var voice: Voice
    var body: some View {
        HStack(spacing: 8) {
            if voice.recording {
                AudioWaveform(levels: voice.levels, active: true,
                              tint: Color(red: 7.0/255, green: 143.0/255, blue: 150.0/255))
                    .frame(maxWidth: .infinity).frame(height: 24)
                    .accessibilityLabel("实时麦克风波形")
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Text(String(format: "%02d:%02d", Int(voice.elapsed) / 60, Int(voice.elapsed) % 60))
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                }.frame(width: 39)
            } else if voice.overlayPhase == "processing" {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("转写与整理中…").font(.system(size: 11))
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: voice.overlayPhase == "success" ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(voice.overlayPhase == "success" ? .teal : .orange)
                    Text(voice.overlayMessage).font(.system(size: 10)).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .help(voice.overlayMessage)
                    .onTapGesture { if voice.overlayPhase == "error" { voice.openMainWindow() } }
            }
            OverlayIconButton(symbol: "xmark", label: voice.recording ? "取消录音" : "关闭悬浮条并取消自动输入") {
                voice.closeOverlay()
            }
            OverlayIconButton(symbol: "checkmark", label: "确认录音并转写", enabled: voice.recording) {
                voice.stop()
            }.opacity(voice.recording ? 1 : 0.35)
        }
        .padding(OverlayGeometry.inset)
        .frame(width: OverlayGeometry.width, height: OverlayGeometry.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OverlayGeometry.radius))
        .overlay(RoundedRectangle(cornerRadius: OverlayGeometry.radius).stroke(.white.opacity(0.2)))
    }
}
