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
        // CGPreflight 在刚勾选后是旧值，交给子进程查询；不能靠窗口标题探测，
        // 新版 macOS 无权限时也会返回带标题的窗口，会把未授权误判成已授权。
        PermissionProbe.screen()
    }

    /// 有屏幕录制权限时窗口标题才对其他进程可见，借此实时判断

    static func captureInteractive(completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mote-ocr-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: url) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", url.path]
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
            throw OCRError.failed("缺少 OCR 组件，请重新安装 Mote。")
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
        if let url = Bundle.main.url(forAuxiliaryExecutable: "MoteOCR") {
            return url
        }
        let fallback = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/MoteOCR")
        return FileManager.default.isExecutableFile(atPath: fallback.path) ? fallback : nil
    }
}
