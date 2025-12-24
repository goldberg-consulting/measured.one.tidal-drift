import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSection
            
            Divider()
                .padding(.vertical, 8)
            
            devicesSection
            
            Divider()
                .padding(.vertical, 8)
            
            actionsSection
        }
        .padding(12)
        .frame(width: 280)
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundColor(appState.screenSharingEnabled ? .green : .secondary)
                Text("Screen Sharing")
                Spacer()
                Text(appState.screenSharingEnabled ? "On" : "Off")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(appState.fileSharingEnabled ? .green : .secondary)
                Text("File Sharing")
                Spacer()
                Text(appState.fileSharingEnabled ? "On" : "Off")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }
    
    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nearby Devices")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
            
            if appState.discoveredDevices.isEmpty {
                Text("No devices found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(appState.discoveredDevices.prefix(5)) { device in
                    MenuBarDeviceRow(device: device)
                }
                
                if appState.discoveredDevices.count > 5 {
                    Text("+ \(appState.discoveredDevices.count - 5) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: 4) {
            Button {
                NetworkDiscoveryService.shared.refreshScan()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Scan Network")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            Button {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "") {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
            } label: {
                HStack {
                    Image(systemName: "macwindow")
                    Text("Open TidalDrift")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            Button {
                appState.hasCompletedOnboarding = false
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Run Setup Wizard")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            Divider()
                .padding(.vertical, 4)
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Quit")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct MenuBarDeviceRow: View {
    let device: DiscoveredDevice
    @State private var isHovering = false
    
    var body: some View {
        Button {
            connectToDevice()
        } label: {
            HStack {
                Image(systemName: device.deviceIcon)
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                
                Text(device.name)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func connectToDevice() {
        Task {
            if device.services.contains(.screenSharing) {
                try? await ScreenShareConnectionService.shared.connect(to: device)
            } else if device.services.contains(.fileSharing) {
                try? await ScreenShareConnectionService.shared.connectToFileShare(device: device)
            }
        }
    }
}

struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView()
            .environmentObject(AppState.shared)
    }
}
