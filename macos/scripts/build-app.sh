#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

app="dist/Lingolite.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/release/Lingolite" "$app/Contents/MacOS/Lingolite"
cp "Resources/Info.plist" "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"

echo "Built $app"

