# 构建

## macOS

要求 macOS 13+ 与 Swift 6（Xcode 16 或对应命令行工具）。

```bash
cd macos
swift build -c release          # 只编译，产物在 .build/release/
./scripts/build-app.sh          # 组装 dist/Mote.app（含 MoteOCR 与 Info.plist）
./scripts/install.sh            # 构建并覆盖安装到 /Applications，然后启动
VERSION=0.9.0 ./scripts/package.sh   # 出 ZIP、DMG 与 SHA256SUMS 到 dist/release/
```

脚本说明：

| 脚本 | 作用 |
| --- | --- |
| `build-app.sh` | 编译两个可执行目标，组装 `dist/Mote.app`，ad-hoc 签名 |
| `install.sh` | 调 `build-app.sh`，结束正在运行的实例，覆盖 `/Applications/Mote.app` 并启动 |
| `package.sh` | 打 ZIP 与 DMG；有 `CODESIGN_IDENTITY` 时用它签名，有 `NOTARY_PROFILE` 时提交公证 |
| `make-icon.swift` | 由代码生成应用图标资源 |

### 常见问题

**改动没生效。** `dist/Mote.app` 里的二进制不会自动更新。只把主程序拷进去而漏了 `MoteOCR`，会出现 OCR「无法读取截图」、`--permissions` 查询为空之类的假故障。手动更新时两个都要拷：

```bash
cp .build/release/Mote dist/Mote.app/Contents/MacOS/Mote
cp .build/release/MoteOCR dist/Mote.app/Contents/MacOS/MoteOCR
codesign --force --deep --sign - dist/Mote.app
```

**直接跑 `.build/release/Mote` 图标不对。** 二进制不在 bundle 里时拿不到 `Info.plist` 与图标资源，要跑 `dist/Mote.app/Contents/MacOS/Mote`。

**重新编译后权限失效。** ad-hoc 签名每次都会变，系统把它当成新应用。重新勾选辅助功能与屏幕录制即可。

**编译错误被吞掉。** `swift build ... | tail -1` 只会看到最后一行，加 `| grep error:` 或者直接看完整输出。

## Windows

要求 Visual Studio 2022（含 C++/WinRT、Windows SDK 10）与 CMake。

```powershell
cmake -S windows -B build -A x64
cmake --build build --config Release
```

产物在 `build\Release\Mote.exe`。打包：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File windows/scripts/package.ps1 -Version 0.9.0
```

产物在 `dist\Mote-<版本>-windows-x64.zip`。

也可以用 Visual Studio 直接打开 `windows\CMakeLists.txt`。

> 这一版 Windows 代码是在 macOS 上写的，没有在本机编译验证过（依赖 WinRT/cppwinrt，必须有 MSVC + Windows SDK）。构建报错请提 issue 并附完整输出。

## 持续集成

`.github/workflows/` 下有三个工作流：

| 文件 | 触发 | 作用 |
| --- | --- | --- |
| `macos.yml` | push / PR | macOS 编译检查 |
| `windows.yml` | push / PR | Windows 编译检查 |
| `release.yml` | 推送 `v*` 标签 | 两端打包并创建 draft Release |

签名与发布流程见 [RELEASE.md](RELEASE.md)。
