#!/bin/zsh
# 构建并覆盖安装到 /Applications，用于本机自用；不做公证和分发签名。
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build-app.sh

target="/Applications/Mote.app"
pkill -x Mote >/dev/null 2>&1 || true
rm -rf "$target"
cp -R dist/Mote.app "$target"

echo "Installed $target"
open "$target"
