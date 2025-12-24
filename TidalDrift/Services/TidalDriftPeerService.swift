import Foundation
import Network
import IOKit
import os.log

/// Service to advertise this TidalDrift instance and discover peers
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
    
    // Use older NetService APIs which have better compatibility
    private var netService: NetService?
    private var netServiceBrowser: NetServiceBrowser?
    private var discoveredServices: [NetService] = []
    
    private let serviceType = "_tidaldrift._tcp."
    private let serviceDomain = "local."
    private let port: Int32 = 51235
    
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
            screenSharingEnabled: true, // Will be updated when we check
            fileSharingEnabled: true    // Will be updated when we check
        )
        
        Self.log("Service initialized")
        Self.log("Local hostname: \(hostname)")
        Self.log("Local IP: \(ipAddress)")
        Self.log("Model: \(localInfo.modelName)")
    }
    
    // MARK: - Advertising (using NetService for better compatibility)
    
    func startAdvertising() {
        guard netService == nil else {
            Self.log("Already advertising, skipping")
            return
        }
        
        Self.log("Starting advertising as '\(localInfo.hostname)' using NetService")
        
        // Create NetService for advertising - use port 0 for auto-assign
        netService = NetService(
            domain: "",  // Empty domain for local network
            type: "_tidaldrift._tcp.",
            name: localInfo.hostname,
            port: 0  // Auto-assign port
        )
        
        // Set TXT record with our info
        let txtData = createTXTRecordData()
        netService?.setTXTRecord(txtData)
        
        netService?.delegate = self
        netService?.publish()  // Simple publish without options
        
        Self.log("NetService publish started")
    }
    
    func stopAdvertising() {
        netService?.stop()
        netService = nil
        DispatchQueue.main.async {
            self.isAdvertising = false
        }
    }
    
    private func createTXTRecordData() -> Data {
        let dict: [String: Data] = [
            "model": localInfo.modelName.data(using: .utf8) ?? Data(),
            "modelId": localInfo.modelIdentifier.data(using: .utf8) ?? Data(),
            "cpu": localInfo.processorInfo.data(using: .utf8) ?? Data(),
            "mem": "\(localInfo.memoryGB)".data(using: .utf8) ?? Data(),
            "os": localInfo.macOSVersion.data(using: .utf8) ?? Data(),
            "user": localInfo.userName.data(using: .utf8) ?? Data(),
            "uptime": "\(localInfo.uptimeHours)".data(using: .utf8) ?? Data(),
            "version": localInfo.tidalDriftVersion.data(using: .utf8) ?? Data(),
            "screen": (localInfo.screenSharingEnabled ? "1" : "0").data(using: .utf8) ?? Data(),
            "file": (localInfo.fileSharingEnabled ? "1" : "0").data(using: .utf8) ?? Data()
        ]
        return NetService.data(fromTXTRecord: dict)
    }
    
    // MARK: - Discovery (using NetServiceBrowser for better compatibility)
    
    func startDiscovery() {
        guard netServiceBrowser == nil else {
            Self.log("Already browsing, skipping")
            return
        }
        
        Self.log("Starting discovery for _tidaldrift._tcp.")
        
        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser?.delegate = self
        // Use empty domain for local network search
        netServiceBrowser?.searchForServices(ofType: "_tidaldrift._tcp.", inDomain: "")
        
        Self.log("NetServiceBrowser search started")
    }
    
    func stopDiscovery() {
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        discoveredServices.removeAll()
    }
    
    func refreshDiscovery() {
        Self.log("Refreshing discovery...")
        stopDiscovery()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startDiscovery()
        }
    }
    
    private func processDiscoveredService(_ service: NetService) {
        let name = service.name
        
        // Skip ourselves
        if name == localInfo.hostname {
            Self.log("Skipping self: \(name)")
            return
        }
        
        Self.log("Processing discovered service: '\(name)'")
        
        // Get TXT record
        if let txtData = service.txtRecordData() {
            let txtDict = NetService.dictionary(fromTXTRecord: txtData)
            let peer = parseTXTRecord(txtDict, name: name)
            Self.log("Parsed TXT: model=\(peer.modelName), user=\(peer.userName)")
            
            // Get IP from resolved addresses
            var ipAddress = ""
            if let addresses = service.addresses {
                for address in addresses {
                    if let ip = extractIPAddress(from: address) {
                        ipAddress = ip
                        break
                    }
                }
            }
            
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
                self.discoveredPeers[name] = updatedPeer
                self.notifyNetworkDiscovery(peer: updatedPeer)
                Self.log("✅ Added peer '\(name)' IP: \(ipAddress.isEmpty ? "resolving" : ipAddress)")
            }
        } else {
            Self.log("No TXT record for '\(name)'")
        }
    }
    
    private func extractIPAddress(from addressData: Data) -> String? {
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        
        let result = addressData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> Int32 in
            guard let sockaddr = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                return -1
            }
            return getnameinfo(sockaddr, socklen_t(addressData.count),
                             &hostname, socklen_t(hostname.count),
                             nil, 0, NI_NUMERICHOST)
        }
        
        if result == 0 {
            let ip = String(cString: hostname)
            // Skip IPv6 link-local addresses
            if !ip.hasPrefix("fe80:") {
                return ip
            }
        }
        return nil
    }
    
    private func parseTXTRecord(_ record: [String: Data], name: String) -> PeerInfo {
        func getString(_ key: String) -> String {
            if let data = record[key], let str = String(data: data, encoding: .utf8) {
                return str
            }
            return ""
        }
        
        return PeerInfo(
            hostname: name,
            ipAddress: "",
            modelName: getString("model").isEmpty ? "Unknown" : getString("model"),
            modelIdentifier: getString("modelId"),
            processorInfo: getString("cpu"),
            memoryGB: Int(getString("mem")) ?? 0,
            macOSVersion: getString("os"),
            userName: getString("user"),
            uptimeHours: Int(getString("uptime")) ?? 0,
            tidalDriftVersion: getString("version"),
            screenSharingEnabled: getString("screen") == "1",
            fileSharingEnabled: getString("file") == "1"
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

// MARK: - NetServiceDelegate

extension TidalDriftPeerService: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        Self.log("✅ NetService published: \(sender.name)")
        DispatchQueue.main.async {
            self.isAdvertising = true
        }
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        Self.log("❌ NetService failed to publish: \(errorDict)")
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        Self.log("NetService resolved: \(sender.name)")
        processDiscoveredService(sender)
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        Self.log("NetService failed to resolve: \(sender.name) - \(errorDict)")
    }
}

// MARK: - NetServiceBrowserDelegate

extension TidalDriftPeerService: NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        Self.log("Browser will search")
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        Self.log("Browser stopped search")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        Self.log("❌ Browser failed to search: \(errorDict)")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Self.log("Found service: '\(service.name)' (more coming: \(moreComing))")
        
        // Skip ourselves
        if service.name == localInfo.hostname {
            Self.log("Skipping self")
            return
        }
        
        // Keep track of discovered services and resolve them
        discoveredServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        Self.log("Service removed: '\(service.name)'")
        discoveredServices.removeAll { $0.name == service.name }
        
        // Remove from discovered peers
        DispatchQueue.main.async {
            self.discoveredPeers.removeValue(forKey: service.name)
        }
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

