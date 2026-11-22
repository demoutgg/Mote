# 签名与发布

## 版本号

发布前同步更新：

- `macos/Resources/Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion`
- `windows/resources` 里如有版本资源，同步修改
- Git tag 使用 `vX.Y.Z`

## macOS 签名与公证

正式分发需要 Apple Developer Program（约 $99/年）。

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
VERSION=0.8.0 \
./macos/scripts/package.sh
```

产物在 `macos/dist/release/`：ZIP、DMG、SHA256SUMS。

没有证书时脚本会使用 ad-hoc 签名；别人下载后需要右键 → 打开，且无法通过公证。

## Windows 签名

正式分发建议购买 OV/EV 代码签名证书。签名命令：

```powershell
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
  /f cert.pfx /p "$env:CERT_PASSWORD" `
  build\Release\Mote.exe
```

没有证书时 exe 未签名，SmartScreen 会提示；可先点“更多信息 → 仍要运行”。

## GitHub Release

两种方式：

### 自动（推荐）

```bash
git tag v0.8.0
git push origin v0.8.0
```

`.github/workflows/release.yml` 会：

- macOS 打包 ZIP + DMG
- Windows 打包 ZIP
- 创建 **draft** Release，附件齐全

到 GitHub → Releases 检查草稿并点击 Publish。

### 手动

```bash
gh release create v0.8.0 \
  macos/dist/release/Mote-0.8.0-macos.dmg \
  macos/dist/release/Mote-0.8.0-macos.zip \
  dist/Mote-0.8.0-windows-x64.zip \
  --draft --title "Mote 0.8.0" --notes-file RELEASE_NOTES.md
```

## 自动化签名（可选）

如果希望 CI 自动签名，在仓库 Secrets 中配置：

- `MACOS_CERTIFICATE`：base64 编码的 `.p12`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `APPLE_ID` / `APPLE_TEAM_ID` / `APPLE_APP_PASSWORD`
- `WINDOWS_CERTIFICATE`：base64 编码的 `.pfx`
- `WINDOWS_CERTIFICATE_PASSWORD`

然后在 release workflow 的打包前导入证书，并把 `CODESIGN_IDENTITY` / `NOTARY_PROFILE` 传给 `package.sh`，Windows 用 `signtool` 签名后再压缩。
