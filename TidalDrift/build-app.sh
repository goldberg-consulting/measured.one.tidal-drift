#!/bin/bash

# TidalDrift Quick Builder - Local testing (no signing)
# Uses xcodebuild + ditto --norsrc
# Requires: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

set -e
VERSION="1.3.15"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

RUN_APP=true; [[ "$1" == "--no-run" ]] && RUN_APP=false

echo -e "${BLUE}🌊 TidalDrift Quick Build v${VERSION}${NC}"

[[ "$(xcode-select -p)" != *"Xcode.app"* ]] && echo "❌ Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" && exit 1

pkill -9 -f "TidalDrift" 2>/dev/null || true
rm -rf TidalDrift.app build-xcode

xcodebuild -scheme TidalDrift -configuration Debug -destination 'platform=macOS' -derivedDataPath ./build-xcode build 2>&1 | grep "BUILD"
[ ! -f "./build-xcode/Build/Products/Debug/TidalDrift" ] && echo "❌ Build failed" && exit 1

mkdir -p TidalDrift.app/Contents/MacOS TidalDrift.app/Contents/Resources
ditto --norsrc ./build-xcode/Build/Products/Debug/TidalDrift TidalDrift.app/Contents/MacOS/TidalDrift
[ -f "Resources/AppIcon.icns" ] && ditto --norsrc Resources/AppIcon.icns TidalDrift.app/Contents/Resources/AppIcon.icns
[ -d "./build-xcode/Build/Products/Debug/TidalDrift_TidalDrift.bundle" ] && \
    ditto --norsrc ./build-xcode/Build/Products/Debug/TidalDrift_TidalDrift.bundle TidalDrift.app/Contents/Resources/TidalDrift_TidalDrift.bundle

cat > TidalDrift.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>TidalDrift</string>
    <key>CFBundleIdentifier</key><string>com.goldbergconsulting.tidaldrift</string>
    <key>CFBundleName</key><string>TidalDrift</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>TidalDrift discovers Macs on your network.</string>
    <key>NSBonjourServices</key><array><string>_rfb._tcp</string><string>_tidaldrift._tcp</string></array>
</dict></plist>
EOF
echo -n "APPL????" > TidalDrift.app/Contents/PkgInfo

codesign --force --deep --sign - TidalDrift.app 2>/dev/null || true
rm -rf build-xcode

echo -e "${GREEN}✅ Built: TidalDrift.app${NC}"
[ "$RUN_APP" = true ] && open TidalDrift.app
