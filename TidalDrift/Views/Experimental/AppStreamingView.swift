import SwiftUI

/// Experimental view for app-specific streaming
struct AppStreamingView: View {
    @StateObject private var service = AppStreamingService.shared
    @StateObject private var networkService = StreamingNetworkService.shared
    @State private var showingInfo = false
    @State private var showingPermissionAlert = false
    @State private var selectedTab = 0  // 0 = Local, 1 = Remote
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()
            
            if !service.isExperimentalEnabled {
                experimentalDisabledView
            } else {
                enabledContent
            }
        }
        .frame(minWidth: 500, minHeight: 550)
        .alert("Screen Recording Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open System Settings") {
                openScreenRecordingSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("TidalDrift needs screen recording permission to list available apps for streaming.")
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.orange)
                    Text("App-Specific Streaming")
                        .font(.headline)
                    
                    Text("EXPERIMENTAL")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
                
                Text("Stream individual apps across your network")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                showingInfo = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingInfo) {
                infoPopover
            }
        }
        .padding()
    }
    
    private var experimentalDisabledView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "flask")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("Experimental Feature")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("App-specific streaming allows you to share just one application window instead of your entire desktop, and discover apps shared by other machines on your network.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            VStack(spacing: 12) {
                Toggle("Enable Experimental Features", isOn: Binding(
                    get: { service.isExperimentalEnabled },
                    set: { service.setExperimentalEnabled($0) }
                ))
                .toggleStyle(.switch)
                
                Text("This feature is still in development")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
    
    private var enabledContent: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                    Text("My Apps")
                }
                .tag(0)
                
                HStack(spacing: 4) {
                    Image(systemName: "network")
                    Text("Remote Apps")
                    if !networkService.allRemoteApps.isEmpty {
                        Text("(\(networkService.allRemoteApps.count))")
                            .foregroundColor(.secondary)
                    }
                }
                .tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            if selectedTab == 0 {
                localAppsContent
            } else {
                remoteAppsContent
            }
        }
    }
    
    // MARK: - Local Apps Tab
    
    private var localAppsContent: some View {
        VStack(spacing: 0) {
            // Hosting status bar
            hostingStatusBar
            
            Divider()
            
            HSplitView {
                localAppList
                    .frame(minWidth: 200)
                
                localDetailView
                    .frame(minWidth: 250)
            }
        }
    }
    
    private var hostingStatusBar: some View {
        HStack(spacing: 12) {
            // Hosting toggle
            HStack(spacing: 8) {
                Circle()
                    .fill(networkService.isHosting ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                
                Text(networkService.isHosting ? "Sharing \(networkService.hostedApps.count) apps" : "Not sharing")
                    .font(.caption)
                    .foregroundColor(networkService.isHosting ? .primary : .secondary)
            }
            
            Toggle("Share My Apps", isOn: Binding(
                get: { networkService.isHosting },
                set: { enabled in
                    if enabled {
                        networkService.startHosting(apps: service.availableApps)
                    } else {
                        networkService.stopHosting()
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            
            Spacer()
            
            Button {
                Task {
                    await service.refreshAvailableApps()
                    if networkService.isHosting {
                        networkService.updateHostedApps(service.availableApps)
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(service.isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(networkService.isHosting ? Color.green.opacity(0.1) : Color.clear)
    }
    
    private var localAppList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Running Apps")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(service.availableApps.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            Divider()
            
            if service.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading apps...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else if service.availableApps.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("No apps found")
                        .foregroundColor(.secondary)
                    Button("Grant Permission") {
                        showingPermissionAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(service.availableApps) { app in
                            AppRow(app: app, isSelected: service.selectedApp?.id == app.id)
                                .onTapGesture {
                                    service.selectApp(app)
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if service.availableApps.isEmpty {
                Task {
                    await service.refreshAvailableApps()
                }
            }
        }
    }
    
    private var localDetailView: some View {
        VStack {
            if let app = service.selectedApp {
                selectedAppDetail(app)
            } else {
                emptySelection
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var emptySelection: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Select an App")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Choose an app to share with others")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func selectedAppDetail(_ app: StreamableApp) -> some View {
        VStack(spacing: 20) {
            // App header
            VStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                }
                
                Text(app.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let bundleId = app.bundleIdentifier {
                    Text(bundleId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Sharing status
                if networkService.isHosting && networkService.hostedApps.contains(app.bundleIdentifier ?? "") {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.green)
                        Text("Being shared")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.top, 20)
            
            Divider()
                .padding(.horizontal)
            
            // Windows section
            VStack(alignment: .leading, spacing: 8) {
                Text("Windows (\(app.windows.count))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(app.windows) { window in
                    WindowRow(
                        window: window,
                        isSelected: service.selectedWindow?.id == window.id
                    )
                    .onTapGesture {
                        service.selectWindow(window)
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Actions
            VStack(spacing: 12) {
                Button {
                    service.bringAppToFront()
                } label: {
                    Label("Bring to Front", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Text("When others connect, they'll see this app")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
    
    // MARK: - Remote Apps Tab
    
    private var remoteAppsContent: some View {
        VStack(spacing: 0) {
            // Discovery controls
            discoveryStatusBar
            
            Divider()
            
            if networkService.discoveredHosts.isEmpty {
                remoteEmptyState
            } else {
                remoteAppsList
            }
        }
    }
    
    private var discoveryStatusBar: some View {
        HStack(spacing: 12) {
            // Discovery status
            HStack(spacing: 8) {
                if networkService.isDiscovering {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
                
                Text(networkService.isDiscovering ? "Searching..." : "Not searching")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button {
                if networkService.isDiscovering {
                    networkService.stopDiscovery()
                } else {
                    networkService.startDiscovery()
                }
            } label: {
                Label(
                    networkService.isDiscovering ? "Stop" : "Search Network",
                    systemImage: networkService.isDiscovering ? "stop.fill" : "magnifyingglass"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Spacer()
            
            if !networkService.discoveredHosts.isEmpty {
                Text("\(networkService.discoveredHosts.count) host\(networkService.discoveredHosts.count == 1 ? "" : "s") found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button {
                networkService.refreshDiscovery()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(!networkService.isDiscovering)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(networkService.isDiscovering ? Color.blue.opacity(0.1) : Color.clear)
        .onAppear {
            // Auto-start discovery when viewing remote tab
            if !networkService.isDiscovering {
                networkService.startDiscovery()
            }
        }
    }
    
    private var remoteEmptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            if networkService.isDiscovering {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Searching for streaming apps...")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Make sure TidalDrift is running on other machines\nwith app sharing enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "network.slash")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                
                Text("No Remote Apps Found")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Click 'Search Network' to discover apps\nbeing shared by other TidalDrift users")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    networkService.startDiscovery()
                } label: {
                    Label("Search Network", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var remoteAppsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(networkService.discoveredHosts) { host in
                    RemoteHostSection(host: host)
                }
            }
            .padding()
        }
    }
    
    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About App-Specific Streaming")
                .font(.headline)
            
            Text("""
            This experimental feature lets you stream individual apps across your network.
            
            How it works:
            1. Enable "Share My Apps" to advertise your apps
            2. Go to "Remote Apps" to discover apps from other machines
            3. Click "Connect" to view a remote app
            
            Requirements:
            • TidalDrift running on both machines
            • Screen Recording permission granted
            • Both machines on the same network
            
            Note: Connection opens Screen Sharing to the remote Mac with the selected app brought to front.
            """)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 320)
    }
    
    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Remote Host Section

struct RemoteHostSection: View {
    let host: StreamingHost
    @StateObject private var networkService = StreamingNetworkService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Host header
            HStack {
                Image(systemName: "desktopcomputer")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(host.ipAddress)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(host.apps.count) app\(host.apps.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Divider()
            
            // Apps from this host
            ForEach(host.apps) { app in
                RemoteAppRow(app: app)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct RemoteAppRow: View {
    let app: RemoteStreamableApp
    @StateObject private var networkService = StreamingNetworkService.shared
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.fill")
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.subheadline)
                
                Text("\(app.windowCount) window\(app.windowCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                networkService.connectToRemoteApp(app)
            } label: {
                Label("Connect", systemImage: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Existing Row Components

struct AppRow: View {
    let app: StreamableApp
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 24, height: 24)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text("\(app.windows.count) window\(app.windows.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }
}

struct WindowRow: View {
    let window: StreamableWindow
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow")
                .foregroundColor(isSelected ? .accentColor : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "Untitled" : window.title)
                    .font(.caption)
                    .lineLimit(1)
                
                Text("\(Int(window.bounds.width))×\(Int(window.bounds.height))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if window.isOnScreen {
                Text("visible")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}

struct AppStreamingView_Previews: PreviewProvider {
    static var previews: some View {
        AppStreamingView()
    }
}
