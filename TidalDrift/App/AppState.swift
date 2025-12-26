import SwiftUI
import Combine

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var trustedDevices: [UUID] = []
    @Published var connectionHistory: [ConnectionRecord] = []
    @Published var settings: AppSettings
    
    @Published var screenSharingEnabled: Bool = false
    @Published var fileSharingEnabled: Bool = false
    @Published var remoteLoginEnabled: Bool = false
    @Published var localIPAddress: String = "Unknown"
    @Published var computerName: String = Host.current().localizedName ?? "Unknown"
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.settings = SettingsService.shared.loadSettings()
        
        setupBindings()
        refreshLocalInfo()
    }
    
    private func setupBindings() {
        NetworkDiscoveryService.shared.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$discoveredDevices)
        
        $settings
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] settings in
                SettingsService.shared.saveSettings(settings)
            }
            .store(in: &cancellables)
    }
    
    func refreshLocalInfo() {
        localIPAddress = NetworkUtils.getLocalIPAddress() ?? "Unknown"
        computerName = Host.current().localizedName ?? "Unknown"
        
        Task {
            await checkSharingStatus()
        }
    }
    
    @MainActor
    func checkSharingStatus() async {
        screenSharingEnabled = await SharingConfigurationService.shared.isScreenSharingEnabled()
        fileSharingEnabled = await SharingConfigurationService.shared.isFileSharingEnabled()
        remoteLoginEnabled = await SharingConfigurationService.shared.isRemoteLoginEnabled()
    }
    
    func toggleDeviceTrust(_ deviceId: UUID) {
        if trustedDevices.contains(deviceId) {
            trustedDevices.removeAll { $0 == deviceId }
        } else {
            trustedDevices.append(deviceId)
        }
        saveTrustedDevices()
    }
    
    func isDeviceTrusted(_ deviceId: UUID) -> Bool {
        trustedDevices.contains(deviceId)
    }
    
    private func saveTrustedDevices() {
        let uuidStrings = trustedDevices.map { $0.uuidString }
        UserDefaults.standard.set(uuidStrings, forKey: "trustedDevices")
    }
    
    func loadTrustedDevices() {
        if let uuidStrings = UserDefaults.standard.stringArray(forKey: "trustedDevices") {
            trustedDevices = uuidStrings.compactMap { UUID(uuidString: $0) }
        }
    }
    
    func addConnectionRecord(_ record: ConnectionRecord) {
        connectionHistory.insert(record, at: 0)
        if connectionHistory.count > 100 {
            connectionHistory = Array(connectionHistory.prefix(100))
        }
        saveConnectionHistory()
    }
    
    private func saveConnectionHistory() {
        if let encoded = try? JSONEncoder().encode(connectionHistory) {
            UserDefaults.standard.set(encoded, forKey: "connectionHistory")
        }
    }
    
    func loadConnectionHistory() {
        if let data = UserDefaults.standard.data(forKey: "connectionHistory"),
           let history = try? JSONDecoder().decode([ConnectionRecord].self, from: data) {
            connectionHistory = history
        }
    }
    
    func clearConnectionHistory() {
        connectionHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "connectionHistory")
    }
}
