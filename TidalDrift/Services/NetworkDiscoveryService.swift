import Foundation
import Network
import Combine

class NetworkDiscoveryService: ObservableObject {
    static let shared = NetworkDiscoveryService()
    
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning: Bool = false
    @Published var lastScanDate: Date?
    
    private var browsers: [NWBrowser] = []
    private var deviceCache: [String: DiscoveredDevice] = [:]
    private var scanTimer: Timer?
    private let queue = DispatchQueue(label: "com.tidaldrift.discovery", qos: .userInitiated)
    
    private let serviceTypes: [String] = [
        "_rfb._tcp",
        "_smb._tcp",
        "_afpovertcp._tcp"
    ]
    
    private init() {}
    
    func startBrowsing() {
        guard !isScanning else { return }
        
        DispatchQueue.main.async {
            self.isScanning = true
        }
        
        for serviceType in serviceTypes {
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: .tcp)
            
            browser.stateUpdateHandler = { [weak self] state in
                self?.handleBrowserState(state, for: serviceType)
            }
            
            browser.browseResultsChangedHandler = { [weak self] results, changes in
                self?.handleBrowseResults(results, changes: changes, serviceType: serviceType)
            }
            
            browser.start(queue: queue)
            browsers.append(browser)
        }
        
        lastScanDate = Date()
    }
    
    func stopBrowsing() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        
        DispatchQueue.main.async {
            self.isScanning = false
        }
    }
    
    func refreshScan() {
        stopBrowsing()
        deviceCache.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startBrowsing()
        }
    }
    
    func startPeriodicScanning(interval: TimeInterval) {
        stopPeriodicScanning()
        
        startBrowsing()
        
        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshScan()
        }
    }
    
    func stopPeriodicScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        stopBrowsing()
    }
    
    private func handleBrowserState(_ state: NWBrowser.State, for serviceType: String) {
        switch state {
        case .ready:
            print("Browser ready for \(serviceType)")
        case .failed(let error):
            print("Browser failed for \(serviceType): \(error)")
        case .cancelled:
            print("Browser cancelled for \(serviceType)")
        default:
            break
        }
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>, serviceType: String) {
        for result in results {
            switch result.endpoint {
            case .service(let name, let type, let domain, _):
                resolveService(name: name, type: type, domain: domain, serviceType: serviceType)
            default:
                break
            }
        }
        
        for change in changes {
            switch change {
            case .removed(let result):
                handleDeviceRemoved(result)
            default:
                break
            }
        }
    }
    
    private func resolveService(name: String, type: String, domain: String, serviceType: String) {
        let params = NWParameters.tcp
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let connection = NWConnection(to: endpoint, using: params)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint {
                    self?.extractIPAddress(from: innerEndpoint, name: name, serviceType: serviceType)
                }
                connection.cancel()
            case .failed:
                connection.cancel()
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            connection.cancel()
        }
    }
    
    private func extractIPAddress(from endpoint: NWEndpoint, name: String, serviceType: String) {
        guard case .hostPort(let host, let port) = endpoint else { return }
        
        var ipAddress = ""
        switch host {
        case .ipv4(let addr):
            ipAddress = "\(addr)"
        case .ipv6(let addr):
            ipAddress = "\(addr)"
        case .name(let hostname, _):
            ipAddress = hostname
        @unknown default:
            break
        }
        
        let portNumber = Int(port.rawValue)
        let service = mapServiceType(serviceType)
        
        DispatchQueue.main.async { [weak self] in
            self?.addOrUpdateDevice(name: name, ipAddress: ipAddress, port: portNumber, service: service)
        }
    }
    
    private func mapServiceType(_ type: String) -> DiscoveredDevice.ServiceType? {
        switch type {
        case "_rfb._tcp", "_rfb._tcp.":
            return .screenSharing
        case "_smb._tcp", "_smb._tcp.":
            return .fileSharing
        case "_afpovertcp._tcp", "_afpovertcp._tcp.":
            return .afp
        default:
            return nil
        }
    }
    
    private func addOrUpdateDevice(name: String, ipAddress: String, port: Int, service: DiscoveredDevice.ServiceType?) {
        let cacheKey = "\(name)-\(ipAddress)"
        
        if var existingDevice = deviceCache[cacheKey] {
            existingDevice.lastSeen = Date()
            if let service = service {
                existingDevice.services.insert(service)
            }
            deviceCache[cacheKey] = existingDevice
        } else {
            var services: Set<DiscoveredDevice.ServiceType> = []
            if let service = service {
                services.insert(service)
            }
            
            let newDevice = DiscoveredDevice(
                name: name,
                hostname: "\(name).local",
                ipAddress: ipAddress,
                services: services,
                lastSeen: Date(),
                port: port
            )
            deviceCache[cacheKey] = newDevice
        }
        
        updatePublishedDevices()
    }
    
    private func handleDeviceRemoved(_ result: NWBrowser.Result) {
        switch result.endpoint {
        case .service(let name, _, _, _):
            deviceCache = deviceCache.filter { !$0.key.hasPrefix(name) }
            updatePublishedDevices()
        default:
            break
        }
    }
    
    private func updatePublishedDevices() {
        let devices = Array(deviceCache.values).sorted { $0.name < $1.name }
        DispatchQueue.main.async {
            self.discoveredDevices = devices
        }
    }
    
    func addManualDevice(name: String, ipAddress: String, port: Int = 5900) {
        let device = DiscoveredDevice(
            name: name,
            hostname: ipAddress,
            ipAddress: ipAddress,
            services: [.screenSharing],
            lastSeen: Date(),
            port: port
        )
        
        let cacheKey = "\(name)-\(ipAddress)"
        deviceCache[cacheKey] = device
        updatePublishedDevices()
    }
}
