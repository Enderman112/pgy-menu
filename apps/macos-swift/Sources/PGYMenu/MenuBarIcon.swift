import AppKit

/// 菜单栏信号图标：五格信号柱，模板图（自动适配深浅色菜单栏）。
enum MenuBarIcon {
    static let size = NSSize(width: 19, height: 15)

    static func make(bars: Int, connected: Bool, known: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            let count = max(0, min(5, bars))
            let barWidth: CGFloat = 2.6
            let gap: CGFloat = 1.15
            let heights: [CGFloat] = [4, 6.5, 9, 11.5, 14]
            let totalWidth = barWidth * 5 + gap * 4
            let originX = (19 - totalWidth) / 2
            let baseY: CGFloat = 0.5

            for index in 0..<5 {
                let rect = NSRect(
                    x: originX + CGFloat(index) * (barWidth + gap),
                    y: baseY,
                    width: barWidth,
                    height: heights[index]
                )
                let path = NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8)
                let on = index < count
                let alpha: CGFloat
                if !known {
                    alpha = 0.25
                } else if on {
                    alpha = 1.0
                } else {
                    alpha = 0.28
                }
                NSColor.black.withAlphaComponent(alpha).setFill()
                path.fill()
            }

            // 未连接时在右下角点一个点，表示“有信号但没拨号”
            if known && !connected && count > 0 {
                let dot = NSRect(x: 16.4, y: 0.2, width: 2.2, height: 2.2)
                NSColor.black.withAlphaComponent(0.55).setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
