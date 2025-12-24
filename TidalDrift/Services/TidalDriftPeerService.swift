import Foundation
import Network
import IOKit
import os.log
import Combine

/// Service to advertise this TidalDrift instance and discover peers
/// Uses Network.framework for modern, reliable Bonjour discovery
class TidalDriftPeerService: NSObject, ObservableObject {
    static let shared = TidalDriftPeerService()
    
    private static let logger = Logger(subsystem: "com.tidaldrift", category: "PeerService")
    
    static func log(_ message: String) {
        logger.info("\(message)")
        print("🌊 TidalDrift PEER: \(message)")
        
        // Also write to a file for debugging
        let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("tidaldrift-peer.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath.path) {
                if let handle = try? FileHandle(forWritingTo: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logPath)
            }
        }
    }
    
    @Published var discoveredPeers: [String: PeerInfo] = [:] // keyed by IP
    @Published var isAdvertising = false
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.tidaldrift.peer.network", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    
    private let serviceType = "_tidaldrift._tcp"
    private let deviceName = Host.current().localizedName ?? "TidalDrift"
    
    private let localInfo: PeerInfo
    
    struct PeerInfo: Codable {
        let hostname: String
        let ipAddress: String
        let modelName: String
        let modelIdentifier: String
        let processorInfo: String
        let memoryGB: Int
        let macOSVersion: String
        let userName: String
        let uptimeHours: Int
        let tidalDriftVersion: String
        let screenSharingEnabled: Bool
        let fileSharingEnabled: Bool
    }
    
    private override init() {
        // Gather local system info
        let hostname = Host.current().localizedName ?? "Unknown"
        let ipAddress = NetworkUtils.getLocalIPAddress() ?? "Unknown"
        
        localInfo = PeerInfo(
            hostname: hostname,
            ipAddress: ipAddress,
            modelName: Self.getModelName(),
            modelIdentifier: Self.getModelIdentifier(),
            processorInfo: Self.getProcessorInfo(),
            memoryGB: Self.getMemoryGB(),
            macOSVersion: Self.getMacOSVersion(),
            userName: NSUserName(),
            uptimeHours: Self.getUptimeHours(),
            tidalDriftVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            screenSharingEnabled: true,
            fileSharingEnabled: true
        )
        
        super.init()
        Self.log("Service initialized with Network.framework")
        Self.log("Local hostname: \(hostname)")
        Self.log("Local IP: \(ipAddress)")
        Self.log("Service Type: \(serviceType)")
        
        setupSettingsBinding()
    }
    
    private func setupSettingsBinding() {
        AppState.shared.$settings
            .map { $0.peerDiscoveryEnabled }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                Self.log("Peer discovery setting changed: \(enabled)")
                if enabled {
                    self?.startAdvertising()
                    self?.startDiscovery()
                } else {
                    self?.stopAdvertising()
                    self?.stopDiscovery()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Advertising (Network.framework)
    
    func startAdvertising() {
        guard listener == nil else {
            Self.log("Already advertising, skipping")
            return
        }
        
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            
            listener = try NWListener(using: params)
            
            // Set up Bonjour service
            // CRITICAL: Ensure serviceType does NOT have a trailing dot here
            listener?.service = NWListener.Service(
                name: deviceName,
                type: serviceType,
                domain: nil, // Use default domain (local.)
                txtRecord: createTXTRecord()
            )
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let portValue = self?.listener?.port?.rawValue.description ?? "unknown"
                    Self.log("✅ Peer listener ready on port \(portValue)")
                    DispatchQueue.main.async {
                        self?.isAdvertising = true
                    }
                case .failed(let error):
                    Self.log("❌ Peer listener failed: \(error)")
                    // Error -65555 is kDNSServiceErr_NotAuth - check Info.plist and entitlements
                    if error.debugDescription.contains("-65555") {
                        Self.log("CRITICAL: NoAuth error (-65555). Check Info.plist NSBonjourServices and Entitlements.")
                    }
                    self?.stopAdvertising()
                case .cancelled:
                    Self.log("Peer listener cancelled")
                    DispatchQueue.main.async {
                        self?.isAdvertising = false
                    }
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { connection in
                // We don't need to handle incoming connections for discovery, 
                // but we must start them or cancel them to avoid leaks
                connection.start(queue: .main)
                connection.cancel()
            }
            
            listener?.start(queue: queue)
            Self.log("Advertising started for \(serviceType)")
            
        } catch {
            Self.log("❌ Failed to start listener: \(error)")
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
        var txt = NWTXTRecord()
        txt["model"] = localInfo.modelName
        txt["modelId"] = localInfo.modelIdentifier
        txt["cpu"] = localInfo.processorInfo
        txt["mem"] = "\(localInfo.memoryGB)"
        txt["os"] = localInfo.macOSVersion
        txt["user"] = localInfo.userName
        txt["uptime"] = "\(localInfo.uptimeHours)"
        txt["version"] = localInfo.tidalDriftVersion
        txt["screen"] = localInfo.screenSharingEnabled ? "1" : "0"
        txt["file"] = localInfo.fileSharingEnabled ? "1" : "0"
        return txt
    }
    
    // MARK: - Discovery (Network.framework)
    
    func startDiscovery() {
        guard browser == nil else {
            Self.log("Already browsing, skipping")
            return
        }
        
        Self.log("Starting discovery for \(serviceType)")
        
        let params = NWParameters()
        params.includePeerToPeer = true
        
        // Use .bonjour with domain nil for standard local network discovery
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
        
        browser?.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                Self.log("❌ Browser failed: \(error)")
            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.processBrowseResults(results)
        }
        
        browser?.start(queue: queue)
        Self.log("NWBrowser search started")
    }
    
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }
    
    private func processBrowseResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            if case .service(let name, let type, let domain, _) = result.endpoint {
                // Skip ourselves
                if name == deviceName { continue }
                
                Self.log("Discovered service: '\(name)'")
                
                // Extract TXT record if available
                if case .bonjour(let txtRecord) = result.metadata {
                    self.resolveAndAddPeer(name: name, type: type, domain: domain, txtRecord: txtRecord)
                } else {
                    // Try to resolve anyway
                    self.resolveAndAddPeer(name: name, type: type, domain: domain, txtRecord: nil)
                }
            }
        }
    }
    
    private func resolveAndAddPeer(name: String, type: String, domain: String, txtRecord: NWTXTRecord?) {
        // Create a temporary connection to resolve the IP address
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                if let path = connection.currentPath,
                   case .hostPort(let host, _) = path.remoteEndpoint {
                    
                    var ipAddress = ""
                    switch host {
                    case .ipv4(let addr): ipAddress = "\(addr)"
                    case .ipv6(let addr): ipAddress = "\(addr)"
                    case .name(let hostname, _): ipAddress = hostname
                    @unknown default: break
                    }
                    
                    // Clean IP
                    if let percentIndex = ipAddress.firstIndex(of: "%") {
                        ipAddress = String(ipAddress[..<percentIndex])
                    }
                    
                    if !ipAddress.isEmpty {
                        self?.addPeer(name: name, ip: ipAddress, txt: txtRecord)
                    }
                }
                connection.cancel()
            } else if case .failed = state {
                connection.cancel()
            }
        }
        
        connection.start(queue: queue)
        
        // Timeout after 5 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            connection.cancel()
        }
    }
    
    private func addPeer(name: String, ip: String, txt: NWTXTRecord?) {
        let peer = PeerInfo(
            hostname: name,
            ipAddress: ip,
            modelName: txt?["model"] ?? "Unknown",
            modelIdentifier: txt?["modelId"] ?? "Unknown",
            processorInfo: txt?["cpu"] ?? "Unknown",
            memoryGB: Int(txt?["mem"] ?? "0") ?? 0,
            macOSVersion: txt?["os"] ?? "Unknown",
            userName: txt?["user"] ?? "Unknown",
            uptimeHours: Int(txt?["uptime"] ?? "0") ?? 0,
            tidalDriftVersion: txt?["version"] ?? "1.0",
            screenSharingEnabled: txt?["screen"] == "1",
            fileSharingEnabled: txt?["file"] == "1"
        )
        
        DispatchQueue.main.async {
            self.discoveredPeers[ip] = peer
            self.notifyNetworkDiscovery(peer: peer)
            Self.log("✅ Updated peer '\(name)' at \(ip)")
        }
    }
    
    private func notifyNetworkDiscovery(peer: PeerInfo) {
        // Map back to the unified NetworkDiscoveryService
        NetworkDiscoveryService.shared.markAsTidalDriftPeer(
            hostname: peer.hostname,
            peerInfo: peer
        )
    }
    
    // MARK: - System Info Helpers
    
    private static func getModelName() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)
        
        if modelString.contains("MacBookPro") { return "MacBook Pro" }
        if modelString.contains("MacBookAir") { return "MacBook Air" }
        if modelString.contains("iMac") { return "iMac" }
        if modelString.contains("Macmini") { return "Mac mini" }
        if modelString.contains("MacPro") { return "Mac Pro" }
        if modelString.contains("MacStudio") { return "Mac Studio" }
        if modelString.contains("Mac14") || modelString.contains("Mac15") { return "MacBook Pro" }
        return modelString
    }
    
    private static func getModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    private static func getProcessorInfo() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var cpu = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &cpu, &size, nil, 0)
        let fullString = String(cString: cpu)
        
        if fullString.isEmpty {
            var size2 = 0
            sysctlbyname("hw.machine", nil, &size2, nil, 0)
            var machine = [CChar](repeating: 0, count: size2)
            sysctlbyname("hw.machine", &machine, &size2, nil, 0)
            let machineStr = String(cString: machine)
            if machineStr.contains("arm64") { return "Apple Silicon" }
        }
        return fullString.replacingOccurrences(of: "(R)", with: "").replacingOccurrences(of: "(TM)", with: "").trimmingCharacters(in: .whitespaces)
    }
    
    private static func getMemoryGB() -> Int {
        var size: size_t = MemoryLayout<Int64>.size
        var memSize: Int64 = 0
        sysctlbyname("hw.memsize", &memSize, &size, nil, 0)
        return Int(memSize / (1024 * 1024 * 1024))
    }
    
    private static func getMacOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    private static func getUptimeHours() -> Int {
        let uptime = ProcessInfo.processInfo.systemUptime
        return Int(uptime / 3600)
    }
}
