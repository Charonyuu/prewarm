#!/bin/bash
# Builds Prewarm.app.
#
#   ./build.sh              build only
#   ./build.sh --install    build, then copy to /Applications and launch
#   ./build.sh --release    build, sign with Developer ID, package a dmg,
#                           notarize it and staple the ticket
set -euo pipefail

APP_NAME="Prewarm"
BINARY="Prewarm"
BUNDLE_ID="com.charonyuu.ClaudePrewarm"
VERSION="2.0.0"
SIGN_IDENTITY="Developer ID Application: Cheng Yu Chiang (XADL3RD65Y)"
NOTARY_PROFILE="prewarm-notary"

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/build/$APP_NAME $VERSION.dmg"
MODE="${1:-}"

echo "→ Compiling (release, universal)…"
swift build -c release --arch arm64 --arch x86_64

echo "→ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/apple/Products/Release/ClaudePrewarm" "$APP/Contents/MacOS/$BINARY"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$BINARY</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>100% local. No API keys. No telemetry.</string>
    <key>NSAppleEventsUsageDescription</key><string>Prewarm opens Terminal so you can sign in to Claude Code, Codex, Grok Build or agy.</string>
</dict>
</plist>
PLIST

if [[ "$MODE" == "--release" ]]; then
    # ---- signed, notarized distribution build ----------------------------
    if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
        echo "✗ Signing identity not found: $SIGN_IDENTITY" >&2
        exit 1
    fi

    echo "→ Signing with Developer ID (hardened runtime)…"
    codesign --force --options runtime --timestamp \
        --identifier "$BUNDLE_ID" \
        --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"

    echo "→ Building disk image…"
    STAGING="$(mktemp -d)"
    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    rm -f "$DMG"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
        -ov -format UDZO -quiet "$DMG"
    rm -rf "$STAGING"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        cat <<MSG

⚠  Built and signed, but NOT notarized — no keychain profile "$NOTARY_PROFILE".
   Store your credentials once, then run this again:

   xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
       --apple-id "<your Apple ID>" \\
       --team-id XADL3RD65Y \\
       --password "<app-specific password from appleid.apple.com>"

   Unnotarized: $DMG
MSG
        exit 0
    fi

    echo "→ Notarizing (this uploads to Apple and waits)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "→ Stapling…"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl -a -t open --context context:primary-signature -v "$DMG"

    echo "✓ Ready to ship: $DMG"
    exit 0
fi

echo "→ Signing (ad-hoc)…"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
echo "✓ Built $APP"

if [[ "$MODE" == "--install" ]]; then
    echo "→ Installing to /Applications…"
    pkill -f "/Applications/$APP_NAME.app" 2>/dev/null || true
    pkill -f "/Applications/Claude Prewarm.app" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app" "/Applications/Claude Prewarm.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    echo "✓ Installed. Launching…"
    open "/Applications/$APP_NAME.app"
fi
