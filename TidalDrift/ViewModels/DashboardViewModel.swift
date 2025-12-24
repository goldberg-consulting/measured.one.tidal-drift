import SwiftUI
import Combine

class DashboardViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedDevice: DiscoveredDevice?
    @Published var showAddDeviceSheet: Bool = false
    @Published var showDeviceDetail: Bool = false
    @Published var isConnecting: Bool = false
    @Published var connectionError: String?
    @Published var viewMode: ViewMode = .grid
    @Published var sortOrder: SortOrder = .name
    
    private var cancellables = Set<AnyCancellable>()
    
    enum ViewMode: String, CaseIterable {
        case grid
        case list
        
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }
    
    enum SortOrder: String, CaseIterable {
        case name
        case lastSeen
        case status
        
        var displayName: String {
            switch self {
            case .name: return "Name"
            case .lastSeen: return "Last Seen"
            case .status: return "Status"
            }
        }
    }
    
    func filteredDevices(_ devices: [DiscoveredDevice]) -> [DiscoveredDevice] {
        var filtered = devices
        
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.ipAddress.contains(searchText)
            }
        }
        
        switch sortOrder {
        case .name:
            filtered.sort { $0.name < $1.name }
        case .lastSeen:
            filtered.sort { $0.lastSeen > $1.lastSeen }
        case .status:
            filtered.sort { $0.isOnline && !$1.isOnline }
        }
        
        return filtered
    }
    
    func selectDevice(_ device: DiscoveredDevice) {
        selectedDevice = device
        showDeviceDetail = true
    }
    
    func connectToDevice(_ device: DiscoveredDevice, service: DiscoveredDevice.ServiceType) async {
        await MainActor.run {
            isConnecting = true
            connectionError = nil
        }
        
        do {
            switch service {
            case .screenSharing:
                try await ScreenShareConnectionService.shared.connect(to: device)
            case .fileSharing:
                try await ScreenShareConnectionService.shared.connectToFileShare(device: device)
            case .afp:
                try await ScreenShareConnectionService.shared.connectToAFP(device: device)
            }
            
            let record = ConnectionRecord(
                deviceId: device.id,
                deviceName: device.name,
                deviceIP: device.ipAddress,
                connectionType: service == .screenSharing ? .screenShare : .fileShare,
                wasSuccessful: true
            )
            
            await MainActor.run {
                AppState.shared.addConnectionRecord(record)
                isConnecting = false
            }
        } catch {
            await MainActor.run {
                connectionError = error.localizedDescription
                isConnecting = false
            }
        }
    }
    
    func refreshScan() {
        NetworkDiscoveryService.shared.refreshScan()
    }
    
    func addManualDevice(name: String, ipAddress: String) {
        NetworkDiscoveryService.shared.addManualDevice(name: name, ipAddress: ipAddress)
        showAddDeviceSheet = false
    }
}
