# Mote for Windows

C++20 + Win32 的托盘应用，产物是单一 exe 加系统自带的 OCR 组件。

> **本版未经实机自测。** 代码在 macOS 上完成，依赖 WinRT/cppwinrt，无法在本机编译验证。如果构建或运行有问题，请提 issue 并附上报错原文。

## 功能

- 托盘图标与右键菜单（含「设置」「历史记录」「关于 Mote」）
- 全局热键（可在设置里重新录制）：
  - `Alt+A` 输入翻译
  - `Alt+D` 选中翻译（UI Automation，失败回退 Ctrl+C）
  - `Alt+V` 剪贴翻译
  - `Alt+S` 截图翻译
  - `Shift+Alt+S` 截图 OCR（识别后复制，不弹翻译窗）
- 悬浮窗：Enter 翻译、Ctrl+Enter 换行，失焦自动收起，尺寸可拖动调整并记住位置
- AI（OpenAI 兼容）与百度翻译可同时启用，流式输出
- AI 预设（OpenAI / DeepSeek / Ollama / LM Studio）与「获取模型」
- 系统提示词可修改，与内置一致时存空串
- 翻译完成后自动复制译文（可选）
- 设置窗口四个分页：通用 / 服务 / 翻译 / 历史
- API Key 保存在 Windows 凭据管理器
- 开机自动启动（HKCU Run，可在设置里开关）
- 最近 100 条本地历史，支持搜索、复制原文/译文、清空
- 截图框选 + WinRT `Windows.Media.Ocr` 识别

## 构建

需要 Visual Studio 2022（含 C++/WinRT 与 Windows SDK 10）与 CMake：

```powershell
cmake -S windows -B build -A x64
cmake --build build --config Release
```

产物在 `build\Release\Mote.exe`。也可以用 Visual Studio 直接打开 `windows\CMakeLists.txt`。

打包：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File windows/scripts/package.ps1 -Version 0.9.0
```

## 说明

- 截图 OCR 使用系统 OCR 语言包；没有对应语言包时会回退到配置的目标语言。
- 与 macOS 的差异：没有权限引导流程（Windows 读选区与截屏不需要单独授权），托盘图标固定。
