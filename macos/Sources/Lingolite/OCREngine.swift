// 区域 OCR：按指定屏幕坐标截图，再用 Vision 识别中英文；不处理选区界面和翻译。
import AppKit
import CoreGraphics
import Vision

enum OCREngine {
    enum OCRError: LocalizedError {
        case cancelled
        case empty
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "已取消截图。"
            case .empty:
                return "没有识别到文字，请换一个区域再试。"
            case let .failed(message):
                return message
            }
        }
    }

    static var hasScreenPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func capture(rect: CGRect, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lingolite-ocr-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: url) }

            // 等遮罩完全消失，避免把选框画进截图。
            usleep(120_000)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = [
                "-x",
                "-R",
                "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))",
                url.path,
            ]
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(OCRError.failed("无法启动截图：\(error.localizedDescription)")))
                }
                return
            }
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: url.path) else {
                DispatchQueue.main.async { completion(.failure(OCRError.cancelled)) }
                return
            }

            do {
                let text = try recognize(url: url)
                DispatchQueue.main.async { completion(.success(text)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func recognize(url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        try VNImageRequestHandler(url: url, options: [:]).perform([request])

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

        guard !text.isEmpty else { throw OCRError.empty }
        return text
    }
}
