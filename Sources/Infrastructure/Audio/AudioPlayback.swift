import AVFoundation
import Combine

@MainActor final class AudioPlayback: ObservableObject {
    @Published private(set) var playingID: UUID?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    func play(_ url: URL, id: UUID) throws {
        if playingID == id {
            stop()
            return
        }
        stop()
        let player = try AVAudioPlayer(contentsOf: url)
        guard player.play() else { throw failure("音频无法播放") }
        self.player = player
        playingID = id
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.player?.isPlaying != true { self?.stop() } }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stop() {
        player?.stop()
        player = nil
        playingID = nil
        timer?.invalidate()
        timer = nil
    }
    deinit { timer?.invalidate() }
}
