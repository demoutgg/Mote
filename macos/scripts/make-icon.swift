// 生成 AppIcon.icns：深色科技风 + 小幽灵吉祥物 + sparkles，不依赖外部素材。
import AppKit
import CoreGraphics

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")

try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

let backgroundTop = NSColor(srgbRed: 0.035, green: 0.055, blue: 0.14, alpha: 1)
let backgroundBottom = NSColor(srgbRed: 0.09, green: 0.13, blue: 0.32, alpha: 1)
let bodyColor = NSColor(srgbRed: 0.92, green: 0.96, blue: 1.0, alpha: 1)
let rimColor = NSColor(srgbRed: 0.42, green: 0.72, blue: 1.0, alpha: 0.9)
let inkColor = NSColor(srgbRed: 0.035, green: 0.06, blue: 0.16, alpha: 1)
let neon = NSColor(srgbRed: 0.35, green: 0.78, blue: 1.0, alpha: 1)
let blushColor = NSColor(srgbRed: 1.0, green: 0.44, blue: 0.76, alpha: 0.55)

func starPath(center: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
    let path = CGMutablePath()
    for index in 0..<8 {
        let angle = CGFloat(index) * .pi / 4 - .pi / 2
        let radius = index.isMultiple(of: 2) ? outer : inner
        let p = CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
        if index == 0 {
            path.move(to: p)
        } else {
            path.addLine(to: p)
        }
    }
    path.closeSubpath()
    return path
}

func ghostPath(size: CGFloat) -> CGPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * size, y: y * size)
    }
    let path = CGMutablePath()
    path.move(to: p(0.21, 0.35))
    path.addCurve(to: p(0.50, 0.83), control1: p(0.21, 0.69), control2: p(0.33, 0.83))
    path.addCurve(to: p(0.79, 0.35), control1: p(0.67, 0.83), control2: p(0.79, 0.69))
    path.addLine(to: p(0.79, 0.30))
    path.addQuadCurve(to: p(0.675, 0.30), control: p(0.7325, 0.205))
    path.addQuadCurve(to: p(0.56, 0.30), control: p(0.6175, 0.395))
    path.addQuadCurve(to: p(0.445, 0.30), control: p(0.5025, 0.205))
    path.addQuadCurve(to: p(0.33, 0.30), control: p(0.3875, 0.395))
    path.addQuadCurve(to: p(0.21, 0.30), control: p(0.27, 0.205))
    path.closeSubpath()
    return path
}

func render(pixels: Int) -> NSImage {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let inset = size * 0.085
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let shape = CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )

    context.saveGState()
    context.addPath(shape)
    context.clip()

    let background = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [backgroundTop.cgColor, backgroundBottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    // 科技网格
    context.setStrokeColor(neon.withAlphaComponent(0.075).cgColor)
    context.setLineWidth(max(size * 0.0012, 0.6))
    let step = size / 12
    var line = rect.minX + step
    while line < rect.maxX {
        context.move(to: CGPoint(x: line, y: rect.minY))
        context.addLine(to: CGPoint(x: line, y: rect.maxY))
        line += step
    }
    var row = rect.minY + step
    while row < rect.maxY {
        context.move(to: CGPoint(x: rect.minX, y: row))
        context.addLine(to: CGPoint(x: rect.maxX, y: row))
        row += step
    }
    context.strokePath()

    let aura = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            neon.withAlphaComponent(0.30).cgColor,
            neon.withAlphaComponent(0).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        aura,
        startCenter: CGPoint(x: size * 0.50, y: size * 0.55),
        startRadius: 0,
        endCenter: CGPoint(x: size * 0.50, y: size * 0.55),
        endRadius: size * 0.42,
        options: []
    )
    context.restoreGState()

    // 幽灵本体
    let ghost = ghostPath(size: size)
    context.saveGState()
    context.setShadow(
        offset: .zero,
        blur: size * 0.045,
        color: neon.withAlphaComponent(0.45).cgColor
    )
    context.setFillColor(bodyColor.cgColor)
    context.addPath(ghost)
    context.fillPath()
    context.restoreGState()

    context.setStrokeColor(rimColor.cgColor)
    context.setLineWidth(size * 0.008)
    context.addPath(ghost)
    context.strokePath()

    // 小手臂
    context.setFillColor(bodyColor.cgColor)
    context.fillEllipse(in: CGRect(
        x: size * 0.155, y: size * 0.38,
        width: size * 0.11, height: size * 0.15
    ))
    context.fillEllipse(in: CGRect(
        x: size * 0.735, y: size * 0.38,
        width: size * 0.11, height: size * 0.15
    ))

    // 眼睛
    context.setFillColor(inkColor.cgColor)
    for centerX in [0.415, 0.585] {
        let eyeRadius = size * 0.028
        context.fillEllipse(in: CGRect(
            x: size * centerX - eyeRadius,
            y: size * 0.555 - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2
        ))
    }

    context.setFillColor(NSColor.white.cgColor)
    for centerX in [0.407, 0.577] {
        context.fillEllipse(in: CGRect(
            x: size * centerX,
            y: size * 0.570,
            width: size * 0.011,
            height: size * 0.011
        ))
    }

    // 腮红
    context.setFillColor(blushColor.cgColor)
    for centerX in [0.315, 0.685] {
        context.fillEllipse(in: CGRect(
            x: size * centerX - size * 0.035,
            y: size * 0.485,
            width: size * 0.070,
            height: size * 0.036
        ))
    }

    // 微笑
    context.setStrokeColor(inkColor.cgColor)
    context.setLineWidth(size * 0.012)
    context.setLineCap(.round)
    context.addArc(
        center: CGPoint(x: size * 0.50, y: size * 0.505),
        radius: size * 0.050,
        startAngle: 205 * .pi / 180,
        endAngle: 335 * .pi / 180,
        clockwise: false
    )
    context.strokePath()

    // sparkles：顶部主星 + 两侧小星
    let white = NSColor.white
    context.saveGState()
    context.setShadow(
        offset: .zero,
        blur: size * 0.030,
        color: neon.withAlphaComponent(0.65).cgColor
    )
    context.setFillColor(white.cgColor)
    context.addPath(starPath(
        center: CGPoint(x: size * 0.50, y: size * 0.872),
        outer: size * 0.038,
        inner: size * 0.013
    ))
    context.fillPath()
    context.restoreGState()

    context.setFillColor(neon.cgColor)
    context.addPath(starPath(
        center: CGPoint(x: size * 0.165, y: size * 0.73),
        outer: size * 0.042,
        inner: size * 0.014
    ))
    context.fillPath()

    context.setFillColor(white.withAlphaComponent(0.85).cgColor)
    context.addPath(starPath(
        center: CGPoint(x: size * 0.845, y: size * 0.70),
        outer: size * 0.030,
        inner: size * 0.010
    ))
    context.fillPath()

    image.unlockFocus()
    return image
}

func writePNG(pixels: Int, name: String) throws {
    let image = render(pixels: pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "MoteIcon", code: 1)
    }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MoteIcon", code: 2)
    }
    try data.write(to: iconset.appendingPathComponent(name))
}

let variants: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (pixels, name) in variants {
    try writePNG(pixels: pixels, name: name)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}
print("Generated \(output.path)")
