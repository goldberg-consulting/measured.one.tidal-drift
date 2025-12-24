import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = DashboardViewModel()
    @ObservedObject private var discoveryService = NetworkDiscoveryService.shared
    
    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            mainContent
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
    
    private var sidebarContent: some View {
        List {
            Section("This Mac") {
                StatusCardView()
            }
            
            Section("Quick Actions") {
                Button {
                    viewModel.showAddDeviceSheet = true
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
                
                Button {
                    // Open Finder to show iCloud devices in sidebar
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
                        if discoveryService.isScanningSubnet {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "network")
                        }
                        Text("Scan Subnet")
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
            }
            .padding()
            
            // Subnet scan progress bar
            if discoveryService.isScanningSubnet {
                VStack(spacing: 4) {
                    ProgressView(value: discoveryService.scanProgress)
                        .progressViewStyle(.linear)
                    Text("Scanning network for devices... \(Int(discoveryService.scanProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
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

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
            .environmentObject(AppState.shared)
    }
}
