# Lingolite for Windows

C++20 + Win32 的轻量客户端骨架，目标产物是几 MB 的免安装 exe。

## 当前进度

- 托盘图标
- `Alt+L` 全局热键
- 鼠标附近悬浮窗
- 单实例

## 下一步

- UI Automation 获取选中文本
- 剪贴板回退
- WinHTTP 调用 OpenAI 兼容接口
- Credential Manager 存储 API Key
- WinRT OCR

## 构建

需要 Visual Studio 2022 Build Tools 和 CMake：

```powershell
cmake -S windows -B build -A x64
cmake --build build --config Release
```

产物在 `build/Release/Lingolite.exe`。

