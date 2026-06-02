#!/bin/bash
set -euo pipefail

echo "=== Building Savage Protracker Player App in Release Mode ==="
swift build -c release
APP_VERSION="$(cat VERSION)"

echo "=== Creating macOS App Bundle structure ==="
APP_DIR="Savage Protracker Player.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Daniel Mueller (9QSWKSR4NQ)}"
SIGN_APP="${SIGN_APP:-auto}"

# Recreate the folders
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy release binary
cp ".build/release/SavageProtrackerPlayerApp" "$MACOS_DIR/"

# Compile and copy AppIcon.icns if AppIcon.png exists
if [ -f "src/AppIcon.png" ]; then
    echo "=== Compiling AppIcon.icns ==="
    mkdir -p AppIcon.iconset
    sips -s format png -z 16 16     src/AppIcon.png --out AppIcon.iconset/icon_16x16.png
    sips -s format png -z 32 32     src/AppIcon.png --out AppIcon.iconset/icon_16x16@2x.png
    sips -s format png -z 32 32     src/AppIcon.png --out AppIcon.iconset/icon_32x32.png
    sips -s format png -z 64 64     src/AppIcon.png --out AppIcon.iconset/icon_32x32@2x.png
    sips -s format png -z 128 128   src/AppIcon.png --out AppIcon.iconset/icon_128x128.png
    sips -s format png -z 256 256   src/AppIcon.png --out AppIcon.iconset/icon_128x128@2x.png
    sips -s format png -z 256 256   src/AppIcon.png --out AppIcon.iconset/icon_256x256.png
    sips -s format png -z 512 512   src/AppIcon.png --out AppIcon.iconset/icon_256x256@2x.png
    sips -s format png -z 512 512   src/AppIcon.png --out AppIcon.iconset/icon_512x512.png
    sips -s format png -z 1024 1024 src/AppIcon.png --out AppIcon.iconset/icon_512x512@2x.png
    iconutil -c icns AppIcon.iconset
    cp AppIcon.icns "$RESOURCES_DIR/"
    rm -rf AppIcon.iconset AppIcon.icns
fi

# Create Info.plist
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SavageProtrackerPlayerApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.viben.SavageProtrackerPlayer</string>
    <key>CFBundleName</key>
    <string>Savage Protracker Player</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [[ "$SIGN_APP" != "0" ]]; then
    echo "=== Checking code signing identity ==="
    if security find-identity -v -p codesigning | grep -Fq "$CODESIGN_IDENTITY"; then
        echo "=== Signing App Bundle ==="
        # Hardened Runtime ist Pflicht fuer spaetere Notarisierung.
        codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
        codesign --verify --deep --strict --verbose=2 "$APP_DIR"
    elif [[ "$SIGN_APP" == "1" || "${REQUIRE_CODESIGN:-0}" == "1" ]]; then
        echo "ABBRUCH: Codesign-Identity nicht gefunden: $CODESIGN_IDENTITY" >&2
        echo "Tipp: SIGN_APP=0 bash build_app.sh baut lokal ohne Signatur." >&2
        exit 1
    else
        echo "WARNUNG: Codesign-Identity nicht sichtbar. App bleibt unsigniert."
        echo "Tipp: REQUIRE_CODESIGN=1 bash build_app.sh erzwingt Signatur fuer Releases."
    fi
fi

echo "=== App Bundle Created Successfully: $APP_DIR ==="
echo "You can now double-click '$APP_DIR' in Finder to launch the player!"
