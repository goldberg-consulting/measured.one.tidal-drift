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
            
            PermissionDiagnosticView()
                .tabItem {
                    Label("Permissions", systemImage: "hand.raised")
                }
            
            SecuritySettingsView()
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
            
            MaintenanceSettingsView()
                .tabItem {
                    Label("Maintenance", systemImage: "wrench.and.screwdriver")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 520)
    }
}

struct MaintenanceSettingsView: View {
    @State private var showCleanup = false
    @State private var duplicateCount = 0
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.orange)
                        Text("Installation Cleanup")
                            .font(.headline)
                    }
                    
                    Text("Find and remove duplicate TidalDrift installations to free up space and avoid confusion.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        if duplicateCount > 0 {
                            Text("\(duplicateCount) duplicate(s) found")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        Spacer()
                        
                        Button("Scan & Cleanup...") {
                            showCleanup = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.blue)
                        Text("Reset App")
                            .font(.headline)
                    }
                    
                    Text("Reset TidalDrift to its initial state. This will clear all settings and restart the onboarding process.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Spacer()
                        
                        Button("Reset All Settings") {
                            resetApp()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCleanup) {
            CleanupDuplicatesView()
        }
        .onAppear {
            checkForDuplicates()
        }
    }
    
    private func checkForDuplicates() {
        DispatchQueue.global(qos: .utility).async {
            let count = InstallationCleanupService.shared.findAllInstallations().count
            DispatchQueue.main.async {
                duplicateCount = count
            }
        }
    }
    
    private func resetApp() {
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        UserDefaults.standard.synchronize()
        
        // Restart onboarding
        AppState.shared.hasCompletedOnboarding = false
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var clipboardService = ClipboardSyncService.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $appState.settings.launchAtLogin)
                
                Toggle("Show menu bar icon", isOn: $appState.settings.showMenuBarIcon)
                
                Toggle("Show notifications", isOn: $appState.settings.showNotifications)
            }
            
            Section("Clipboard") {
                Toggle("Sync clipboard between Macs", isOn: $clipboardService.isEnabled)
                
                Text("When enabled, anything you copy will be available on other Macs running TidalDrift on your network.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Experimental") {
                Toggle(isOn: Binding(
                    get: { AppStreamingService.shared.isExperimentalEnabled },
                    set: { AppStreamingService.shared.setExperimentalEnabled($0) }
                )) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("App Streaming")
                            Text("Stream individual windows instead of full desktop")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section {
                Picker("Appearance", selection: $appState.settings.theme) {
                    ForEach(AppSettings.AppTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }
            
            Section {
                Button {
                    appState.hasCompletedOnboarding = false
                } label: {
                    Label("Run Setup Wizard Again", systemImage: "arrow.counterclockwise")
                }
                
                Button(role: .destructive) {
                    SettingsService.shared.resetToDefaults()
                    appState.settings = .default
                } label: {
                    Label("Reset All Settings", systemImage: "trash")
                }
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
            
            Section {
                Toggle("Enable Wake-on-LAN", isOn: $appState.settings.wakeOnLANEnabled)
                
                if appState.settings.wakeOnLANEnabled {
                    Toggle("Auto-wake before connecting", isOn: $appState.settings.autoWakeBeforeConnect)
                        .help("Automatically send a wake signal before connecting to an offline device")
                    
                    Picker("WOL Port", selection: $appState.settings.wakeOnLANPort) {
                        ForEach(AppSettings.wolPortOptions, id: \.self) { port in
                            Text(AppSettings.wolPortDisplayName(for: port)).tag(port)
                        }
                    }
                    
                    Picker("Retry attempts", selection: $appState.settings.wakeOnLANRetries) {
                        ForEach(AppSettings.wolRetryOptions, id: \.self) { count in
                            Text("\(count) \(count == 1 ? "attempt" : "attempts")").tag(count)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Wake-on-LAN")
                    Image(systemName: "poweron")
                        .foregroundColor(.green)
                }
            } footer: {
                Text("Wake sleeping Macs on your network. Requires the target Mac to have Wake for network access enabled in Energy Saver settings.")
                    .font(.caption)
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
            TidalDriftLogo(size: .medium)
            
                    Text("Version 1.1.2")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("VPN & VNET Screen Sharing Made Simple")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Built for internal corporate networks where screen sharing typically stinks. Discover, connect, and share with other Macs instantly.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            // Goldberg Consulting branding
            VStack(spacing: 8) {
                Divider()
                    .padding(.horizontal, 40)
                
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "building.2")
                            .font(.caption)
                        Text("Developed by")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    Text("Goldberg Consulting, LLC")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppState.shared)
    }
}
