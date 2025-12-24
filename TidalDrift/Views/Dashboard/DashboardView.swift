import SwiftUI

enum DashboardSection: String, CaseIterable {
    case devices = "Devices"
    case appStreaming = "App Streaming"
    case clipboardSync = "Clipboard Sync"
    case troubleshooting = "Troubleshooting"
}

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = DashboardViewModel()
    @ObservedObject private var discoveryService = NetworkDiscoveryService.shared
    @State private var selectedSection: DashboardSection = .devices
    
    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $viewModel.showAddDeviceSheet) {
            AddDeviceSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.selectedDevice) { device in
            DeviceDetailSheet(device: device)
        }
        .onAppear {
            NetworkDiscoveryService.shared.startBrowsing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanNetwork)) { _ in
            viewModel.refreshScan()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addDeviceManually)) { _ in
            viewModel.showAddDeviceSheet = true
        }
    }
    
    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .devices:
            mainContent
        case .appStreaming:
            AppStreamingTabView()
        case .clipboardSync:
            ClipboardSyncTabView()
        case .troubleshooting:
            TroubleshootingView()
        }
    }
    
    private var sidebarContent: some View {
        List(selection: $selectedSection) {
            Section("This Mac") {
                StatusCardView()
            }
            
            Section("Navigation") {
                Label("Devices", systemImage: "desktopcomputer")
                    .tag(DashboardSection.devices)
                
                Label("App Streaming", systemImage: "app.connected.to.app.below.fill")
                    .tag(DashboardSection.appStreaming)
                    .badge(Text("β").foregroundColor(.orange))
                
                HStack {
                    Label("Clipboard Sync", systemImage: "doc.on.clipboard")
                    Spacer()
                    if ClipboardSyncService.shared.isEnabled {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                }
                .tag(DashboardSection.clipboardSync)
                
                Label("Troubleshooting", systemImage: "wrench.and.screwdriver")
                    .tag(DashboardSection.troubleshooting)
            }
            
            Section("Quick Actions") {
                Button {
                    viewModel.showAddDeviceSheet = true
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
                
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
                } label: {
                    Label("iCloud Devices", systemImage: "icloud")
                }
                .help("Open Finder to see Macs on your iCloud account")
            }
            
            if !appState.connectionHistory.isEmpty {
                Section("Recent") {
                    ForEach(appState.connectionHistory.prefix(5)) { record in
                        RecentConnectionRow(record: record)
                    }
                    
                    Button(role: .destructive) {
                        appState.clearConnectionHistory()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 250)
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            toolbar
            
            if appState.discoveredDevices.isEmpty {
                emptyState
            } else {
                deviceContent
            }
        }
    }
    
    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search devices...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 250)
                
                Spacer()
                
                // Scan Subnet button - prominent
                Button {
                    Task {
                        await viewModel.scanSubnet(baseIP: NetworkUtils.getLocalIPAddress() ?? "192.168.1.1")
                    }
                } label: {
                    HStack(spacing: 6) {
                        ScanButtonIcon(isScanning: discoveryService.isScanningSubnet)
                            .frame(width: 18, height: 18)
                        
                        Text(discoveryService.isScanningSubnet ? "Scanning..." : "Scan Subnet")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(discoveryService.isScanningSubnet)
                
                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 8)
                
                Picker("Sort", selection: $viewModel.sortOrder) {
                    ForEach(DashboardViewModel.SortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 130)
                
                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 8)
                
                Picker("View", selection: $viewModel.viewMode) {
                    ForEach(DashboardViewModel.ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .labelsHidden()
                
                // Clear stale devices button (only show if there are stale devices)
                let staleCount = appState.discoveredDevices.filter { $0.isStale }.count
                if staleCount > 0 {
                    Button {
                        discoveryService.removeStaleDevices()
                    } label: {
                        Label("Clear \(staleCount) Old", systemImage: "clock.badge.xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Remove devices not seen in 24+ hours")
                }
            }
            .padding()
            
            // Fixed height progress area - always reserves space
            HStack(spacing: 8) {
                if discoveryService.isScanningSubnet {
                    ProgressView(value: discoveryService.scanProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 200)
                    
                    Text("\(Int(discoveryService.scanProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .frame(width: 35, alignment: .trailing)
                }
                
                Spacer()
            }
            .frame(height: 20)
            .padding(.horizontal)
            .opacity(discoveryService.isScanningSubnet ? 1 : 0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "network.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Devices Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Make sure other Macs have Screen Sharing or File Sharing enabled")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button("Scan Network") {
                    viewModel.refreshScan()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Add Manually") {
                    viewModel.showAddDeviceSheet = true
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var deviceContent: some View {
        let devices = viewModel.filteredDevices(appState.discoveredDevices)
        
        ScrollView {
            if viewModel.viewMode == .grid {
                DeviceGridView(devices: devices, onSelect: { device in
                    viewModel.selectDevice(device)
                })
            } else {
                DeviceListView(devices: devices, onSelect: { device in
                    viewModel.selectDevice(device)
                })
            }
        }
        .padding()
    }
}

struct RecentConnectionRow: View {
    let record: ConnectionRecord
    
    var body: some View {
        HStack {
            Image(systemName: record.connectionType.icon)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading) {
                Text(record.deviceName)
                    .font(.subheadline)
                Text(record.relativeTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(record.wasSuccessful ? Color.green : Color.red)
                .frame(width: 8, height: 8)
        }
    }
}

// Animated scan button icon - pulses and rotates when scanning
struct ScanButtonIcon: View {
    let isScanning: Bool
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0
    @State private var ringScale: CGFloat = 0.5
    
    var body: some View {
        ZStack {
            // Pulsing rings when scanning
            if isScanning {
                // Outer expanding ring
                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                    .scaleEffect(ringScale)
                    .opacity(2 - Double(ringScale))
                
                // Inner ring
                Circle()
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    .scaleEffect(pulse)
            }
            
            // Main icon - radar/wifi style
            Image(systemName: isScanning ? "dot.radiowaves.left.and.right" : "network")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(isScanning ? rotation : 0))
                .scaleEffect(isScanning ? pulse : 1.0)
        }
        .onChange(of: isScanning) { scanning in
            if scanning {
                startAnimations()
            } else {
                stopAnimations()
            }
        }
        .onAppear {
            if isScanning {
                startAnimations()
            }
        }
    }
    
    private func startAnimations() {
        // Continuous rotation
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            pulse = 1.15
        }
        
        // Ring expansion
        withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
            ringScale = 1.8
        }
    }
    
    private func stopAnimations() {
        rotation = 0
        pulse = 1.0
        ringScale = 0.5
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
            .environmentObject(AppState.shared)
    }
}
