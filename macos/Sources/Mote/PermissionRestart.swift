// 等授权期间守着自己被系统结束：屏幕录制的「退出并重新打开」会把进程杀掉且不再拉起，
// 这里预埋一个脱离进程的看护脚本，等 Mote 消失后再把它打开一次。
// 不处理：用户主动退出、正常关闭引导窗——这两种情况会先撤掉标记，看护脚本不会动作。
import AppKit

enum PermissionRestart {
    /// 标记文件在就先授权、后退出之间做凭据；只有授权流程会写它。
    private static var markerURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mote-permission-restart")
    }

    private static var isArmed = false

    static func arm() {
        guard !isArmed else { return }
        isArmed = true
        let marker = markerURL.path
        try? Data().write(to: markerURL)

        let bundle = Bundle.main.bundlePath
        // 每 2 秒探一次，最长 10 分钟；进程消失才重新打开，避免多开
        let script = """
        i=0
        while [ $i -lt 300 ]; do
            sleep 2
            i=$((i+1))
            pgrep -x Mote >/dev/null || break
        done
        if [ -f "\(marker)" ] && ! pgrep -x Mote >/dev/null; then
            rm -f "\(marker)"
            open -a "\(bundle)"
        fi
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            isArmed = false
            try? FileManager.default.removeItem(at: markerURL)
        }
    }

    static func disarm() {
        guard isArmed else { return }
        isArmed = false
        try? FileManager.default.removeItem(at: markerURL)
    }
}
