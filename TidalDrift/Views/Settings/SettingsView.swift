import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            NetworkSettingsView()
                .tabItem {
                    Label("Network", systemImage: "network")
                }
            
            SecuritySettingsView()
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $appState.settings.launchAtLogin)
                
                Toggle("Show menu bar icon", isOn: $appState.settings.showMenuBarIcon)
                
                Toggle("Show notifications", isOn: $appState.settings.showNotifications)
            }
            
            Section {
                Picker("Appearance", selection: $appState.settings.theme) {
                    ForEach(AppSettings.AppTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }
            
            Section {
                Button("Reset Onboarding") {
                    appState.hasCompletedOnboarding = false
                }
                
                Button("Reset All Settings") {
                    SettingsService.shared.resetToDefaults()
                    appState.settings = .default
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct NetworkSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section("Discovery") {
                Picker("Scan interval", selection: $appState.settings.scanIntervalSeconds) {
                    ForEach(AppSettings.scanIntervalOptions, id: \.self) { interval in
                        Text(AppSettings.scanIntervalDisplayName(for: interval)).tag(interval)
                    }
                }
                
                Toggle("Auto-connect to trusted devices", isOn: $appState.settings.autoConnectTrustedDevices)
            }
            
            Section("Network Status") {
                HStack {
                    Text("Local IP")
                    Spacer()
                    Text(appState.localIPAddress)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Computer Name")
                    Spacer()
                    Text(appState.computerName)
                        .foregroundColor(.secondary)
                }
                
                Button("Refresh") {
                    appState.refreshLocalInfo()
                }
            }
            
            Section("Sharing Status") {
                HStack {
                    Text("Screen Sharing")
                    Spacer()
                    StatusBadge(isEnabled: appState.screenSharingEnabled)
                }
                
                HStack {
                    Text("File Sharing")
                    Spacer()
                    StatusBadge(isEnabled: appState.fileSharingEnabled)
                }
                
                Button("Open Sharing Settings") {
                    SharingConfigurationService.shared.openSharingPreferences()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct SecuritySettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var trustedDeviceCount: Int = 0
    @State private var savedCredentialsCount: Int = 0
    
    var body: some View {
        Form {
            Section("Authentication") {
                Toggle("Use Touch ID when available", isOn: $appState.settings.useBiometrics)
                
                Toggle("Log connection attempts", isOn: $appState.settings.enableConnectionLogging)
            }
            
            Section("Trusted Devices") {
                HStack {
                    Text("Trusted devices")
                    Spacer()
                    Text("\(appState.trustedDevices.count)")
                        .foregroundColor(.secondary)
                }
                
                Button("Clear All Trusted Devices") {
                    appState.trustedDevices.removeAll()
                }
                .foregroundColor(.red)
                .disabled(appState.trustedDevices.isEmpty)
            }
            
            Section("Saved Credentials") {
                HStack {
                    Text("Saved credentials")
                    Spacer()
                    Text("\(savedCredentialsCount)")
                        .foregroundColor(.secondary)
                }
                
                Button("View in Keychain Access") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
                }
            }
            
            Section("Connection History") {
                HStack {
                    Text("Logged connections")
                    Spacer()
                    Text("\(appState.connectionHistory.count)")
                        .foregroundColor(.secondary)
                }
                
                Button("Clear History") {
                    appState.connectionHistory.removeAll()
                }
                .foregroundColor(.red)
                .disabled(appState.connectionHistory.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadCounts()
        }
    }
    
    private func loadCounts() {
        trustedDeviceCount = appState.trustedDevices.count
        if let ids = try? KeychainService.shared.getAllSavedDeviceIds() {
            savedCredentialsCount = ids.count
        }
    }
}

struct StatusBadge: View {
    let isEnabled: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isEnabled ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(isEnabled ? "Enabled" : "Disabled")
                .font(.caption)
                .foregroundColor(isEnabled ? .green : .orange)
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "water.waves")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("TidalDrift")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version 1.0.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("Mac-to-Mac network sharing made simple. Discover, connect, and share with other Macs on your local network.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                Link("Documentation", destination: URL(string: "https://github.com/tidaldrift/docs")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/tidaldrift/issues")!)
            }
            .font(.subheadline)
            
            Spacer()
            
            Text("Made with love for the Mac community")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
