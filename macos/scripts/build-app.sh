#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

app="dist/Mote.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/release/Mote" "$app/Contents/MacOS/Mote"
cp ".build/release/MoteOCR" "$app/Contents/MacOS/MoteOCR"
cp "Resources/Info.plist" "$app/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app"

echo "Built $app"

