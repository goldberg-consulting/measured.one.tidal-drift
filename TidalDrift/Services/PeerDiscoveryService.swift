import Foundation
import Network
import Combine

/// Service for discovering other TidalDrift instances on the network
/// and sharing system information between peers
class PeerDiscoveryService: ObservableObject {
    static let shared = PeerDiscoveryService()
    
    private let serviceType = "_tidaldrift._tcp"
    private let serviceDomain = "local."
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.tidaldrift.peer", qos: .userInitiated)
    
    @Published var discoveredPeers: [String: PeerInfo] = [:] // keyed by IP
    @Published var isAdvertising: Bool = false
    
    private init() {}
    
    // MARK: - System Info Collection
    
    struct PeerInfo: Codable, Identifiable {
        var id: String { ipAddress }
        let ipAddress: String
        let computerName: String
        let modelName: String
        let modelIdentifier: String
        let processorInfo: String
        let memoryGB: Int
        let macOSVersion: String
        let macOSBuild: String
        let serialNumber: String?
        let userName: String
        let uptimeHours: Int
        let tidalDriftVersion: String
        let lastSeen: Date
        
        var displayModel: String {
            if !modelName.isEmpty {
                return modelName
            }
            return modelIdentifier
        }
    }
    
    /// Get current system information to advertise
    func getLocalSystemInfo() -> [String: String] {
        var info: [String: String] = [:]
        
        // Computer name
        info["computerName"] = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        
        // Model info
        info["modelName"] = getModelName()
        info["modelIdentifier"] = getModelIdentifier()
        
        // Processor
        info["processor"] = getProcessorInfo()
        
        // Memory
        info["memoryGB"] = "\(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))"
        
        // macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        info["macOSVersion"] = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        info["macOSBuild"] = getBuildNumber()
        
        // Serial (may be restricted)
        info["serial"] = getSerialNumber() ?? ""
        
        // User
        info["userName"] = NSFullUserName()
        
        // Uptime
        let uptime = ProcessInfo.processInfo.systemUptime
        info["uptimeHours"] = "\(Int(uptime / 3600))"
        
        // App version
        info["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        
        return info
    }
    
    private func getModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    private func getModelName() -> String {
        let identifier = getModelIdentifier()
        
        // Map common identifiers to friendly names
        let modelMap: [String: String] = [
            "MacBookPro": "MacBook Pro",
            "MacBookAir": "MacBook Air",
            "Macmini": "Mac mini",
            "MacPro": "Mac Pro",
            "iMac": "iMac",
            "MacStudio": "Mac Studio"
        ]
        
        for (key, name) in modelMap {
            if identifier.contains(key) {
                return name
            }
        }
        
        return identifier
    }
    
    private func getProcessorInfo() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var processor = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &processor, &size, nil, 0)
        let brand = String(cString: processor)
        
        if brand.isEmpty {
            // Apple Silicon
            var cpuSize = 0
            sysctlbyname("hw.ncpu", nil, &cpuSize, nil, 0)
            var ncpu: Int32 = 0
            sysctlbyname("hw.ncpu", &ncpu, &cpuSize, nil, 0)
            
            // Try to get chip name
            let identifier = getModelIdentifier()
            if identifier.contains("Mac14") || identifier.contains("Mac15") {
                return "Apple Silicon (\(ncpu) cores)"
            }
            return "Apple M-series (\(ncpu) cores)"
        }
        
