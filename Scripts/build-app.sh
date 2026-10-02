#!/bin/bash
# Assembles and signs SaveAsHere.app.
#
# The signing identity must be STABLE. macOS ties the Accessibility grant to the
# code signature, and ad-hoc signing produces a new identity on every build —
# which silently invalidates the grant while System Settings still shows the app
# as enabled. That failure mode wastes hours, so it is called out loudly below.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/SaveAsHere.app"
BUNDLE_ID="com.abumoosa.saveashere"

swift build -c release --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/SaveAsHere" "$APP/Contents/MacOS/SaveAsHere"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>SaveAsHere</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>SaveAsHere</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

IDENTITY="${SAH_SIGN_IDENTITY:-}"

# Prefer any real identity in the keychain over ad-hoc, since ad-hoc is what
# breaks the Accessibility grant on rebuild.
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)"
  [ -n "$IDENTITY" ] && echo "Using keychain identity: $IDENTITY"
fi

if [ -z "$IDENTITY" ]; then
  cat <<'WARN'

WARNING: SAH_SIGN_IDENTITY is not set, so this build is signed ad-hoc.
The Accessibility grant will break on the next rebuild — and System Settings
will still show the app as enabled, so it looks like a code bug rather than a
permission one.

To fix permanently, create a self-signed code-signing certificate once:
  Keychain Access > Certificate Assistant > Create a Certificate…
    Name: SaveAsHere Dev
    Identity Type: Self Signed Root
    Certificate Type: Code Signing
  Then: export SAH_SIGN_IDENTITY="SaveAsHere Dev"

If the grant goes stale anyway, reset it and re-grant:
  tccutil reset Accessibility com.abumoosa.saveashere

WARN
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
else
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
fi

echo "Built $APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature' || true
