#!/bin/zsh
# 打包 macOS Release：签名、DMG/ZIP、可选公证；不做上传。
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.7.3}}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="dist/Lingolite.app"
OUT="dist/release"

./scripts/build-app.sh

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP/Contents/MacOS/LingoliteOCR"
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/LingoliteOCR"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$OUT"
mkdir -p "$OUT"

ditto -c -k --keepParent "$APP" "$OUT/Lingolite-$VERSION-macos.zip"

STAGE="dist/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "Lingolite $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$OUT/Lingolite-$VERSION-macos.dmg" >/dev/null

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit \
    "$OUT/Lingolite-$VERSION-macos.dmg" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$OUT/Lingolite-$VERSION-macos.dmg"
  xcrun stapler staple "$APP" || true
  ditto -c -k --keepParent "$APP" "$OUT/Lingolite-$VERSION-macos.zip"
fi

(cd "$OUT" && shasum -a 256 * > SHA256SUMS.txt)
echo "Packaged $OUT"
