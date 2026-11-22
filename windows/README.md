# Mote for Windows

C++20 + Win32 的轻量客户端，产物是单一 exe 加 OCR 运行所需的系统组件。

## 已实现

- 托盘图标与右键菜单
- 全局热键：
  - `Alt+A` 输入翻译
  - `Alt+D` 选中翻译（UI Automation，失败回退 Ctrl+C）
  - `Alt+V` 剪贴翻译
  - `Alt+S` 截图翻译
  - `Shift+Alt+S` 截图 OCR（识别后复制，不弹翻译窗）
- 鼠标附近/居中偏上的悬浮窗，Enter 翻译、Ctrl+Enter 换行
- AI（OpenAI 兼容）与百度翻译可同时启用
- 设置窗口，API Key 保存在 Windows 凭据管理器
- 开机自动启动（HKCU Run，可在设置里开关）
- 最近 100 条本地历史，支持复制与清空
- 截图框选 + WinRT `Windows.Media.Ocr` 识别

## 构建

需要 Visual Studio 2022 Build Tools（含 C++/WinRT 和 Windows SDK）与 CMake：

```powershell
cmake -S windows -B build -A x64
cmake --build build --config Release
```

产物在 `build/Release/Mote.exe`。

## 说明

- 截图 OCR 使用系统 OCR 语言包；没有中文语言包时会回退到用户配置语言。
- Windows 版暂不支持自定义快捷键，使用固定组合。
