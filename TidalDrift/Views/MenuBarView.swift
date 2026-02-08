import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var localCast = LocalCastService.shared
    @State private var isTogglingLocalCast = false
    @State private var showPermissionAlert = false
    @State private var permissionAlertMessage = ""
    
    // Filter out the current device - only show other devices
    private var otherDevices: [DiscoveredDevice] {
        appState.discoveredDevices.filter { !$0.isCurrentDevice }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSection
            
            Divider()
                .padding(.vertical, 8)
            
            localCastSection
            
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
    
    private var localCastSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(localCast.isHosting ? .yellow : .secondary)
                Text("LocalCast Hosting")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                
                if isTogglingLocalCast {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 40)
                } else {
                    Toggle("", isOn: Binding(
                        get: { localCast.isHosting },
                        set: { newValue in
                            isTogglingLocalCast = true
                            Task {
                                if newValue {
                                    do {
                                        print("🌊 MenuBar: Toggle ON - calling startHosting()")
                                        try await localCast.startHosting()
                                        print("🌊 MenuBar: startHosting() succeeded")
                                    } catch let error as LocalCastError {
                                        print("🌊 MenuBar: ❌ startHosting() failed: \(error)")
                                        await MainActor.run {
                                            permissionAlertMessage = error.errorDescription ?? "Failed to start LocalCast"
                                            showPermissionAlert = true
                                        }
                                    } catch {
                                        print("🌊 MenuBar: ❌ startHosting() failed: \(error)")
                                        await MainActor.run {
                                            permissionAlertMessage = error.localizedDescription
                                            showPermissionAlert = true
                                        }
                                    }
                                } else {
                                    print("🌊 MenuBar: Toggle OFF - calling stopHosting()")
                                    localCast.stopHosting()
                                }
                                await MainActor.run {
                                    isTogglingLocalCast = false
                                }
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .labelsHidden()
                }
            }
            .alert("LocalCast Permission Required", isPresented: $showPermissionAlert) {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(permissionAlertMessage + "\n\nPlease grant Accessibility permission to TidalDrift, then try again.")
            }
            
            if localCast.isHosting {
                VStack(alignment: .leading, spacing: 4) {
                    if !localCast.activeConnections.isEmpty {
                        ForEach(localCast.activeConnections) { conn in
                            HStack {
                                Image(systemName: "display")
                                    .font(.caption)
                                Text(conn.clientName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("Waiting for connections...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(.leading, 24)
            }
        }
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
            
            if otherDevices.isEmpty {
                Text("No devices found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(otherDevices.prefix(5)) { device in
                    MenuBarDeviceRow(device: device)
                }
                
                if otherDevices.count > 5 {
                    Text("+ \(otherDevices.count - 5) more")
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
