import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = DashboardViewModel()
    
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
                    viewModel.refreshScan()
                } label: {
                    Label("Scan Network", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isScanning)
                
                Button {
                    viewModel.showAddDeviceSheet = true
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
            }
            
            if !appState.connectionHistory.isEmpty {
                Section("Recent") {
                    ForEach(appState.connectionHistory.prefix(5)) { record in
                        RecentConnectionRow(record: record)
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
        HStack {
            TextField("Search devices...", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)
            
            Spacer()
            
            if appState.isScanning {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, 8)
            }
            
            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(DashboardViewModel.SortOrder.allCases, id: \.self) { order in
                    Text(order.displayName).tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            
            Picker("View", selection: $viewModel.viewMode) {
                ForEach(DashboardViewModel.ViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
        }
        .padding()
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

#Preview {
    DashboardView()
        .environmentObject(AppState.shared)
}
