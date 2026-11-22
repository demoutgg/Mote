// 权限探测：借 MoteOCR 子进程查询真实授权状态；不负责发起授权请求和引导界面。
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// 主进程内的 AXIsProcessTrusted / CGPreflightScreenCaptureAccess 都按进程缓存，
/// 用户刚在系统设置里勾选时读到的还是旧值；子进程每次都是全新进程，能读到当前状态。
/// 窗口标题之类的旁证不能用：新版 macOS 无权限时也返回带标题的窗口。
enum PermissionProbe {
    private static let cacheLifetime: TimeInterval = 0.8
    private static let lock = NSLock()
    private static var cache: (accessibility: Bool, screen: Bool, at: Date)?
    private static var refreshing = false

    static func accessibility() -> Bool {
        // 主进程已判定为真就不必再起子进程
        if AXIsProcessTrusted() { return true }
        return current().accessibility
    }

    static func screen() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return current().screen
    }

    /// 轮询期间后台刷新，避免每次 40ms 的子进程查询都卡在主线程
    static func refreshInBackground() {
        lock.lock()
        let cached = cache
        let isFresh = cached.map { Date().timeIntervalSince($0.at) < cacheLifetime } ?? false
        if refreshing || isFresh {
            lock.unlock()
            return
        }
        refreshing = true
        lock.unlock()

        DispatchQueue.global(qos: .utility).async {
            let fresh = queryHelper() ?? (false, false)
            lock.lock()
            cache = (fresh.accessibility, fresh.screen, Date())
            refreshing = false
            lock.unlock()
        }
    }

    private static func current() -> (accessibility: Bool, screen: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let cache, Date().timeIntervalSince(cache.at) < cacheLifetime {
            return (cache.accessibility, cache.screen)
        }
        // 后台正在刷新时先给旧值，避免同一轮里起两个子进程
        if refreshing {
            guard let cache else { return (false, false) }
            return (cache.accessibility, cache.screen)
        }
        let fresh = queryHelper() ?? (false, false)
        cache = (fresh.accessibility, fresh.screen, Date())
        return fresh
    }

    private static func queryHelper() -> (accessibility: Bool, screen: Bool)? {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "MoteOCR") else { return nil }
        let process = Process()
        process.executableURL = url
        process.arguments = ["--permissions"]
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return (text.contains("ax=1"), text.contains("screen=1"))
    }
}
