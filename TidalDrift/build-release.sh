#!/bin/bash

# TidalDrift Release Builder
# Creates a signed, notarized DMG for distribution
#
# IMPORTANT: Uses xcodebuild instead of swift build for reliability
# Requires: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
#
# Usage:
#   ./build-release.sh              # Build and notarize
#   ./build-release.sh --skip-notarize  # Build only (for testing)

set -e

# Configuration
APP_NAME="TidalDrift"
BUNDLE_ID="com.goldbergconsulting.tidaldrift"
VERSION="1.3.14"
DMG_NAME="${APP_NAME}-${VERSION}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load credentials from .env if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
    echo -e "${BLUE}📋 Loaded credentials from .env${NC}"
fi

# Signing identity
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"

# Output directories
BUILD_DIR="$(pwd)"
RELEASE_DIR="$BUILD_DIR/dist"
APP_BUNDLE="$APP_NAME.app"

# Parse arguments
SKIP_NOTARIZE=false
for arg in "$@"; do
    case $arg in
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
    esac
done

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     🌊 TidalDrift Release Builder v${VERSION}              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ========== STEP 0: VERIFY XCODE SETUP ==========
echo -e "${BLUE}🔧 Step 0: Verifying Xcode setup...${NC}"
XCODE_PATH=$(xcode-select -p)
if [[ "$XCODE_PATH" != *"Xcode.app"* ]]; then
    echo -e "${RED}❌ xcode-select is not pointing to Xcode.app${NC}"
    echo "Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi
echo -e "${GREEN}  ✓ Using Xcode at: $XCODE_PATH${NC}"
echo ""

# ========== STEP 1: CLEANUP ==========
echo -e "${BLUE}🧹 Step 1: Cleanup...${NC}"
pkill -9 -f "TidalDrift" 2>/dev/null || true
pkill -9 swift 2>/dev/null || true
rm -rf "$APP_BUNDLE" build-xcode
echo -e "${GREEN}  ✓ Cleanup complete${NC}"
echo ""

# ========== STEP 2: CHECK CERTIFICATE ==========
echo -e "${BLUE}🔍 Step 2: Checking certificate...${NC}"
DEV_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
if [ -z "$DEV_ID" ]; then
    echo -e "${RED}❌ No Developer ID Application certificate found${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Found: $DEV_ID${NC}"
echo ""

# ========== STEP 3: BUILD ==========
echo -e "${BLUE}🔨 Step 3: Building...${NC}"
mkdir -p dist
xcodebuild -scheme TidalDrift \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath ./build-xcode \
    clean build 2>&1 | grep -E "(BUILD|error:)" | tail -5

BINARY="./build-xcode/Build/Products/Release/TidalDrift"
if [ ! -f "$BINARY" ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Build successful${NC}"
echo ""

# ========== STEP 4: CREATE APP BUNDLE ==========
echo -e "${BLUE}📦 Step 4: Creating app bundle...${NC}"

# Clean xattrs from build products BEFORE copying
xattr -cr ./build-xcode/Build/Products/Release/

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy and immediately clean
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/"
[ -f "Resources/AppIcon.icns" ] && cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
[ -d "./build-xcode/Build/Products/Release/TidalDrift_TidalDrift.bundle" ] && \
    cp -R ./build-xcode/Build/Products/Release/TidalDrift_TidalDrift.bundle "$APP_BUNDLE/Contents/Resources/"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TidalDrift</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>TidalDrift</string>
    <key>CFBundleDisplayName</key><string>TidalDrift</string>
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
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# CRITICAL: Clean ALL xattrs recursively
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -print0 | xargs -0 xattr -c 2>/dev/null || true

echo -e "${GREEN}  ✓ App bundle created${NC}"
echo ""

# ========== STEP 5: SIGN ==========
echo -e "${BLUE}🔏 Step 5: Signing...${NC}"
codesign --force --deep --options runtime \
    --sign "$DEV_ID" \
    --timestamp \
    --entitlements TidalDrift.entitlements \
    "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
echo -e "${GREEN}  ✓ Signed${NC}"
echo ""

# ========== STEP 6: CREATE DMG ==========
echo -e "${BLUE}💿 Step 6: Creating DMG...${NC}"
DMG_FINAL="${RELEASE_DIR}/${DMG_NAME}.dmg"
rm -rf "${RELEASE_DIR}/dmg-staging" "$DMG_FINAL"
mkdir -p "${RELEASE_DIR}/dmg-staging"
cp -R "$APP_BUNDLE" "${RELEASE_DIR}/dmg-staging/"
ln -s /Applications "${RELEASE_DIR}/dmg-staging/Applications"
xattr -cr "${RELEASE_DIR}/dmg-staging"
hdiutil create -volname "$APP_NAME" -srcfolder "${RELEASE_DIR}/dmg-staging" -ov -format UDZO "$DMG_FINAL"
rm -rf "${RELEASE_DIR}/dmg-staging"
codesign --force --sign "$DEV_ID" --timestamp "$DMG_FINAL"
echo -e "${GREEN}  ✓ DMG created${NC}"
echo ""

# ========== STEP 7: NOTARIZE ==========
if [ "$SKIP_NOTARIZE" = true ]; then
    echo -e "${YELLOW}⏭️  Skipping notarization${NC}"
else
    echo -e "${BLUE}📤 Step 7: Notarizing...${NC}"
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null; then
        if [ -n "$APPLE_ID" ] && [ -n "$TEAM_ID" ] && [ -n "$APP_SPECIFIC_PASSWORD" ]; then
            xcrun notarytool store-credentials "$NOTARY_PROFILE" \
                --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PASSWORD"
        else
            echo -e "${YELLOW}⚠️  No credentials. Skipping notarization.${NC}"
            SKIP_NOTARIZE=true
        fi
    fi
    if [ "$SKIP_NOTARIZE" = false ]; then
        xcrun notarytool submit "$DMG_FINAL" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG_FINAL"
        echo -e "${GREEN}  ✓ Notarized${NC}"
    fi
fi

# Cleanup
rm -rf build-xcode "$APP_BUNDLE"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            🎉 Done! ${DMG_NAME}.dmg${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Size: $(du -h "$DMG_FINAL" | cut -f1)"
echo "  Path: $DMG_FINAL"
echo ""
