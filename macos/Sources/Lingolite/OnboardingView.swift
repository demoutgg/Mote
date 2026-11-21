// 首次启动引导：说明快捷键、授权和配置步骤；不处理翻译本身。
import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: SettingsStore
    var onOpenSettings: () -> Void
    var onFinish: () -> Void

    @State private var permissionGranted = OCREngine.hasScreenPermission

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)

                VStack(spacing: 6) {
                    Text("欢迎使用 Lingolite")
                        .font(.system(size: 22, weight: .semibold))
                    Text("选中文本，按 ⌥L，在鼠标旁得到 AI 翻译。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            VStack(spacing: 14) {
                step(
                    number: 1,
                    title: "授予屏幕录制权限",
                    detail: permissionGranted ? "已授权，可以框选屏幕区域识别文字。" : "框选翻译需要读取屏幕内容；不授权仍可手动输入。",
                    status: permissionGranted ? "已授权" : "未授权",
                    statusColor: permissionGranted ? .green : .orange
                ) {
                    if !permissionGranted {
                        Button("去授权") {
                            OCREngine.requestScreenPermission()
                        }
                        .buttonStyle(.link)
                    }
                }

                step(
                    number: 2,
                    title: "配置翻译服务",
                    detail: "填自己的 API Key，支持 OpenAI、DeepSeek、Ollama 等兼容接口。"
                ) {
                    Button("打开设置") {
                        onOpenSettings()
                    }
                    .buttonStyle(.link)
                }

                step(
                    number: 3,
                    title: "开始使用",
                    detail: "⌥D 框选屏幕区域翻译；⌥A 输入翻译，⌥V 翻译剪贴板。",
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionGranted = OCREngine.hasScreenPermission
        }
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
