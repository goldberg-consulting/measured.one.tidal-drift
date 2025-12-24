# TidalDrift - macOS Network Sharing App

## Project Overview

This is a **native macOS application** source code project. It cannot be compiled or run on Replit because Replit runs Linux, not macOS.

## Project Type
- **Platform**: macOS 13.0+ (Ventura)
- **Language**: Swift 5.9
- **Framework**: SwiftUI
- **Architecture**: MVVM

## How to Use This Project

1. Download the `TidalDrift` folder
2. Open on a Mac with Xcode 15+ installed
3. Create a new macOS App project in Xcode
4. Import all source files from the TidalDrift folder
5. Configure entitlements and Info.plist
6. Build and run

## File Structure

```
TidalDrift/
├── App/           - Main app entry point and state
├── Views/         - SwiftUI views organized by feature
├── ViewModels/    - MVVM view models
├── Services/      - Business logic services
├── Models/        - Data models
├── Utilities/     - Helper utilities
├── Resources/     - Assets and localization
├── Info.plist     - App configuration
├── TidalDrift.entitlements - Security entitlements
└── Package.swift  - Swift Package Manager config
```

## Key Features

- Bonjour/mDNS network discovery for Macs
- Screen sharing via VNC
- SMB file sharing connections
- Secure Keychain credential storage
- Menu bar quick access
- Beautiful SwiftUI interface

## Dependencies

All dependencies are built-in macOS frameworks:
- SwiftUI
- Network.framework
- ServiceManagement
- Security
- LocalAuthentication
- CoreWLAN
- SystemConfiguration

## Notes

- LSP errors shown are expected - Swift/macOS code cannot be validated on Linux
- No workflows needed - this is source code for macOS development
