# TidalDrift

A menu-bar Mac utility for discovering, connecting to, and streaming between Macs on your local network. Built entirely with Apple frameworks -- no external dependencies.

TidalDrift replaces the clunky workflow of opening System Settings, toggling sharing services, remembering IP addresses, and launching Screen Sharing.app. It lives in your menu bar, discovers every Mac on your LAN via Bonjour, and gives you one-click access to screen sharing (VNC), file sharing (SMB), SSH, and its own low-latency streaming engine called LocalCast.

## Features

**Menu-Bar Command Center**
- Lives entirely in the menu bar -- no main window needed
- Compact popover shows your Mac's sharing status, all discovered devices, and inline action buttons
- One-click LocalCast, VNC, SMB, and SSH connections from any device row
- Drag files onto the Dock icon to send to multiple devices at once

**LocalCast -- Low-Latency Screen Streaming**
- Custom streaming engine: ScreenCaptureKit capture, VideoToolbox H.264/HEVC encoding, Metal rendering, raw UDP transport
- Sub-frame latency on gigabit LAN -- noticeably faster than VNC
- Stream full display or a single app window
- End-to-end AES-256-GCM encryption with HKDF-SHA256 key derivation
- Retina-quality with adaptive resolution (720p to 4K)
- Remote mouse and keyboard input with configurable rate limiting
- Live quality tuning slider synced between client and host

**Network Discovery**
- Bonjour/mDNS service browsing for `_rfb._tcp`, `_smb._tcp`, `_ssh._tcp`, and TidalDrift peers
- Subnet scanning for devices that don't advertise services
- Rich peer metadata broadcast (model, CPU, memory, macOS version, uptime)
- Connection history and saved credentials in Keychain

**TidalDrop -- Peer-to-Peer File Transfer**
- Drop files onto any device card or use the Dock icon
- Transfers via mounted SMB share when available, falls back to direct TCP
- Configurable destination folder

**Other**
- Wake-on-LAN with MAC auto-discovery
- Clipboard sync between Macs
- Guided setup wizard for Screen Sharing, File Sharing, SSH, and Firewall
- Built-in integration test suite (22 tests covering Bonjour, networking, crypto, file transfer, and streaming)

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ with Swift 5.9+ for building

## Building

TidalDrift uses Swift Package Manager. The project builds with either `xcodebuild` or `swift build`.

### Development Build (recommended)

The dev build script handles signing, DMG creation, installation to `/Applications`, and TCC permission resets:

```bash
cd TidalDrift
chmod +x build-app.sh
./build-app.sh
```

This requires:
- Xcode selected: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- A Developer ID certificate in your Keychain (falls back to ad-hoc signing if unavailable)

### Release Build (signed + notarized)

```bash
cd TidalDrift
chmod +x build-release.sh
./build-release.sh
```

The release build adds hardened runtime, notarization via Apple's notary service, and ticket stapling. It requires a `.env` file -- see [Configuration](#configuration) below.

To skip notarization (sign only):

```bash
./build-release.sh --skip-notarize
```

### Swift Package Manager

```bash
cd TidalDrift
swift build
```

Note: `swift build` compiles the code but does not create an `.app` bundle with the required `Info.plist`, entitlements, or code signing. Use `build-app.sh` for a runnable app.

## Permissions

TidalDrift requests several macOS permissions on first use:

| Permission | Purpose |
|---|---|
| **Screen Recording** | Required for LocalCast host to capture the screen |
| **Accessibility** | Required for remote input injection (mouse/keyboard) on the host |
| **Local Network** | Required for Bonjour discovery and direct connections |

The build scripts automatically reset TCC permissions on each rebuild since code signature changes invalidate previous grants.

## Architecture

```
TidalDrift/
  App/                    # App entry point, delegate, state management
  Views/
    MenuBarView.swift     # Primary UI -- menu bar popover
    DropTargetPicker.swift # Multi-device file send picker
    Settings/             # Settings window tabs (incl. test suite)
    Dashboard/            # Device grid/list views (legacy, kept for reference)
    DeviceDetail/         # Standalone device detail windows
    Onboarding/           # First-run setup wizard
  LocalCast/
    Core/                 # Configuration, service, permissions
    Host/                 # Screen capture, video encoding, input injection
    Client/               # Session management, video decoding
    Transport/            # UDP transport, packet protocol
    Security/             # AES-256-GCM crypto, HKDF key derivation
    Views/                # Viewer window, quality controls, app picker
  Services/               # Bonjour, TidalDrop, clipboard sync, discovery
    TestSuite/            # In-app integration tests
  Models/                 # DiscoveredDevice, ConnectionRecord, AppSettings
  ViewModels/             # Dashboard/device detail view models
  Utilities/              # NetworkUtils, ShellExecutor
```

## Configuration

### Notarization credentials (`TidalDrift/.env`)

The release build script sources `TidalDrift/.env` for Apple notarization credentials. This file is gitignored and must never be committed.

```bash
cp TidalDrift/.env.example TidalDrift/.env
```

Then edit `TidalDrift/.env` with your values:

| Variable | Description | Where to get it |
|---|---|---|
| `APPLE_ID` | Your Apple Developer account email | [developer.apple.com](https://developer.apple.com) |
| `TEAM_ID` | Your 10-character Apple Developer Team ID | Xcode > Settings > Accounts > Team ID, or [Membership](https://developer.apple.com/account#MembershipDetailsCard) |
| `APP_SPECIFIC_PASSWORD` | An app-specific password for notarytool | [appleid.apple.com](https://appleid.apple.com) > Sign-In and Security > App-Specific Passwords |
| `NOTARY_PROFILE` | Keychain profile name (default: `notarytool-profile`) | Auto-created by the build script on first run |

On the first notarization run, the script stores these credentials in your login keychain under the profile name so subsequent runs don't need the plaintext values. You can also store them manually:

```bash
xcrun notarytool store-credentials "notarytool-profile" \
  --apple-id "you@example.com" \
  --team-id "XXXXXXXXXX" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### Developer ID certificate

Both build scripts require a **Developer ID Application** certificate in your Keychain. The dev build (`build-app.sh`) falls back to ad-hoc signing if none is found; the release build (`build-release.sh`) will exit with an error.

Verify your certificate is installed:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

## Running Tests

Tests run inside the app itself. Launch TidalDrift, open **Settings > Tests**, and click **Run All Tests**. The suite covers:

- **Permissions** -- Screen Recording, Accessibility, network availability
- **Bonjour** -- Service advertising, self-discovery, LocalCast UDP browse
- **Network** -- TCP/UDP port binding, loopback echo roundtrips
- **Security** -- Key generation, HKDF derivation, AES-GCM encrypt/decrypt, tamper detection
- **TidalDrop** -- Loopback file transfer (small and large), destination folder validation
- **LocalCast** -- Streaming tuning interpolation, packet protocol serialization, host session lifecycle

## License

MIT License. See [LICENSE](LICENSE) for details.

## Credits

Developed by [Goldberg Consulting, LLC d/b/a Measured.One](https://measured.one).
