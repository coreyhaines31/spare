#!/bin/bash
# Points the Homebrew cask at a published release: bash scripts/update-homebrew-cask.sh 0.13.0
set -euo pipefail
VERSION="${1:?usage: scripts/update-homebrew-cask.sh <version>}"
URL="https://github.com/coreyhaines31/spare/releases/download/v$VERSION/Spare-$VERSION-arm64.dmg"
SHA=$(curl -fsSL "$URL" | shasum -a 256 | cut -d' ' -f1)
TAP=$(mktemp -d)
gh repo clone coreyhaines31/homebrew-tap "$TAP" -- --quiet --depth 1
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/spare.rb"
git -C "$TAP" commit -qam "spare $VERSION"
git -C "$TAP" push -q
printf 'Updated the spare cask to %s (%s)\n' "$VERSION" "$SHA"
