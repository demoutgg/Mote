// 视觉常量：字号、圆角、间距与语义色。只放取值，不承载布局或业务逻辑。
import AppKit

enum Theme {
    enum Font {
        static let caption = NSFont.systemFont(ofSize: 10)
        static let footnote = NSFont.systemFont(ofSize: 11)
        static let footnoteStrong = NSFont.systemFont(ofSize: 11, weight: .semibold)
        static let body = NSFont.systemFont(ofSize: 13)
        static let button = NSFont.systemFont(ofSize: 12, weight: .medium)
        static let bodyStrong = NSFont.systemFont(ofSize: 13, weight: .medium)
        static let title = NSFont.systemFont(ofSize: 15)
        static let large = NSFont.systemFont(ofSize: 17, weight: .semibold)
        static let section = NSFont.systemFont(ofSize: 12, weight: .semibold)
        static let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        static let monoDigits = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let card: CGFloat = 12
        static let popup: CGFloat = 16
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    /// 卡片填充：靠与窗口底色的明度差分层次，不再加描边。
    /// 深色下 controlBackgroundColor 比窗口底色更暗，会把卡片画成「洞」，改用略亮的固定值。
    static var cardFill: NSColor {
        dynamic(light: .controlBackgroundColor, dark: NSColor(calibratedWhite: 0.16, alpha: 1))
    }
    static var separator: NSColor { .separatorColor }

    /// 录入框底色：比卡片暗一档，不描边也能看出这里是可点的输入位
    static var wellFill: NSColor {
        dynamic(light: NSColor(white: 0.94, alpha: 1), dark: NSColor(white: 0.22, alpha: 1))
    }

    /// 深浅色各自取值：替换初始化时一次性固化到 layer 的 cgColor
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

/// 纯色填充视图：在 updateLayer 里取色，深浅色切换时才会跟着变
final class FillView: NSView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = cornerRadius > 0
        layer?.backgroundColor = fill.cgColor
    }
}

/// 1pt 分隔线：随深浅色外观重绘
final class SeparatorView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        wantsLayer = true
        layer?.backgroundColor = Theme.separator.cgColor
    }
}
