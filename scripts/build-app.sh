#!/bin/bash
# Builds the bottle manager (app/) and assembles dist/Winebuild Manager.app.
# Usage: scripts/build-app.sh [--open]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPSRC="$ROOT/app"
OUT="$ROOT/dist/Winebuild Manager.app"
WORK="$ROOT/build/app"

swift build --package-path "$APPSRC" -c release --product WinebuildManager
BIN="$(swift build --package-path "$APPSRC" -c release --show-bin-path)/WinebuildManager"

mkdir -p "$WORK"
if [ ! -f "$WORK/AppIcon.icns" ] || [ "$APPSRC/Tools/make-icon.swift" -nt "$WORK/AppIcon.icns" ]; then
    swift "$APPSRC/Tools/make-icon.swift" "$WORK/icon-1024.png"
    rm -rf "$WORK/AppIcon.iconset"; mkdir "$WORK/AppIcon.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$WORK/icon-1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z $d $d "$WORK/icon-1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$WORK/AppIcon.iconset" -o "$WORK/AppIcon.icns"
fi

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/WinebuildManager"
cp "$WORK/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Winebuild Manager</string>
    <key>CFBundleDisplayName</key><string>Winebuild Manager</string>
    <key>CFBundleIdentifier</key><string>local.winebuild.manager</string>
    <key>CFBundleExecutable</key><string>WinebuildManager</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>vi</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>WinebuildRoot</key><string>$ROOT</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$OUT" >/dev/null
echo "Built: $OUT"
[ "${1:-}" = "--open" ] && open "$OUT"
exit 0
