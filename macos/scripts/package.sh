#!/bin/zsh
# 打包 macOS Release：签名、DMG/ZIP、可选公证；不做上传。
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.8.0}}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="dist/Mote.app"
OUT="dist/release"

./scripts/build-app.sh

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP/Contents/MacOS/MoteOCR"
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/MoteOCR"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$OUT"
mkdir -p "$OUT"

ditto -c -k --keepParent "$APP" "$OUT/Mote-$VERSION-macos.zip"

STAGE="dist/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "Mote $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$OUT/Mote-$VERSION-macos.dmg" >/dev/null

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit \
    "$OUT/Mote-$VERSION-macos.dmg" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$OUT/Mote-$VERSION-macos.dmg"
  xcrun stapler staple "$APP" || true
  ditto -c -k --keepParent "$APP" "$OUT/Mote-$VERSION-macos.zip"
fi

(cd "$OUT" && shasum -a 256 * > SHA256SUMS.txt)
echo "Packaged $OUT"
