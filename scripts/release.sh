#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Needs the full Xcode, even if the shell points DEVELOPER_DIR at the Command Line Tools.
case "${DEVELOPER_DIR:-}" in
  ""|*CommandLineTools*) export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ;;
esac
: "${TEAM_ID:?Set your Apple Developer team ID}"
: "${DEVELOPMENT_IDENTITY:?Set your Apple Development signing identity}"
: "${NOTARY_PROFILE:?Set your notarytool keychain profile}"
make lint
make test
make app
RELEASE_DIR=$(mktemp -d "$PWD/dist/release.XXXXXX")
export RELEASE_DIR TEAM_ID DEVELOPMENT_IDENTITY
ARCHIVE="$RELEASE_DIR/Spare.xcarchive"
mkdir -p "$ARCHIVE/Products/Applications"
ditto dist/Spare.app "$ARCHIVE/Products/Applications/Spare.app"
codesign --force --sign "$DEVELOPMENT_IDENTITY" --options runtime --timestamp "$ARCHIVE/Products/Applications/Spare.app"
python3 - <<'PY'
import datetime
import os
import plistlib
import subprocess
from pathlib import Path
root = Path(os.environ['RELEASE_DIR'])
info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
architectures = subprocess.check_output(['lipo', '-archs', 'dist/Spare.app/Contents/MacOS/Spare'], text=True).split()
properties = {key: info[key] for key in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion')}
properties.update(ApplicationPath='Applications/Spare.app', Architectures=architectures,
                  SigningIdentity=os.environ['DEVELOPMENT_IDENTITY'], Team=os.environ['TEAM_ID'])
archive = dict(ArchiveVersion=2, CreationDate=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
               Name='Spare', SchemeName='Spare', ApplicationProperties=properties)
(root / 'Spare.xcarchive/Info.plist').write_bytes(plistlib.dumps(archive))
(root / 'export.plist').write_bytes(plistlib.dumps(dict(method='developer-id', teamID=os.environ['TEAM_ID'], signingStyle='automatic')))
PY
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$RELEASE_DIR/export.plist" \
  -exportPath "$RELEASE_DIR/export" -allowProvisioningUpdates
APP="$RELEASE_DIR/export/Spare.app"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$RELEASE_DIR/notarize.zip"
xcrun notarytool submit "$RELEASE_DIR/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type exec --verbose "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
ARCH=$(lipo -archs "$APP/Contents/MacOS/Spare" | tr ' ' '-')
mkdir -p "$RELEASE_DIR/dmg"
ditto "$APP" "$RELEASE_DIR/dmg/Spare.app"
ln -s /Applications "$RELEASE_DIR/dmg/Applications"
DMG="$RELEASE_DIR/Spare-$VERSION-$ARCH.dmg"
hdiutil create -volname Spare -srcfolder "$RELEASE_DIR/dmg" -format UDZO "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
(cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS.txt)
# Sparkle reads the EdDSA private key from the keychain account named by SPARKLE_ACCOUNT.
mkdir -p "$RELEASE_DIR/appcast"
cp "$DMG" "$RELEASE_DIR/appcast/"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --account "${SPARKLE_ACCOUNT:-spare}" \
  --download-url-prefix "https://github.com/coreyhaines31/spare/releases/download/v$VERSION/" \
  --link https://spareformac.com "$RELEASE_DIR/appcast"
printf 'Release ready: %s\nAttach %s to the GitHub release\n' "$DMG" "$RELEASE_DIR/appcast/appcast.xml"
