#!/bin/bash

# TidalDrift Release Builder v1.3.16
# Uses xcodebuild + ditto --norsrc to avoid resource fork issues
# Requires: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

set -e

APP_NAME="TidalDrift"
BUNDLE_ID="com.goldbergconsulting.tidaldrift"
VERSION="1.4.1"
DMG_NAME="${APP_NAME}-${VERSION}"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env" && echo -e "${BLUE}📋 Loaded .env${NC}"

NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"
RELEASE_DIR="$(pwd)/dist"
APP_BUNDLE="$APP_NAME.app"

SKIP_NOTARIZE=false
for arg in "$@"; do [[ "$arg" == "--skip-notarize" ]] && SKIP_NOTARIZE=true; done

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     🌊 TidalDrift Release Builder v${VERSION}              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verify Xcode
[[ "$(xcode-select -p)" != *"Xcode.app"* ]] && echo -e "${RED}❌ Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer${NC}" && exit 1
echo -e "${GREEN}✓ Xcode${NC}"

# Cleanup
pkill -9 -f "TidalDrift" 2>/dev/null || true; pkill -9 swift 2>/dev/null || true
rm -rf "$APP_BUNDLE" build-xcode
echo -e "${GREEN}✓ Cleanup${NC}"

# Reset ALL TCC permissions (code signature changes on every rebuild, invalidating old grants)
for TCC_SERVICE in ScreenCapture Accessibility ListenEvent LocalNetwork; do
    tccutil reset "$TCC_SERVICE" "$BUNDLE_ID" 2>/dev/null || true
done
echo -e "${GREEN}✓ TCC permissions reset: ScreenCapture, Accessibility, ListenEvent, LocalNetwork${NC}"

# Certificate
DEV_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
[ -z "$DEV_ID" ] && echo -e "${RED}❌ No Developer ID${NC}" && exit 1
echo -e "${GREEN}✓ Certificate${NC}"

# Clean source xattrs before build
echo -e "${BLUE}🧹 Cleaning source xattrs...${NC}"
find Resources -type f -exec xattr -c {} \; 2>/dev/null || true
echo -e "${GREEN}✓ Source cleaned${NC}"

# Build
echo -e "${BLUE}🔨 Building...${NC}"
mkdir -p dist
xcodebuild -scheme TidalDrift -configuration Release -destination 'platform=macOS' -derivedDataPath ./build-xcode clean build 2>&1 | grep -E "(BUILD|error:)" | tail -3
[ ! -f "./build-xcode/Build/Products/Release/TidalDrift" ] && echo -e "${RED}❌ Build failed${NC}" && exit 1
echo -e "${GREEN}✓ Build${NC}"

# Create bundle using ditto --norsrc (strips resource forks)
echo -e "${BLUE}📦 Creating bundle...${NC}"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
ditto --norsrc ./build-xcode/Build/Products/Release/TidalDrift "$APP_BUNDLE/Contents/MacOS/TidalDrift"
[ -f "Resources/AppIcon.icns" ] && ditto --norsrc Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
[ -d "./build-xcode/Build/Products/Release/TidalDrift_TidalDrift.bundle" ] && \
    ditto --norsrc ./build-xcode/Build/Products/Release/TidalDrift_TidalDrift.bundle "$APP_BUNDLE/Contents/Resources/TidalDrift_TidalDrift.bundle"

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>TidalDrift</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>TidalDrift</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>TidalDrift discovers Macs on your network.</string>
    <key>NSBonjourServices</key><array><string>_rfb._tcp</string><string>_smb._tcp</string><string>_afpovertcp._tcp</string><string>_ssh._tcp</string><string>_tidaldrift._tcp</string><string>_tidaldrop._tcp</string><string>_tidaldrift-cast._udp</string><string>_tidalclip._tcp</string><string>_tidalstream._tcp</string></array>
</dict></plist>
EOF
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# CRITICAL: Remove ALL xattrs from bundle before signing
echo -e "${BLUE}🧹 Removing all xattrs from bundle...${NC}"
find "$APP_BUNDLE" -type f -exec xattr -c {} \; 2>/dev/null || true
find "$APP_BUNDLE" -type d -exec xattr -c {} \; 2>/dev/null || true
xattr -rc "$APP_BUNDLE" 2>/dev/null || true

echo -e "${GREEN}✓ Bundle${NC}"

# Sign
echo -e "${BLUE}🔏 Signing...${NC}"
codesign --force --deep --options runtime --sign "$DEV_ID" --timestamp --entitlements TidalDrift.entitlements "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
echo -e "${GREEN}✓ Signed${NC}"

# DMG
echo -e "${BLUE}💿 Creating DMG...${NC}"
DMG_FINAL="${RELEASE_DIR}/${DMG_NAME}.dmg"
rm -rf "${RELEASE_DIR}/dmg-staging" "$DMG_FINAL"
mkdir -p "${RELEASE_DIR}/dmg-staging"
ditto --norsrc "$APP_BUNDLE" "${RELEASE_DIR}/dmg-staging/$APP_BUNDLE"
ln -s /Applications "${RELEASE_DIR}/dmg-staging/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "${RELEASE_DIR}/dmg-staging" -ov -format UDZO "$DMG_FINAL"
rm -rf "${RELEASE_DIR}/dmg-staging"
codesign --force --sign "$DEV_ID" --timestamp "$DMG_FINAL"
echo -e "${GREEN}✓ DMG${NC}"

# Notarize
if [ "$SKIP_NOTARIZE" = true ]; then
    echo -e "${YELLOW}⏭️  Skipping notarization${NC}"
else
    echo -e "${BLUE}📤 Notarizing...${NC}"
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null; then
        [ -n "$APPLE_ID" ] && [ -n "$TEAM_ID" ] && [ -n "$APP_SPECIFIC_PASSWORD" ] && \
            xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PASSWORD"
    fi
    xcrun notarytool submit "$DMG_FINAL" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_FINAL"
    echo -e "${GREEN}✓ Notarized${NC}"
fi

rm -rf build-xcode "$APP_BUNDLE"

# Copy to network share for easy install on other Macs
SMB_MOUNT="/Volumes/Eli Goldberg's Public Folder"
SMB_URL="smb://US_LDHG427053._smb._tcp.local/Eli Goldberg's Public Folder/"

if [ -d "$SMB_MOUNT" ]; then
    echo -e "${BLUE}📂 Copying to network share...${NC}"
    cp "$DMG_FINAL" "$SMB_MOUNT/"
    echo -e "${GREEN}✓ Copied to $SMB_MOUNT/${NC}"
else
    echo -e "${BLUE}📂 Mounting network share...${NC}"
    if osascript -e "mount volume \"$SMB_URL\"" 2>/dev/null; then
        sleep 2
        if [ -d "$SMB_MOUNT" ]; then
            cp "$DMG_FINAL" "$SMB_MOUNT/"
            echo -e "${GREEN}✓ Copied to $SMB_MOUNT/${NC}"
        else
            echo -e "${YELLOW}⚠️  Mount succeeded but folder not found — copy manually${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Could not mount network share — copy manually${NC}"
        echo "   open \"$SMB_URL\""
    fi
fi

echo ""
echo -e "${GREEN}🎉 Done! ${DMG_NAME}.dmg ($(du -h "$DMG_FINAL" | cut -f1))${NC}"
echo "   $DMG_FINAL"
