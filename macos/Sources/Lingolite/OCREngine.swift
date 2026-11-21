// 区域 OCR：按屏幕坐标截图，再交给短生命周期子进程识别；主应用不加载 Vision。
import AppKit
import CoreGraphics

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
                let text = try recognizeWithHelper(url: url)
                DispatchQueue.main.async { completion(.success(text)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func recognizeWithHelper(url: URL) throws -> String {
        guard let helper = helperURL() else {
            throw OCRError.failed("缺少 OCR 组件，请重新安装 Lingolite。")
        }

        let process = Process()
        process.executableURL = helper
        process.arguments = [url.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw OCRError.failed("无法启动 OCR：\(error.localizedDescription)")
        }

        // 先读 stdout 到 EOF，避免大段文字填满管道造成死锁。
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw OCRError.failed(message.isEmpty ? "OCR 识别失败" : message)
        }

        let text = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw OCRError.empty }
        return text
    }

    private static func helperURL() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "LingoliteOCR") {
            return url
        }
        let fallback = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/LingoliteOCR")
        return FileManager.default.isExecutableFile(atPath: fallback.path) ? fallback : nil
    }
}
