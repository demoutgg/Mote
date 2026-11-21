// 生成 AppIcon.icns：渐变圆角底 + 白色“译”字，不依赖外部素材。
import AppKit
import CoreGraphics

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")

try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

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

    let colors = [
        CGColor(srgbRed: 0.29, green: 0.48, blue: 1.00, alpha: 1),
        CGColor(srgbRed: 0.55, green: 0.35, blue: 0.96, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
    context.fillEllipse(in: CGRect(
        x: rect.minX - rect.width * 0.25,
        y: rect.midY,
        width: rect.width * 0.95,
        height: rect.width * 0.95
    ))
    context.restoreGState()

    // 参考 Bob 的对话气泡轮廓：白色气泡 + 深蓝字形，缩小后仍可辨认。
    let bubbleRect = CGRect(
        x: size * 0.20,
        y: size * 0.28,
        width: size * 0.60,
        height: size * 0.45
    )
    let bubbleRadius = size * 0.13
    let bubble = CGMutablePath()
    bubble.addRoundedRect(
        in: bubbleRect,
        cornerWidth: bubbleRadius,
        cornerHeight: bubbleRadius
    )
    bubble.move(to: CGPoint(x: size * 0.31, y: size * 0.30))
    bubble.addLine(to: CGPoint(x: size * 0.27, y: size * 0.17))
    bubble.addLine(to: CGPoint(x: size * 0.43, y: size * 0.30))
    bubble.closeSubpath()

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.035,
        color: CGColor(srgbRed: 0.10, green: 0.16, blue: 0.45, alpha: 0.30)
    )
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.addPath(bubble)
    context.fillPath()
    context.restoreGState()

    let font = NSFont(name: "PingFangSC-Semibold", size: size * 0.255)
        ?? NSFont.systemFont(ofSize: size * 0.255, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 0.20, green: 0.30, blue: 0.82, alpha: 1),
    ]
    let text = "译" as NSString
    let textSize = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(
            x: bubbleRect.midX - textSize.width / 2,
            y: bubbleRect.midY - textSize.height / 2 + size * 0.008
        ),
        withAttributes: attributes
    )

    // 右上角两点高光，呼应 AI 的轻盈感。
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92))
    context.fillEllipse(in: CGRect(
        x: size * 0.775,
        y: size * 0.745,
        width: size * 0.030,
        height: size * 0.030
    ))
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55))
    context.fillEllipse(in: CGRect(
        x: size * 0.825,
        y: size * 0.685,
        width: size * 0.018,
        height: size * 0.018
    ))

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
        throw NSError(domain: "LingoliteIcon", code: 1)
    }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "LingoliteIcon", code: 2)
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
