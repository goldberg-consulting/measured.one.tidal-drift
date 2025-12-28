#!/bin/bash

# TidalDrift Quick Builder
# Creates a local .app bundle for testing (no code signing)
#
# IMPORTANT: Uses xcodebuild instead of swift build for reliability
# Requires: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
#
# Usage:
#   ./build-app.sh           # Build and run
#   ./build-app.sh --no-run  # Build only

set -e

APP_NAME="TidalDrift"
VERSION="1.3.14"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
RUN_APP=true
for arg in "$@"; do
    case $arg in
        --no-run)
            RUN_APP=false
            shift
            ;;
    esac
done

echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  🌊 TidalDrift Quick Build v${VERSION}   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Verify Xcode setup
XCODE_PATH=$(xcode-select -p)
if [[ "$XCODE_PATH" != *"Xcode.app"* ]]; then
    echo -e "${RED}❌ xcode-select not pointing to Xcode.app${NC}"
    echo "Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

# Cleanup
echo -e "${BLUE}🧹 Cleanup...${NC}"
pkill -9 -f "TidalDrift" 2>/dev/null || true
pkill -9 swift 2>/dev/null || true
rm -rf TidalDrift.app build-xcode
sleep 1

# Build
echo -e "${BLUE}🔨 Building...${NC}"
xcodebuild -scheme TidalDrift \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath ./build-xcode \
    build 2>&1 | grep -E "(BUILD|error:)" | tail -5

BINARY="./build-xcode/Build/Products/Debug/TidalDrift"
if [ ! -f "$BINARY" ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

# Create app bundle
echo -e "${BLUE}📦 Creating app bundle...${NC}"
mkdir -p TidalDrift.app/Contents/MacOS
mkdir -p TidalDrift.app/Contents/Resources

cp "$BINARY" TidalDrift.app/Contents/MacOS/
[ -f "Resources/AppIcon.icns" ] && cp Resources/AppIcon.icns TidalDrift.app/Contents/Resources/
[ -d "./build-xcode/Build/Products/Debug/TidalDrift_TidalDrift.bundle" ] && \
    cp -R ./build-xcode/Build/Products/Debug/TidalDrift_TidalDrift.bundle TidalDrift.app/Contents/Resources/

cat > TidalDrift.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TidalDrift</string>
    <key>CFBundleIdentifier</key><string>com.goldbergconsulting.tidaldrift</string>
    <key>CFBundleName</key><string>TidalDrift</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>TidalDrift needs to discover other Macs on your local network.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_rfb._tcp</string>
        <string>_smb._tcp</string>
        <string>_ssh._tcp</string>
        <string>_tidaldrift._tcp</string>
        <string>_tidaldrop._tcp</string>
    </array>
</dict>
</plist>
EOF
echo -n "APPL????" > TidalDrift.app/Contents/PkgInfo

# Ad-hoc sign for local use
codesign --force --deep --sign - TidalDrift.app 2>/dev/null || true

# Cleanup build artifacts
rm -rf build-xcode

echo ""
echo -e "${GREEN}✅ Built: TidalDrift.app (v${VERSION})${NC}"
echo ""

if [ "$RUN_APP" = true ]; then
    echo -e "${BLUE}🚀 Launching...${NC}"
    open TidalDrift.app
fi
