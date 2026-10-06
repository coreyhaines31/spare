#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
[ -d dist/Spare.app ] && rm -r dist/Spare.app
mkdir -p dist/Spare.app/Contents/MacOS dist/Spare.app/Contents/Resources dist/Spare.app/Contents/Frameworks
cp "$BIN_DIR/Spare" dist/Spare.app/Contents/MacOS/Spare
ditto "$BIN_DIR/Sparkle.framework" dist/Spare.app/Contents/Frameworks/Sparkle.framework
install_name_tool -add_rpath @executable_path/../Frameworks dist/Spare.app/Contents/MacOS/Spare
cp Resources/Info.plist dist/Spare.app/Contents/Info.plist
mkdir -p dist/Spare.iconset
swift scripts/icon.swift dist/Spare.iconset
iconutil -c icns dist/Spare.iconset -o dist/Spare.app/Contents/Resources/Spare.icns
codesign --force --deep --sign - dist/Spare.app
printf 'Built %s/dist/Spare.app\n' "$PWD"
