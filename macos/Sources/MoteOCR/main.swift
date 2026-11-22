// Mote 的 OCR 子进程：读取截图、识别文字并输出到 stdout；不处理 UI 和翻译。
import Foundation
import ImageIO
import Vision

enum HelperError: LocalizedError {
    case missingImage
    case unreadableImage
    case emptyText

    var errorDescription: String? {
        switch self {
        case .missingImage:
            return "缺少截图文件"
        case .unreadableImage:
            return "无法读取截图"
        case .emptyText:
            return "没有识别到文字"
        }
    }
}

func recognize(path: String) throws -> String {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw HelperError.unreadableImage
    }

    // 限制最长边，避免超大 Retina 截图让 Vision 申请过多内存。
    let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 2400,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        thumbnailOptions as CFDictionary
    ) else {
        throw HelperError.unreadableImage
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["zh-Hans", "en-US"]

    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

    let observations = request.results ?? []
    let sorted = observations.sorted { first, second in
        let firstBox = first.boundingBox
        let secondBox = second.boundingBox
        if abs(firstBox.midY - secondBox.midY) > 0.015 {
            return firstBox.midY > secondBox.midY
        }
        return firstBox.minX < secondBox.minX
    }

    let text = sorted
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty else { throw HelperError.emptyText }
    return text
}

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("缺少截图文件".utf8))
    exit(2)
}

do {
    let text = try recognize(path: CommandLine.arguments[1])
    FileHandle.standardOutput.write(Data(text.utf8))
    exit(0)
} catch {
    FileHandle.standardError.write(Data(error.localizedDescription.utf8))
    exit(1)
}
