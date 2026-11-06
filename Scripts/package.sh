#!/usr/bin/env bash
# Package build/Clipster.app into dist/ as a .dmg and .zip with SHA-256 sums.
#   usage: Scripts/package.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: package.sh <version>}"
APP="build/Clipster.app"
[[ -d "$APP" ]] || { echo "missing $APP — run Scripts/build-app.sh first" >&2; exit 1; }

mkdir -p dist
DMG="dist/Clipster-$VERSION.dmg"
ZIP="dist/Clipster-$VERSION.zip"
rm -f "$DMG" "$ZIP"

echo "==> Creating $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Creating $DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE:?}"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Clipster $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ -n "${SIGN_ID:-}" && "${SIGN_ID}" != "-" ]]; then
    codesign --force --sign "$SIGN_ID" --timestamp "$DMG"
fi

(cd dist && shasum -a 256 "Clipster-$VERSION.dmg" "Clipster-$VERSION.zip" > SHA256SUMS.txt)
cat dist/SHA256SUMS.txt
