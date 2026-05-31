#!/bin/bash
set -e

DMG_NAME="Savage Protracker Player"
APP_NAME="Savage Protracker Player.app"
VOL_NAME="Savage Protracker Player"

echo "=== Preparing DMG Build ==="
# 1. Clean old files
mkdir -p build
rm -f "build/${DMG_NAME}.dmg" build/dmg_rw.dmg
rm -rf build/dmg_temp
mkdir -p build/dmg_temp

# 2. Copy the App bundle
cp -R "${APP_NAME}" build/dmg_temp/

# 3. Create Applications symlink
ln -s /Applications build/dmg_temp/Applications

# 4. Create Retina-compatible background (2x TIFF: 1x 600x600 + 2x 1200x1200)
sips -s format png -s dpiWidth 72 -s dpiHeight 72 -z 600 600 src/DmgBackground.png --out build/DmgBg_1x.png
sips -s format png -s dpiWidth 144 -s dpiHeight 144 -z 1200 1200 src/DmgBackground.png --out build/DmgBg_2x.png
tiffutil -cathidpicheck build/DmgBg_1x.png build/DmgBg_2x.png -out build/DmgBackground.tiff

# 5. Create raw DMG of size 25MB
hdiutil create -size 25m -fs HFS+ -volname "${VOL_NAME}" -ov build/dmg_rw.dmg

# 6. Mount DMG
echo "=== Mounting DMG ==="
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "/Volumes/${VOL_NAME}" build/dmg_rw.dmg

# 7. Copy files to DMG
echo "=== Copying files to DMG ==="
cp -R "build/dmg_temp/${APP_NAME}" "/Volumes/${VOL_NAME}/"
ln -s /Applications "/Volumes/${VOL_NAME}/Applications"

# 8. Create hidden background directory and copy background
mkdir -p "/Volumes/${VOL_NAME}/.background"
cp build/DmgBackground.tiff "/Volumes/${VOL_NAME}/.background/DmgBackground.tiff"

# 9. Run AppleScript to set layout
echo "=== Configuring DMG layout with AppleScript ==="
osascript <<EOF
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 700, 700}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file ".background:DmgBackground.tiff"
        -- Position icons over the slots in the background image
        set position of item "${APP_NAME}" of container window to {180, 360}
        set position of item "Applications" of container window to {420, 360}
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# 10. Unmount DMG
echo "=== Unmounting DMG ==="
sleep 2
hdiutil detach "/Volumes/${VOL_NAME}" || hdiutil detach -force "/Volumes/${VOL_NAME}"

# 11. Convert raw DMG to compressed read-only DMG
echo "=== Converting DMG to read-only ==="
hdiutil convert build/dmg_rw.dmg -format UDZO -imagekey zlib-level=9 -o "build/${DMG_NAME}.dmg"

# 12. Cleanup
rm -f build/dmg_rw.dmg build/DmgBg_1x.png build/DmgBg_2x.png build/DmgBackground.tiff
rm -rf build/dmg_temp
echo "=== DMG build successful: build/${DMG_NAME}.dmg ==="
