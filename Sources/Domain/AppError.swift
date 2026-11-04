import Foundation

func failure(_ message: String) -> NSError {
    NSError(domain: "RimeVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
