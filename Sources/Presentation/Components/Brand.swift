import AppKit

enum Brand {
    static let logo: NSImage = {
        guard let url = Bundle.main.url(forResource: "ShengjianLogo", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else { return NSImage() }
        return image
    }()
}
