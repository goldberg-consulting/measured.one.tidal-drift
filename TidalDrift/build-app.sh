#!/bin/bash

# TidalDrift App Builder
# Creates a proper macOS .app bundle

set -e

APP_NAME="TidalDrift"
BUNDLE_ID="com.goldbergconsulting.tidaldrift"
VERSION="1.0.0"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Kill any running instances of TidalDrift first
if pgrep -f "TidalDrift" > /dev/null 2>&1; then
    echo -e "${YELLOW}🔪 Killing running TidalDrift instances...${NC}"
    pkill -f "TidalDrift" 2>/dev/null || true
    sleep 1
fi

echo -e "${BLUE}🌊 Building TidalDrift...${NC}"

# Build release version
swift build -c release

echo -e "${BLUE}📦 Creating app bundle...${NC}"

# Create app bundle structure
APP_BUNDLE="$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp .build/release/TidalDrift "$APP_BUNDLE/Contents/MacOS/"

# Copy icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
fi

# Copy any bundle resources
if [ -d ".build/release/TidalDrift_TidalDrift.bundle" ]; then
    cp -R .build/release/TidalDrift_TidalDrift.bundle "$APP_BUNDLE/Contents/Resources/"
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>TidalDrift</string>
    <key>CFBundleExecutable</key>
    <string>TidalDrift</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TidalDrift</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>TidalDrift needs to discover other Macs on your local network for screen sharing and file sharing.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_rfb._tcp</string>
        <string>_smb._tcp</string>
        <string>_afpovertcp._tcp</string>
        <string>_tidaldrift._tcp</string>
        <string>_tidalclip._tcp</string>
    </array>
    <key>NSHumanReadableCopyright</key>
    <string>© 2024 Goldberg Consulting, LLC. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc sign the app (allows running on local machine)
echo -e "${BLUE}🔏 Signing app...${NC}"
codesign --force --deep --sign - "$APP_BUNDLE"

echo -e "${GREEN}✅ Build complete!${NC}"
echo ""
echo -e "App bundle created: ${BLUE}$(pwd)/$APP_BUNDLE${NC}"
echo ""

# Auto-launch if --run flag is passed
if [[ "$1" == "--run" ]] || [[ "$1" == "-r" ]]; then
    echo -e "${BLUE}🚀 Launching TidalDrift...${NC}"
    open "$APP_BUNDLE"
else
    echo "To install:"
    echo "  1. Drag '$APP_BUNDLE' to your Applications folder"
    echo "  2. Or run: cp -R '$APP_BUNDLE' /Applications/"
    echo ""
    echo "To run now:"
    echo "  open '$APP_BUNDLE'"
    echo "  or: ./build-app.sh --run"
fi

