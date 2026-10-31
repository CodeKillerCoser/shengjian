import CoreAudio
import SwiftUI

@MainActor final class AudioInputMonitor: ObservableObject {
    static let shared = AudioInputMonitor()
    static let missingMessage = "未检测到语音输入设备"
    @Published private(set) var hasInput: Bool = false
    private let probe: () -> Bool
    private var subscriptions: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(probe: @escaping () -> Bool = AudioInputMonitor.detectInput, subscribe: Bool = true) {
        self.probe = probe
        // Subscribe before probing so an attachment during launch cannot be missed.
        if subscribe {
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    Task { @MainActor in self?.deviceConfigurationChanged() }
                }
                if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
                    subscriptions.append((address, listener))
                }
            }
        }
        deviceConfigurationChanged()
    }
    func deviceConfigurationChanged() { hasInput = probe() }
    deinit {
        for (var address, listener) in subscriptions {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }
    nonisolated static func detectInput() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = devices.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return false }
        return devices.contains { device in
            var configuration = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &configuration, 0, nil, &bytes) == noErr, bytes >= MemoryLayout<AudioBufferList>.size else { return false }
            let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { storage.deallocate() }
            guard AudioObjectGetPropertyData(device, &configuration, 0, nil, &bytes, storage) == noErr else { return false }
            let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
            return buffers.contains { $0.mNumberChannels > 0 }
        }
    }
}
