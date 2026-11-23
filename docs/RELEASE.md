# 发布

## 版本号

发布前同步：

- `macos/Resources/Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion`
- `windows/CMakeLists.txt` 里的版本资源
- `docs/CHANGELOG.md` 增加对应条目
- Git tag 使用 `vX.Y.Z`

## 发布前检查

- [ ] `cd macos && swift build -c release` 通过
- [ ] `./macos/scripts/install.sh` 安装后逐项点验：输入、选中、剪贴板、截图翻译、截图 OCR
- [ ] 权限引导能弹出，授权后自动关闭
- [ ] 设置四个分页都能滚动到最底部，保存后不关闭窗口
- [ ] 历史记录可搜索、复制、清空
- [ ] `docs/CHANGELOG.md` 与 `README.md` 内容与实际一致
- [ ] Windows 改动若未经实机验证，Release 说明里要写明

## 本机打包

```bash
VERSION=0.10.0 ./macos/scripts/package.sh
```

产物在 `macos/dist/release/`：`Mote-0.10.0-macos.zip`、`Mote-0.10.0-macos.dmg`、`SHA256SUMS.txt`。

没有证书时脚本自动使用 ad-hoc 签名，产物能跑但未经公证，用户首次打开需要右键 → 打开。

## 签名与公证（macOS）

正式分发需要 Apple Developer Program。

1. 在 Apple Developer 后台创建 **Developer ID Application** 证书，导出 `.p12`。
2. 导入钥匙串：

```bash
security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
security import cert.p12 -k build.keychain -P "$P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" build.keychain
```

3. 配置公证凭据：

```bash
xcrun notarytool store-credentials "mote-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

4. 打包、签名、公证：

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="mote-notary" \
VERSION=0.10.0 \
./macos/scripts/package.sh
```

## 签名（Windows）

正式分发建议购买 OV/EV 代码签名证书：

```powershell
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
  /f cert.pfx /p "$env:CERT_PASSWORD" `
  build\Release\Mote.exe
```

没有证书时 exe 未签名，SmartScreen 会提示，用户需点「更多信息 → 仍要运行」。

## 发布到 GitHub

### 自动（推荐）

```bash
git tag v0.10.0
git push origin v0.10.0
```

`.github/workflows/release.yml` 会打包 macOS 的 ZIP/DMG 与 Windows 的 ZIP，创建 **draft** Release。到仓库 Releases 页面检查并点击 Publish。

### 手动

```bash
gh release create v0.10.0 \
  macos/dist/release/Mote-0.10.0-macos.dmg \
  macos/dist/release/Mote-0.10.0-macos.zip \
  macos/dist/release/SHA256SUMS.txt \
  --title "Mote 0.10.0" --notes-file RELEASE_NOTES.md --latest
```

Windows 产物由 CI 编译，未经实机运行验证，Release 说明里必须写清这一点。

### Release 说明模板

```markdown
## 安装

下载 `Mote-<版本>-macos.dmg`，拖进「应用程序」。当前为 ad-hoc 签名、未经公证，
首次打开请右键 → 打开。

## 本次更新

- …

## 已知问题

- Windows 版未经实机运行验证（CI 只验证编译通过），请自行评估或参考 docs/BUILD.md 自行编译。
- 重新编译后 ad-hoc 签名变化，需要重新授权辅助功能与屏幕录制。
```

## CI 自动签名（可选）

在仓库 Secrets 中配置：

- `MACOS_CERTIFICATE`：base64 编码的 `.p12`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `APPLE_ID` / `APPLE_TEAM_ID` / `APPLE_APP_PASSWORD`
- `WINDOWS_CERTIFICATE`：base64 编码的 `.pfx`
- `WINDOWS_CERTIFICATE_PASSWORD`

然后在 release workflow 打包前导入证书，把 `CODESIGN_IDENTITY` / `NOTARY_PROFILE` 传给 `package.sh`，Windows 用 `signtool` 签名后再压缩。
