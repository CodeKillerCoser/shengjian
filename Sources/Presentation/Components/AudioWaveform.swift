import SwiftUI

struct AudioWaveform: View {
    let levels: [Float]
    let active: Bool
    var tint: Color = .teal
    var body: some View {
        Canvas { context, size in
            let count = min(levels.count, max(1, Int(size.width / 3)))
            let samples = Array(levels.suffix(count))
            let step = size.width / CGFloat(max(samples.count, 1))
            for (index, level) in samples.enumerated() {
                let height = max(3, CGFloat(level) * (size.height - 4))
                let rect = CGRect(
                    x: CGFloat(index) * step, y: (size.height - height) / 2, width: max(1, step * 0.55), height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 2), with: .color(active ? tint : .secondary.opacity(0.25)))
            }
        }
    }
}
