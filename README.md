# TidalDrift

A beautiful native macOS application for seamless Mac-to-Mac network sharing, screen sharing, and file sharing discovery.

## Features

- **Network Discovery**: Automatically discover other Macs on your local network using Bonjour/mDNS
- **Screen Sharing**: Connect to other Macs for remote screen viewing and control
- **File Sharing**: Access shared files and folders on discovered Macs
- **Trusted Devices**: Mark devices as trusted for quick one-click connections
- **Credential Management**: Securely store credentials in macOS Keychain
- **Menu Bar Integration**: Quick access to devices from the menu bar
- **Beautiful UI**: Modern SwiftUI interface with light/dark mode support

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (for building)

## Installation

### Option 1: Build with Xcode

1. Download the `TidalDrift` folder to your Mac
2. Open Xcode and create a new macOS App project named "TidalDrift"
3. Delete the auto-generated files and copy the source files from this folder
4. Configure the project:
   - Set deployment target to macOS 13.0
   - Add the entitlements file to the project
   - Set the Info.plist in build settings
5. Build and run (Cmd+R)

### Option 2: Create Xcode Project Manually

1. Open Xcode → File → New → Project
2. Select "macOS" → "App"
3. Product Name: TidalDrift
4. Interface: SwiftUI
5. Language: Swift
6. Copy all files from the `TidalDrift` folder into your project
7. Add required frameworks: Network, ServiceManagement, Security, LocalAuthentication

## Project Structure

```
TidalDrift/
├── App/
│   ├── TidalDriftApp.swift      # Main app entry point
│   ├── AppDelegate.swift        # App delegate for notifications
│   ├── AppState.swift           # Global app state
│   └── ContentView.swift        # Root content view
├── Views/
│   ├── Onboarding/              # Setup wizard views
│   ├── Dashboard/               # Main dashboard views
│   ├── DeviceDetail/            # Device detail sheet
│   ├── Settings/                # Settings views
│   └── Components/              # Reusable UI components
├── ViewModels/                  # MVVM view models
├── Services/
│   ├── NetworkDiscoveryService  # Bonjour discovery
│   ├── SharingConfigurationService  # System sharing status
│   ├── ScreenShareConnectionService # VNC connections
│   ├── KeychainService          # Secure credential storage
│   └── SettingsService          # App settings management
├── Models/                      # Data models
├── Utilities/                   # Network & shell utilities
└── Resources/                   # Assets and localization
```

## Usage

### First Launch
1. The app will guide you through enabling Screen Sharing and File Sharing on your Mac
2. Follow the onboarding wizard to configure system settings

### Discovering Devices
- The app automatically scans for Macs on your local network
- Click "Scan Network" to refresh the device list
- Use "Add Device" to manually add a device by IP address

### Connecting
1. Click on a discovered device
2. Choose "Screen Share" or "File Share"
3. Enter credentials if prompted
4. Optionally save credentials to Keychain

### Trusted Devices
- Mark devices as "trusted" for quick access
- Trusted devices appear prominently in the dashboard

## Privacy & Security

- **Local Network Only**: All connections stay on your local network
- **Keychain Storage**: Credentials are encrypted in macOS Keychain
- **No Cloud Services**: No data is sent to external servers
- **Touch ID Support**: Optional biometric authentication

## Entitlements

The app requires these entitlements:
- `com.apple.security.network.client` - Network connections
- `com.apple.security.network.server` - Accept incoming connections
- `com.apple.security.files.user-selected.read-write` - File access
- Keychain access groups for credential storage

## Building Notes

Since this project was created in Replit (which runs Linux), it cannot be compiled or run here. You need to:

1. Download the TidalDrift folder
2. Open on a Mac with Xcode installed
3. Create a new Xcode project and import the source files
4. Build and run on macOS 13.0+

## License

MIT License - feel free to modify and distribute.

## Support

For issues and feature requests, please create an issue in the repository.
