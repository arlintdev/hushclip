#!/usr/bin/env bash
# Build Clipster.app into build/.
#
#   VERSION   marketing version (default: 1.0.0)
#   ARCHS     space-separated architectures (default: "arm64 x86_64" = universal)
#   SIGN_ID   codesigning identity (default: "-" = ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-arm64 x86_64}"
SIGN_ID="${SIGN_ID:--}"
APP="build/Clipster.app"

arch_flags=()
for arch in $ARCHS; do arch_flags+=(--arch "$arch"); done

echo "==> Building Clipster $VERSION ($BUILD_NUMBER) for: $ARCHS"
swift build -c release "${arch_flags[@]}"
BIN_DIR="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Clipster" "$APP/Contents/MacOS/Clipster"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Signing with: $SIGN_ID"
if [[ "$SIGN_ID" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$APP"
else
    # Hardened runtime + secure timestamp are required for notarization.
    codesign --force --sign "$SIGN_ID" --options runtime --timestamp "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/Clipster"
echo "==> Built $APP"
