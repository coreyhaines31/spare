#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
mkdir -p dist/Spare.app/Contents/MacOS dist/Spare.app/Contents/Resources
cp "$BIN_DIR/Spare" dist/Spare.app/Contents/MacOS/Spare
cp Resources/Info.plist dist/Spare.app/Contents/Info.plist
mkdir -p dist/Spare.iconset
swift scripts/icon.swift dist/Spare.iconset
iconutil -c icns dist/Spare.iconset -o dist/Spare.app/Contents/Resources/Spare.icns
codesign --force --sign - dist/Spare.app
printf 'Built %s/dist/Spare.app\n' "$PWD"
