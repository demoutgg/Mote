// 首次启动引导：说明快捷键、授权和配置步骤；不处理翻译本身。
import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: SettingsStore
    var onOpenSettings: () -> Void
    var onFinish: () -> Void

    @State private var axGranted = SelectionReader.hasAccessibilityPermission
    @State private var screenGranted = OCREngine.hasScreenPermission
    private let permissionTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)

                VStack(spacing: 6) {
                    Text("欢迎使用 Mote")
                        .font(.system(size: 22, weight: .semibold))
                    Text("选中文本或框选屏幕区域，按快捷键得到 AI 翻译。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            VStack(spacing: 14) {
                step(
                    number: 1,
                    title: "授予必要权限",
                    detail: "选中翻译需要辅助功能；截图翻译需要屏幕录制，授权后可能需要重启 Mote。",
                    status: axGranted && screenGranted ? "已完成" : "待授权",
                    statusColor: axGranted && screenGranted ? .green : .orange
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if !axGranted {
                            Button("辅助功能") {
                                SelectionReader.requestAccessibilityPermission()
                            }
                            .buttonStyle(.link)
                        }
                        if !screenGranted {
                            Button("屏幕录制") {
                                OCREngine.requestScreenPermission()
                            }
                            .buttonStyle(.link)
                        }
                        if axGranted && screenGranted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Button("重新检查") {
                            refreshPermissions()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                    }
                }

                step(
                    number: 2,
                    title: "配置翻译服务",
                    detail: "支持 OpenAI 兼容接口与百度翻译，可同时启用多个服务。"
                ) {
                    Button("打开设置") {
                        onOpenSettings()
                    }
                    .buttonStyle(.link)
                }

                step(
                    number: 3,
                    title: "开始使用",
                    detail: "⌥D 选中翻译 · ⌥S 截图翻译\n⌥A 输入 · ⌥V 剪贴 · ⇧⌥S 截图 OCR",
                    accessory: { EmptyView() }
                )
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            HStack(spacing: 12) {
                Text("API Key 只保存在本机钥匙串，翻译历史不上传。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("稍后再说") {
                    onFinish()
                }
                Button("开始使用") {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 540, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(permissionTimer) { _ in
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        axGranted = SelectionReader.hasAccessibilityPermission
        screenGranted = OCREngine.hasScreenPermission
    }

    private func step<Accessory: View>(
        number: Int,
        title: String,
        detail: String,
        status: String? = nil,
        statusColor: Color = .secondary,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    if let status {
                        Text(status)
                            .font(.system(size: 10))
                            .foregroundStyle(statusColor)
                    }
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            accessory()
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
