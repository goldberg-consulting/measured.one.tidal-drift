import Foundation
import Network
import IOKit
import os.log

/// Service to advertise this TidalDrift instance and discover peers
/// Uses modern NWListener/NWBrowser API for better compatibility and reliability
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
    
    @Published var discoveredPeers: [String: PeerInfo] = [:] // keyed by hostname/IP
    @Published var isAdvertising = false
    
    // Use modern Network.framework APIs (same as ClipboardSyncService)
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var resolvingConnections: [String: NWConnection] = [:] // Track connections for IP resolution
    
    private let serviceType = "_tidaldrift._tcp" // No trailing dot for NWListener
    private let serviceDomain = "local."
    private let port: UInt16 = 51235
    
    private let localInfo: PeerInfo
    private let queue = DispatchQueue.main // Use main queue like ClipboardSyncService
    
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
            screenSharingEnabled: true, // Will be updated when we check
            fileSharingEnabled: true    // Will be updated when we check
        )
        
        Self.log("Service initialized")
        Self.log("Local hostname: \(hostname)")
        Self.log("Local IP: \(ipAddress)")
        Self.log("Model: \(localInfo.modelName)")
    }
    
    // MARK: - Advertising (using NWListener like ClipboardSyncService)
    
    func startAdvertising() {
        guard listener == nil else {
            Self.log("Already advertising, skipping")
            return
        }
        
        Self.log("Starting advertising as '\(localInfo.hostname)' using NWListener")
        
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            
            // Set up Bonjour service advertisement
            listener?.service = NWListener.Service(
                name: localInfo.hostname,
                type: serviceType,
                domain: serviceDomain,
                txtRecord: createTXTRecord()
            )
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        Self.log("✅ NWListener ready - service published successfully")
                        self?.isAdvertising = true
                    case .failed(let error):
                        Self.log("❌ NWListener failed: \(error.localizedDescription)")
                        self?.isAdvertising = false
                    case .cancelled:
                        Self.log("NWListener cancelled")
                        self?.isAdvertising = false
                    case .waiting(let error):
                        Self.log("NWListener waiting: \(error.localizedDescription)")
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                Self.log("New connection received from peer")
                // Accept connections from other TidalDrift instances
                connection.start(queue: self?.queue ?? .main)
            }
            
            listener?.start(queue: queue)
            Self.log("NWListener started on port \(port)")
            
        } catch {
            Self.log("❌ Failed to create NWListener: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isAdvertising = false
            }
        }
    }
    
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isAdvertising = false
        }
        Self.log("Stopped advertising")
    }
    
    private func createTXTRecord() -> NWTXTRecord {
        var txtRecord = NWTXTRecord()
        txtRecord["model"] = localInfo.modelName
        txtRecord["modelId"] = localInfo.modelIdentifier
        txtRecord["cpu"] = localInfo.processorInfo
        txtRecord["mem"] = "\(localInfo.memoryGB)"
        txtRecord["os"] = localInfo.macOSVersion
        txtRecord["user"] = localInfo.userName
        txtRecord["uptime"] = "\(localInfo.uptimeHours)"
        txtRecord["version"] = localInfo.tidalDriftVersion
        txtRecord["screen"] = localInfo.screenSharingEnabled ? "1" : "0"
        txtRecord["file"] = localInfo.fileSharingEnabled ? "1" : "0"
        return txtRecord
    }
    
    // MARK: - Discovery (using NWBrowser like ClipboardSyncService)
    
    func startDiscovery() {
        guard browser == nil else {
            Self.log("Already browsing, skipping")
            return
        }
        
        Self.log("Starting discovery for \(serviceType)")
        
        let params = NWParameters()
        params.includePeerToPeer = true
        
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: serviceDomain), using: params)
        
        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Self.log("✅ NWBrowser ready - browsing started")
            case .failed(let error):
                Self.log("❌ NWBrowser failed: \(error.localizedDescription)")
            case .cancelled:
                Self.log("NWBrowser cancelled")
            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results, changes: changes)
            }
        }
        
        browser?.start(queue: queue)
        Self.log("NWBrowser started")
    }
    
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        // Cancel any pending resolution connections
        resolvingConnections.values.forEach { $0.cancel() }
        resolvingConnections.removeAll()
        Self.log("Stopped discovery")
    }
    
    func refreshDiscovery() {
        Self.log("Refreshing discovery...")
        stopDiscovery()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startDiscovery()
        }
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                handleDiscoveredService(result)
            case .removed(let result):
                handleRemovedService(result)
            case .changed(let old, let new, _):
                // Service updated
                handleRemovedService(old)
                handleDiscoveredService(new)
            case .identical:
                // No change needed
                break
            @unknown default:
                break
            }
        }
    }
    
    private func handleDiscoveredService(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else {
            return
        }
        
        // Skip ourselves
        if name == localInfo.hostname {
            Self.log("Skipping self: \(name)")
            return
        }
        
        Self.log("Found service: '\(name)'")
        
        // Extract TXT record from metadata
        var peerInfo: PeerInfo?
        if case .bonjour(let txtRecord) = result.metadata {
            peerInfo = parseTXTRecord(txtRecord, name: name)
        } else {
            // Create minimal peer info if no TXT record
            peerInfo = PeerInfo(
                hostname: name,
                ipAddress: "",
                modelName: "Unknown",
                modelIdentifier: "",
                processorInfo: "",
                memoryGB: 0,
                macOSVersion: "",
                userName: "",
                uptimeHours: 0,
                tidalDriftVersion: "",
                screenSharingEnabled: false,
                fileSharingEnabled: false
            )
        }
        
        guard let peer = peerInfo else {
            Self.log("Failed to parse peer info for '\(name)'")
            return
        }
        
        // Resolve IP address by attempting a connection
        resolvePeerIP(result: result, peer: peer)
    }
    
    private func resolvePeerIP(result: NWBrowser.Result, peer: PeerInfo) {
        // Check if already resolving
        if resolvingConnections[peer.hostname] != nil {
            return
        }
        
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        resolvingConnections[peer.hostname] = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                // Extract IP from connection path
                if let path = connection.currentPath,
                   case .hostPort(let host, _) = path.remoteEndpoint {
                    var ipAddress = ""
                    switch host {
                    case .ipv4(let addr):
                        ipAddress = "\(addr)"
                    case .ipv6(let addr):
                        let addrString = "\(addr)"
                        // Skip IPv6 link-local addresses
                        if !addrString.hasPrefix("fe80:") {
                            ipAddress = addrString
                        }
                    case .name(let hostname, _):
                        ipAddress = hostname
                    @unknown default:
                        break
                    }
                    
                    // Clean IP (remove interface suffix)
                    if let percentIndex = ipAddress.firstIndex(of: "%") {
                        ipAddress = String(ipAddress[..<percentIndex])
                    }
                    
                    if !ipAddress.isEmpty {
                        let updatedPeer = PeerInfo(
                            hostname: peer.hostname,
                            ipAddress: ipAddress,
                            modelName: peer.modelName,
                            modelIdentifier: peer.modelIdentifier,
                            processorInfo: peer.processorInfo,
                            memoryGB: peer.memoryGB,
                            macOSVersion: peer.macOSVersion,
                            userName: peer.userName,
                            uptimeHours: peer.uptimeHours,
                            tidalDriftVersion: peer.tidalDriftVersion,
                            screenSharingEnabled: peer.screenSharingEnabled,
                            fileSharingEnabled: peer.fileSharingEnabled
                        )
                        
                        DispatchQueue.main.async {
                            self.discoveredPeers[peer.hostname] = updatedPeer
                            self.notifyNetworkDiscovery(peer: updatedPeer)
                            Self.log("✅ Added peer '\(peer.hostname)' IP: \(ipAddress)")
                        }
                    }
                }
                
                // Cancel connection after resolving
                connection.cancel()
                self.resolvingConnections.removeValue(forKey: peer.hostname)
                
            case .failed(let error):
                Self.log("Failed to resolve IP for '\(peer.hostname)': \(error.localizedDescription)")
                connection.cancel()
                self.resolvingConnections.removeValue(forKey: peer.hostname)
                
            case .cancelled:
                self.resolvingConnections.removeValue(forKey: peer.hostname)
                
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        
        // Timeout after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.resolvingConnections[peer.hostname] === connection {
                Self.log("Timeout resolving IP for '\(peer.hostname)'")
                connection.cancel()
                self.resolvingConnections.removeValue(forKey: peer.hostname)
            }
        }
    }
    
    private func handleRemovedService(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else {
            return
        }
        
        Self.log("Service removed: '\(name)'")
        
        // Cancel any pending resolution
        resolvingConnections[name]?.cancel()
        resolvingConnections.removeValue(forKey: name)
        
        // Remove from discovered peers
        DispatchQueue.main.async {
            self.discoveredPeers.removeValue(forKey: name)
        }
    }
    
    private func parseTXTRecord(_ txtRecord: NWTXTRecord?, name: String) -> PeerInfo {
        guard let txtRecord = txtRecord else {
            return PeerInfo(
                hostname: name,
                ipAddress: "",
                modelName: "Unknown",
                modelIdentifier: "",
                processorInfo: "",
                memoryGB: 0,
                macOSVersion: "",
                userName: "",
                uptimeHours: 0,
                tidalDriftVersion: "",
                screenSharingEnabled: false,
                fileSharingEnabled: false
            )
        }
        
        return PeerInfo(
            hostname: name,
            ipAddress: "",
            modelName: txtRecord["model"]?.isEmpty == false ? txtRecord["model"]! : "Unknown",
            modelIdentifier: txtRecord["modelId"] ?? "",
            processorInfo: txtRecord["cpu"] ?? "",
            memoryGB: Int(txtRecord["mem"] ?? "0") ?? 0,
            macOSVersion: txtRecord["os"] ?? "",
            userName: txtRecord["user"] ?? "",
            uptimeHours: Int(txtRecord["uptime"] ?? "0") ?? 0,
            tidalDriftVersion: txtRecord["version"] ?? "",
            screenSharingEnabled: txtRecord["screen"] == "1",
            fileSharingEnabled: txtRecord["file"] == "1"
        )
    }
    
    private func notifyNetworkDiscovery(peer: PeerInfo) {
        // Update any existing device in NetworkDiscoveryService with TidalDrift peer info
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
        
        // Map identifier to friendly name
        if modelString.contains("MacBookPro") {
            return "MacBook Pro"
        } else if modelString.contains("MacBookAir") {
            return "MacBook Air"
        } else if modelString.contains("iMac") {
            return "iMac"
        } else if modelString.contains("Macmini") {
            return "Mac mini"
        } else if modelString.contains("MacPro") {
            return "Mac Pro"
        } else if modelString.contains("Mac14") || modelString.contains("Mac15") {
            // M-series Macs
            return "MacBook Pro"
        }
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
        
        // Clean up the string
        if fullString.isEmpty {
            // Probably Apple Silicon
            var size2 = 0
            sysctlbyname("hw.machine", nil, &size2, nil, 0)
            var machine = [CChar](repeating: 0, count: size2)
            sysctlbyname("hw.machine", &machine, &size2, nil, 0)
            let machineStr = String(cString: machine)
            
            if machineStr.contains("arm64") {
                return "Apple Silicon"
            }
        }
        
        return fullString
            .replacingOccurrences(of: "(R)", with: "")
            .replacingOccurrences(of: "(TM)", with: "")
            .trimmingCharacters(in: .whitespaces)
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

// MARK: - NetworkDiscoveryService Extension

extension NetworkDiscoveryService {
    private static let peerLogger = Logger(subsystem: "com.tidaldrift", category: "PeerMatching")
    
    func markAsTidalDriftPeer(hostname: String, peerInfo: TidalDriftPeerService.PeerInfo) {
        DispatchQueue.main.async {
            // Try to find matching device by hostname, name, or IP address
            let normalizedHostname = hostname.lowercased().replacingOccurrences(of: ".local", with: "")
            
            Self.peerLogger.info("Looking for device matching '\(hostname)' (normalized: '\(normalizedHostname)')")
            Self.peerLogger.info("Current devices: \(self.discoveredDevices.map { $0.name }.joined(separator: ", "))")
            
            if let index = self.discoveredDevices.firstIndex(where: { device in
                let deviceName = device.name.lowercased()
                let deviceHostname = device.hostname.lowercased().replacingOccurrences(of: ".local", with: "")
                let deviceIP = device.ipAddress
                
                let matches = deviceName == normalizedHostname ||
                       deviceHostname == normalizedHostname ||
                       deviceName.contains(normalizedHostname) ||
                       normalizedHostname.contains(deviceName) ||
                       (!peerInfo.ipAddress.isEmpty && deviceIP == peerInfo.ipAddress)
                
                if matches {
                    Self.peerLogger.info("Match found: \(device.name)")
                }
                return matches
            }) {
                var device = self.discoveredDevices[index]
                device.isTidalDriftPeer = true
                device.peerModelName = peerInfo.modelName
                device.peerModelIdentifier = peerInfo.modelIdentifier
                device.peerProcessorInfo = peerInfo.processorInfo
                device.peerMemoryGB = peerInfo.memoryGB
                device.peerMacOSVersion = peerInfo.macOSVersion
                device.peerUserName = peerInfo.userName
                device.peerUptimeHours = peerInfo.uptimeHours
                
                // Update IP if we have a resolved one
                if !peerInfo.ipAddress.isEmpty && peerInfo.ipAddress != "Resolving..." {
                    device.ipAddress = peerInfo.ipAddress
                }
                
                self.discoveredDevices[index] = device
                Self.peerLogger.info("✅ Marked '\(device.name)' as TidalDrift peer")
                print("🌊 TidalDrift PEER: Marked \(device.name) as TidalDrift peer (matched from \(hostname))")
            } else {
                // Create a new device entry for this TidalDrift peer
                let displayName = hostname.replacingOccurrences(of: ".local", with: "")
                let newDevice = DiscoveredDevice(
                    name: displayName,
                    hostname: hostname.hasSuffix(".local") ? hostname : "\(hostname).local",
                    ipAddress: peerInfo.ipAddress.isEmpty ? "Resolving..." : peerInfo.ipAddress,
                    services: peerInfo.screenSharingEnabled ? [.screenSharing] : [],
                    lastSeen: Date(),
                    isTrusted: false,
                    isTidalDriftPeer: true,
                    peerModelName: peerInfo.modelName,
                    peerModelIdentifier: peerInfo.modelIdentifier,
                    peerProcessorInfo: peerInfo.processorInfo,
                    peerMemoryGB: peerInfo.memoryGB,
                    peerMacOSVersion: peerInfo.macOSVersion,
                    peerUserName: peerInfo.userName,
                    peerUptimeHours: peerInfo.uptimeHours
                )
                self.discoveredDevices.append(newDevice)
                Self.peerLogger.info("✅ Added new TidalDrift peer: '\(displayName)'")
                print("🌊 TidalDrift PEER: Added new TidalDrift peer: \(displayName)")
            }
        }
    }
}
