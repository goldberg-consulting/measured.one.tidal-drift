#!/bin/bash

# TidalDrift Release Builder
# Creates a signed, notarized DMG for distribution
#
# Prerequisites:
# 1. Developer ID Application certificate in Keychain
# 2. Developer ID Installer certificate (optional, for pkg)
# 3. App-specific password stored in Keychain:
#    xcrun notarytool store-credentials "notarytool-profile" \
#      --apple-id "your@email.com" \
#      --team-id "YOUR_TEAM_ID" \
#      --password "app-specific-password"
#
# Usage:
#   ./build-release.sh              # Build and notarize
#   ./build-release.sh --skip-notarize  # Build only (for testing)

set -e

# Configuration
APP_NAME="TidalDrift"
BUNDLE_ID="com.goldbergconsulting.tidaldrift"
VERSION="1.3.11"
DMG_NAME="${APP_NAME}-${VERSION}"

# Load credentials from .env if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
    echo -e "${BLUE}📋 Loaded credentials from .env${NC}"
fi

# Signing identity - update this to your Developer ID
# List available identities: security find-identity -v -p codesigning
DEVELOPER_ID_APP="Developer ID Application: Eli Goldberg (97UY84BV45)"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"

# Output directories
BUILD_DIR="$(pwd)"
RELEASE_DIR="$BUILD_DIR/release"
APP_BUNDLE="$APP_NAME.app"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

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

# Step 1: Check for Developer ID
echo -e "${BLUE}🔍 Checking for Developer ID certificate...${NC}"
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo -e "${RED}❌ No Developer ID Application certificate found!${NC}"
    echo ""
    echo "Available identities:"
    security find-identity -v -p codesigning
    echo ""
    echo "To proceed, you need a Developer ID Application certificate from Apple."
    echo "Or use: ./build-app.sh for local ad-hoc signing."
    exit 1
fi

# Show available Developer IDs
echo "Available Developer ID certificates:"
security find-identity -v -p codesigning | grep "Developer ID Application" || true
echo ""

# Step 2: Kill running instances
if pgrep -f "TidalDrift" > /dev/null 2>&1; then
    echo -e "${YELLOW}🔪 Killing running TidalDrift instances...${NC}"
    pkill -f "TidalDrift" 2>/dev/null || true
    sleep 1
fi

# Step 3: Clean build
echo -e "${BLUE}🧹 Cleaning previous build...${NC}"
rm -rf .build
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Step 4: Build release binary
echo -e "${BLUE}🔨 Building release binary...${NC}"
swift build -c release

# Step 5: Create app bundle
echo -e "${BLUE}📦 Creating app bundle...${NC}"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp .build/release/TidalDrift "$APP_BUNDLE/Contents/MacOS/"

# Copy icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
fi

# Copy bundle resources
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
        <string>_ssh._tcp</string>
        <string>_tidaldrift._tcp</string>
        <string>_tidalclip._tcp</string>
        <string>_tidalstream._tcp</string>
        <string>_tidaldrop._tcp</string>
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

# Step 6: Sign the app with Developer ID
echo -e "${BLUE}🔏 Signing app with Developer ID...${NC}"

# Get the actual Developer ID identity
DEV_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')

if [ -z "$DEV_ID" ]; then
    echo -e "${RED}❌ Could not find Developer ID Application certificate${NC}"
    exit 1
fi

echo "Using identity: $DEV_ID"

# Sign with hardened runtime (required for notarization)
codesign --force --deep --options runtime \
    --sign "$DEV_ID" \
    --timestamp \
    --entitlements TidalDrift.entitlements \
    "$APP_BUNDLE"

# Verify signature
echo -e "${BLUE}✓ Verifying signature...${NC}"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# Step 7: Create DMG
echo -e "${BLUE}💿 Creating DMG...${NC}"

DMG_TEMP="${RELEASE_DIR}/${DMG_NAME}-temp.dmg"
DMG_FINAL="${RELEASE_DIR}/${DMG_NAME}.dmg"

# Create staging directory for DMG contents
DMG_STAGING="${RELEASE_DIR}/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app to staging
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create Applications symlink
ln -s /Applications "$DMG_STAGING/Applications"

# Create the DMG directly from the staging folder
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_FINAL"

# Cleanup staging
rm -rf "$DMG_STAGING"

# Step 8: Sign the DMG
echo -e "${BLUE}🔏 Signing DMG...${NC}"
codesign --force --sign "$DEV_ID" --timestamp "$DMG_FINAL"

# Verify DMG signature
codesign --verify --verbose "$DMG_FINAL"

echo -e "${GREEN}✅ DMG created and signed: $DMG_FINAL${NC}"

# Step 9: Notarize (unless skipped)
if [ "$SKIP_NOTARIZE" = true ]; then
    echo -e "${YELLOW}⏭️  Skipping notarization (--skip-notarize flag)${NC}"
else
    echo -e "${BLUE}📤 Submitting for notarization...${NC}"
    echo "This may take several minutes..."
    
    # Check if notary profile exists, create from .env if not
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null; then
        echo -e "${YELLOW}⚠️  Notary profile '$NOTARY_PROFILE' not found in Keychain.${NC}"
        
        # Try to create from .env credentials
        if [ -n "$APPLE_ID" ] && [ -n "$TEAM_ID" ] && [ -n "$APP_SPECIFIC_PASSWORD" ]; then
            echo -e "${BLUE}🔐 Creating notary profile from .env credentials...${NC}"
            xcrun notarytool store-credentials "$NOTARY_PROFILE" \
                --apple-id "$APPLE_ID" \
                --team-id "$TEAM_ID" \
                --password "$APP_SPECIFIC_PASSWORD"
            echo -e "${GREEN}✓ Notary profile created${NC}"
        else
            echo ""
            echo "To set up notarization credentials, either:"
            echo ""
            echo "1. Create a .env file with:"
            echo "   APPLE_ID=\"your@email.com\""
            echo "   TEAM_ID=\"YOUR_TEAM_ID\""
            echo "   APP_SPECIFIC_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
            echo ""
            echo "2. Or run manually:"
            echo "   xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
            echo "     --apple-id \"your@email.com\" \\"
            echo "     --team-id \"YOUR_TEAM_ID\" \\"
            echo "     --password \"your-app-specific-password\""
            echo ""
            echo -e "${YELLOW}DMG was created but NOT notarized.${NC}"
            exit 0
        fi
    fi
    
    # Submit for notarization
    xcrun notarytool submit "$DMG_FINAL" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    
    # Step 10: Staple the ticket
    echo -e "${BLUE}📎 Stapling notarization ticket...${NC}"
    xcrun stapler staple "$DMG_FINAL"
    
    # Verify stapling
    xcrun stapler validate "$DMG_FINAL"
    
    echo -e "${GREEN}✅ Notarization complete and stapled!${NC}"
fi

# Final summary
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            🎉 Release Build Complete!                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Version:    ${BLUE}${VERSION}${NC}"
echo -e "  DMG:        ${BLUE}${DMG_FINAL}${NC}"
echo -e "  Size:       $(du -h "$DMG_FINAL" | cut -f1)"
echo ""

if [ "$SKIP_NOTARIZE" = false ]; then
    echo -e "  Status:     ${GREEN}✅ Signed & Notarized${NC}"
    echo ""
    echo "  This DMG is ready for distribution!"
else
    echo -e "  Status:     ${YELLOW}⚠️  Signed (not notarized)${NC}"
    echo ""
    echo "  Run without --skip-notarize to notarize for public distribution."
fi

echo ""
echo "  To test: open \"$DMG_FINAL\""
echo ""