        return brand
    }
    
    private func getBuildNumber() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var build = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &build, &size, nil, 0)
        return String(cString: build)
    }
    
    private func getSerialNumber() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }
        
        if let serialNumber = IORegistryEntryCreateCFProperty(
            platformExpert,
            "IOPlatformSerialNumber" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            return serialNumber
        }
        
        return nil
    }
    
    // MARK: - Service Advertisement
    
    func startAdvertising() {
        guard listener == nil else { return }
        
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            
            listener = try NWListener(using: params)
            listener?.service = NWListener.Service(
                name: Host.current().localizedName ?? "TidalDrift",
                type: serviceType,
                domain: serviceDomain,
                txtRecord: createTXTRecord()
            )
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isAdvertising = true
                    case .failed:
                        self?.isAdvertising = false
                    case .cancelled:
                        self?.isAdvertising = false
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { connection in
                // Accept connections from other TidalDrift instances
                connection.start(queue: self.queue)
            }
            
            listener?.start(queue: queue)
            
        } catch {
            // Failed to create listener - peer discovery disabled
        }
    }
    
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isAdvertising = false
        }
    }
    
    private func createTXTRecord() -> NWTXTRecord {
        var txtRecord = NWTXTRecord()
        let info = getLocalSystemInfo()
        
        for (key, value) in info {
            txtRecord[key] = value
        }
        
        return txtRecord
    }
    
    // MARK: - Peer Discovery
    
    func startBrowsing() {
        guard browser == nil else { return }
        
        let params = NWParameters()
        params.includePeerToPeer = true
        
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: serviceDomain), using: params)
        
        browser?.stateUpdateHandler = { _ in
            // Browser state changes handled silently
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handlePeerResults(results)
        }
        
        browser?.start(queue: queue)
    }
    
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }
    
    private func handlePeerResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            switch result.endpoint {
            case .service(let name, _, _, _):
                resolvePeer(result: result, name: name)
            default:
                break
            }
        }
    }
    
    private func resolvePeer(result: NWBrowser.Result, name: String) {
        // Get TXT record from result metadata
        if case let .bonjour(txtRecord) = result.metadata {
            let info = parseTXTRecord(txtRecord, name: name)
            
            // Resolve IP address
            if case .service(let serviceName, let type, let domain, _) = result.endpoint {
                let endpoint = NWEndpoint.service(name: serviceName, type: type, domain: domain, interface: nil)
                let connection = NWConnection(to: endpoint, using: .tcp)
                
                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        if let path = connection.currentPath,
                           case .hostPort(let host, _) = path.remoteEndpoint {
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
                            
                            // Clean IP
                            if let percentIndex = ipAddress.firstIndex(of: "%") {
                                ipAddress = String(ipAddress[..<percentIndex])
                            }
                            
                            if !ipAddress.isEmpty {
                                var peerInfo = info
                                peerInfo = PeerInfo(
                                    ipAddress: ipAddress,
                                    computerName: info.computerName,
                                    modelName: info.modelName,
                                    modelIdentifier: info.modelIdentifier,
                                    processorInfo: info.processorInfo,
                                    memoryGB: info.memoryGB,
                                    macOSVersion: info.macOSVersion,
                                    macOSBuild: info.macOSBuild,
                                    serialNumber: info.serialNumber,
                                    userName: info.userName,
                                    uptimeHours: info.uptimeHours,
                                    tidalDriftVersion: info.tidalDriftVersion,
                                    lastSeen: Date()
                                )
                                
                                DispatchQueue.main.async {
                                    self?.discoveredPeers[ipAddress] = peerInfo
                                    // Also notify NetworkDiscoveryService
                                    self?.notifyNetworkDiscovery(peerInfo: peerInfo)
                                }
                            }
                        }
                        connection.cancel()
                    case .failed:
                        connection.cancel()
                    default:
                        break
                    }
                }
                
                connection.start(queue: queue)
                
                // Timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    connection.cancel()
                }
            }
        }
    }
    
    private func parseTXTRecord(_ txtRecord: NWTXTRecord?, name: String) -> PeerInfo {
        guard let txtRecord = txtRecord else {
            return PeerInfo(
                ipAddress: "",
                computerName: name,
                modelName: "",
                modelIdentifier: "",
                processorInfo: "",
                memoryGB: 0,
                macOSVersion: "",
                macOSBuild: "",
                serialNumber: nil,
                userName: "",
                uptimeHours: 0,
                tidalDriftVersion: "",
                lastSeen: Date()
            )
        }
        
        return PeerInfo(
            ipAddress: "",
            computerName: txtRecord["computerName"] ?? name,
            modelName: txtRecord["modelName"] ?? "",
            modelIdentifier: txtRecord["modelIdentifier"] ?? "",
            processorInfo: txtRecord["processor"] ?? "",
            memoryGB: Int(txtRecord["memoryGB"] ?? "0") ?? 0,
            macOSVersion: txtRecord["macOSVersion"] ?? "",
            macOSBuild: txtRecord["macOSBuild"] ?? "",
            serialNumber: txtRecord["serial"]?.isEmpty == false ? txtRecord["serial"] : nil,
            userName: txtRecord["userName"] ?? "",
            uptimeHours: Int(txtRecord["uptimeHours"] ?? "0") ?? 0,
            tidalDriftVersion: txtRecord["appVersion"] ?? "",
            lastSeen: Date()
        )
    }
    
    private func notifyNetworkDiscovery(peerInfo: PeerInfo) {
        // Mark the device as a TidalDrift peer in NetworkDiscoveryService
        NetworkDiscoveryService.shared.markAsTidalDriftPeer(
            ipAddress: peerInfo.ipAddress,
            peerInfo: peerInfo
        )
    }
    
    // MARK: - Lifecycle
    
    func start() {
        startAdvertising()
        startBrowsing()
    }
    
    func stop() {
        stopAdvertising()
        stopBrowsing()
    }
}

