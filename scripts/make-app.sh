#!/usr/bin/env bash
# Builds a release binary and assembles Uninstaller.app — a menu-bar
# agent (LSUIElement, no Dock icon). Mirrors Alfred / port-swift.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/Uninstaller.app"
SRC_ICON="$ROOT/art/AppIcon-source.png"
VERSION="0.1.6"
SIGN_IDENTITY="${SIGN_IDENTITY:-0948896DC970503ADEF5B5070E0BB3E9D9047757}"
DMG="$ROOT/Uninstaller-$VERSION.dmg"

echo "› swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "› assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# App icon → .iconset → .icns
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
  pxs="${spec%%:*}"; name="${spec##*:}"
  sips -z "$pxs" "$pxs" "$SRC_ICON" --out "$ICONSET/icon_${name}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cp "$BIN/Uninstaller" "$APP/Contents/MacOS/Uninstaller"

# Embed + sign SuiteKit and the pane dylib so the launcher can
# dlopen the same code out of this installed .app.
mkdir -p "$APP/Contents/Frameworks"
cp "$BIN/libSuiteKit.dylib" "$APP/Contents/Frameworks/"
cp "$BIN/libUninstallerPane.dylib" "$APP/Contents/Frameworks/"
if [ -d "$BIN/Uninstaller_UninstallerPane.bundle" ]; then
  find "$BIN/Uninstaller_UninstallerPane.bundle" -type f \
    \( -name '*.png' -o -name '*.icns' \) \
    -exec cp {} "$APP/Contents/Resources/" \;
fi
install_name_tool -add_rpath @executable_path/../Frameworks \
  "$APP/Contents/MacOS/Uninstaller" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Uninstaller</string>
  <key>CFBundleDisplayName</key><string>Uninstaller</string>
  <key>CFBundleIdentifier</key><string>com.mattssoftware.uninstaller</string>
  <key>CFBundleExecutable</key><string>Uninstaller</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Uninstaller</string>
  <!-- Used so Finder can move /Applications/<App>.app to Trash on
       our behalf. The first uninstall triggers a one-time
       "Uninstaller would like to control Finder" prompt; clicking
       Allow lets every subsequent uninstall run without further
       interruption. This routes around App Management TCC, which
       can silently deny on machines where any earlier
       NSWorkspace.recycle attempt got implicitly refused and never
       re-prompts. -->
  <key>NSAppleEventsUsageDescription</key>
  <string>Uninstaller asks Finder to move apps and their leftover files to the Trash on your behalf.</string>
</dict>
</plist>
PLIST

# Sign inside-out with Developer ID if present; ad-hoc otherwise.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/libSuiteKit.dylib"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/libUninstallerPane.dylib"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/Uninstaller"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=1 "$APP" \
    && echo "✓ signed: $SIGN_IDENTITY"
else
  echo "⚠ signing identity not found — ad-hoc signing instead"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "✓ built $APP"

# Notarize + staple (Developer ID only). Non-fatal: if creds aren't
# available we still complete with a signed-but-not-notarized app.
NOTARY_PROFILE="${NOTARY_PROFILE:-Notary}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "› notarizing $APP (waits on Apple)…"
  NZIP="$(mktemp -d)/notarize.zip"
  ditto -c -k --keepParent "$APP" "$NZIP"
  if xcrun notarytool submit "$NZIP" \
       --keychain-profile "$NOTARY_PROFILE" --wait; then
    if xcrun stapler staple "$APP"; then
      if xcrun stapler validate "$APP"; then
        echo "✓ notarized + stapled $APP"
      else
        echo "⚠ staple validate failed for $APP"
      fi
    else
      echo "⚠ stapling failed for $APP"
    fi
  else
    echo "⚠ notarization skipped/failed — $APP signed but not notarized"
  fi
fi

# Optional .dmg from the stapled .app.
if [ "${SKIP_DMG:-0}" != "1" ]; then
  STAGE="$(mktemp -d)/dmg"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/Uninstaller.app"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -quiet -volname "Uninstaller" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG"
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    codesign --force --sign "$SIGN_IDENTITY" "$DMG" || true
  fi
  echo "✓ built $DMG"
fi
