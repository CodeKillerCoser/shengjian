import Combine

// Recording and history processing share audio resources. One explicit phase
// makes their existing mutual exclusion visible to every feature.
@MainActor final class ActivityState: ObservableObject {
    enum Phase { case idle, preparingRecording, recording, processing }
    @Published var phase: Phase = .idle
    var recording: Bool { phase == .recording }
    var busy: Bool { phase == .preparingRecording || phase == .processing }
    var idle: Bool { phase == .idle }
}
