# Lingolite

轻量、原生的跨平台 AI 划词翻译工具。选中文本，按快捷键，在鼠标附近得到流式翻译。

## 状态

v0.1 开发中。macOS 优先，Windows 随后跟进。

## 目标

- 原生实现，不用 Electron
- 自己填 API Key，兼容 OpenAI Chat Completions 接口
- 默认本地存储，不上传历史，不收集遥测
- macOS：菜单栏应用，无 Dock 图标
- Windows：托盘应用，无主窗口常驻
- 后续支持截图 OCR（v0.2）

## 技术栈

- macOS：Swift 6 + AppKit/SwiftUI + Vision
- Windows：C++20 + Win32 + WinRT OCR
- 共享：JSON 配置格式、Prompt 规范、API 协议

## macOS 开发

要求 macOS 13+、Swift 6。

```bash
cd macos
./scripts/install.sh   # 构建并安装到 /Applications

# 只打包、不安装：
./scripts/build-app.sh && open dist/Lingolite.app
```

首次使用需要在“系统设置 → 隐私与安全性 → 辅助功能”中授权 Lingolite，否则划词捕获会回退到模拟复制。

默认快捷键：`⌥L`（Option + L）。

说明：本地构建使用 ad-hoc 签名，重新编译后系统会把它当成新应用，可能需要重新勾选辅助功能权限。正式分发前会换成 Developer ID 签名。

## 配置

菜单栏图标 → Settings：

- Endpoint：支持完整 `/v1/chat/completions` 地址，也支持只填 base URL
- API Key：macOS Keychain / Windows Credential Manager
- Model：例如 `gpt-4o-mini`、`deepseek-chat`、`qwen-plus`
- Target language 与 System prompt

API Key 不写入 JSON，也不会出现在导出的配置里。

设置页提供 OpenAI、DeepSeek、Ollama、LM Studio 的快速填充，以及直接测试连通性的按钮。

## Roadmap

- v0.1：macOS 划词翻译、手动输入、Keychain、流式输出
- v0.2：macOS 截图 OCR、历史记录、快捷键设置
- v0.3：Windows beta（托盘、热键、UIA 划词、WinRT OCR）
- v1.0：双端稳定版、签名分发、自动更新

## License

MIT

