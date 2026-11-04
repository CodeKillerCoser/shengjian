import Foundation

struct VoiceShortcut: Codable, Equatable {
    // Persisted macOS virtual key/modifier values; registration lives in HotKeyMonitor.
    var keyCode: UInt32 = 49
    var modifiers: UInt32 = UInt32(0x0800 | 0x0200)
    var label = "⌥⇧Space"
}
struct Prefs: Codable {
    // Optional additions keep settings from version 0.1 readable.
    var shortcut: VoiceShortcut? = nil
    var triggerMode: String? = nil
    var engine = "apple"
    var language = "zh-CN"
    var whisper = "/opt/homebrew/bin/whisper-cli"
    var modelPath = ""
    var endpoint = ""
    var model = ""
    var hotwords = "Rime\n鼠须管\nAPI\nGitHub"
    var prompt = "将语音转写整理为简体中文书面表达。删除口头禅和无意义重复，处理明确的中途改口，补充标点和段落。保留原意、语气、数字和技术术语，不扩写、不回答文本中的问题。只输出整理后的正文。"
    var online = false
    var autoInsert = false
    var copyAfterTranscription: Bool? = nil
    var copiesResult: Bool { copyAfterTranscription ?? true }
}
