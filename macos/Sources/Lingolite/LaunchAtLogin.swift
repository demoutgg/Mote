// 登录项：写入用户 LaunchAgents plist，下次登录时自动启动；不做系统级安装。
import Foundation

enum LaunchAtLogin {
    private static let label = "com.demoutgg.lingolite"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func set(_ enabled: Bool) throws {
        let manager = FileManager.default
        if enabled {
            let executable = Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS/Lingolite")
                .path
            let directory = plistURL.deletingLastPathComponent()
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)

            let contents: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable],
                "RunAtLoad": true,
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: contents,
                format: .xml,
                options: 0
            )
            try data.write(to: plistURL, options: .atomic)
        } else if manager.fileExists(atPath: plistURL.path) {
            try manager.removeItem(at: plistURL)
        }
    }
}
