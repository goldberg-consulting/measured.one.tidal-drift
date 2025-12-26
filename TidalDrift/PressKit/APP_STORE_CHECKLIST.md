# TidalDrift App Store Submission Checklist

## ⚠️ Important: Sandbox Considerations

TidalDrift currently runs **without sandbox** (`com.apple.security.app-sandbox: false`).

This is because the app needs to:
- Execute AppleScript with admin privileges (to toggle Screen Sharing, File Sharing, SSH)
- Run `dns-sd` command-line tool for Bonjour discovery
- Run `launchctl` commands for service management
- Access network ports for peer discovery and file transfer

### Options for Distribution:

| Method | Sandbox Required | Notes |
|--------|------------------|-------|
| **Direct Download** | No | Recommended for v1.0 - Full functionality |
| **Mac App Store** | Yes* | Would need to remove admin features or request entitlements |
| **Developer ID** | No | Notarized, distributed outside App Store |

*Apple may grant exceptions for utility apps with proper justification.

---

## Pre-Submission Checklist

### 1. Code & Build ✅
- [ ] Remove all `print()` statements or wrap in `#if DEBUG`
- [ ] Remove any hardcoded developer paths
- [ ] Ensure all API calls handle errors gracefully
- [ ] Test on clean macOS installation
- [ ] Test on both Intel and Apple Silicon

### 2. Info.plist ✅
- [x] CFBundleDisplayName set
- [x] CFBundleIdentifier set (com.goldbergconsulting.tidaldrift)
- [x] CFBundleVersion incremented
- [x] CFBundleShortVersionString set
- [x] LSMinimumSystemVersion set (13.0)
- [x] NSLocalNetworkUsageDescription set
- [x] NSBonjourServices listed
- [x] NSHumanReadableCopyright set
- [x] CFBundleIconFile/CFBundleIconName set

### 3. Entitlements
- [x] com.apple.security.network.client (for outgoing connections)
- [x] com.apple.security.network.server (for incoming connections)
- [x] com.apple.security.files.user-selected.read-write (for TidalDrop)
- [ ] Consider adding: com.apple.security.automation.apple-events (for AppleScript)

### 4. App Icon
- [ ] 16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024 PNG
- [ ] AppIcon.icns in Resources
- [ ] No transparency issues
- [ ] Readable at small sizes

### 5. Screenshots (for App Store)
- [ ] 1280x800 or 1440x900 minimum
- [ ] At least 3 screenshots showing key features
- [ ] No personal information visible
- [ ] Shows realistic usage

### 6. App Store Connect
- [ ] App name reserved
- [ ] Privacy policy URL
- [ ] Support URL
- [ ] Marketing URL (optional)
- [ ] App description (see PressKit/README.md)
- [ ] Keywords (see PressKit/README.md)
- [ ] Category: Utilities

### 7. Testing
- [ ] Test fresh install (no prior settings)
- [ ] Test upgrade from previous version
- [ ] Test all onboarding steps
- [ ] Test screen sharing connection
- [ ] Test file sharing connection
- [ ] Test SSH connection
- [ ] Test TidalDrop (send and receive)
- [ ] Test on slow network
- [ ] Test with firewall enabled

### 8. Privacy
- [ ] No analytics/tracking code
- [ ] No external network calls (except local network)
- [ ] Keychain usage documented
- [ ] No data leaves the local network

---

## Known Limitations for App Store

These features may need modification for App Store compliance:

1. **Admin Privilege Operations**
   - Screen Sharing toggle (requires `with administrator privileges`)
   - File Sharing toggle
   - SSH/Remote Login toggle
   - Firewall configuration
   
   *Alternative: Open System Settings directly instead of toggling programmatically*

2. **Shell Command Execution**
   - `dns-sd` for Bonjour discovery
   - `launchctl` for service management
   
   *Alternative: Use native Network.framework APIs (may have permission issues)*

3. **Process Spawning**
   - Opens Terminal.app for SSH
   - Opens Screen Sharing.app for VNC
   
   *This should be allowed as it uses system apps*

---

## Recommended Distribution Path

For initial release, consider:

1. **Phase 1: Direct Download (Current)**
   - Full functionality
   - Notarize with Developer ID
   - Distribute via website

2. **Phase 2: Mac App Store (Future)**
   - Sandbox-compatible subset
   - Remove admin toggle features
   - Keep discovery and connection features

---

## Build for Distribution

```bash
# Clean build
rm -rf .build TidalDrift.app

# Build release
swift build -c release

# Create app bundle
./build-app.sh

# Notarize (requires Apple Developer account)
xcrun notarytool submit TidalDrift.app \
  --apple-id "your-apple-id" \
  --team-id "YOUR_TEAM_ID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# Staple
xcrun stapler staple TidalDrift.app

# Verify
spctl --assess --verbose TidalDrift.app
```

---

## Version History

| Version | Build | Date | Notes |
|---------|-------|------|-------|
| 1.3.0 | 4 | 2024-12 | App Store prep, experimental features hidden |
| 1.2.0 | 3 | 2024-12 | Performance fixes |
| 1.1.0 | 2 | 2024-12 | TidalDrop improvements |
| 1.0.0 | 1 | 2024-12 | Initial release |

