import AVFoundation

/// Decode the recording before recognition; retained original audio is never changed.
enum SpeechAudio {
    struct Prepared {
        let buffer: AVAudioPCMBuffer
        let duration: Double
        let rmsDB: Double
        let peakDB: Double
    }
    static func prepare(_ url: URL) throws -> Prepared {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0, file.length <= AVAudioFramePosition(file.processingFormat.sampleRate * 180),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw failure("录音文件没有有效音频帧，或长度异常；请检查输入设备")
        }
        try file.read(into: source)
        guard source.frameLength > 0, let channels = source.floatChannelData else { throw failure("录音文件无法解码") }
        let count = Int(source.frameLength), channelCount = Int(source.format.channelCount)
        var squares = 0.0, peak = 0.0
        for c in 0..<channelCount {
            for i in 0..<count {
                let sample = Double(channels[c][i]); squares += sample * sample; peak = max(peak, abs(sample))
            }
        }
        let rms = sqrt(squares / Double(count * channelCount))
        // A modest gain on quiet files assists the fallback recognizer. Do not
        // discard quiet speech or trim any samples using a silence threshold.
        let gain = Float(min(4, max(1, 0.035 / max(rms, 0.000001))))
        let padding = AVAudioFrameCount(source.format.sampleRate * 0.2)
        guard let padded = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength + padding * 2),
              let output = padded.floatChannelData else { throw failure("无法准备识别音频") }
        padded.frameLength = padded.frameCapacity
        for c in 0..<channelCount {
            output[c].initialize(repeating: 0, count: Int(padded.frameLength))
            for i in 0..<count { output[c][i + Int(padding)] = max(-0.98, min(0.98, channels[c][i] * gain)) }
        }
        return Prepared(buffer: padded, duration: Double(count) / source.format.sampleRate,
                        rmsDB: 20 * log10(max(rms, 0.00000001)), peakDB: 20 * log10(max(peak, 0.00000001)))
    }
    static func isNoSpeech(_ error: Error) -> Bool {
        let e = error as NSError
        return e.code == 1110 || e.localizedDescription.lowercased().contains("no speech")
    }
}
