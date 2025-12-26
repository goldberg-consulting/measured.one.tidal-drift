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
        
        // Write to file asynchronously to avoid blocking
        DispatchQueue.global(qos: .utility).async {
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
    }
    
    @Published var discoveredPeers: [String: PeerInfo] = [:] // keyed by IP
    @Published var isAdvertising = false
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.tidaldrift.peer.network", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    
    // Fallback: Use NetService for reliable Bonjour advertising
    private var netService: NetService?
    private var netServiceBrowser: NetServiceBrowser?
    
    private var telemetryTimer: Timer?
    // UDP heartbeat disabled - requires special permissions
    // private var udpHeartbeatTimer: Timer?
    
    private let serviceType = "_tidaldrift._tcp"
    private let dropServiceType = "_tidaldrop._tcp"
    private let deviceName = (Host.current().localizedName ?? "TidalDrift").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: " ", with: "-")
    
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
    
    private var dnssdProcess: Process?
    
    func startAdvertising() {
        guard dnssdProcess == nil else {
            Self.log("Already advertising, skipping")
            return
        }
        
        Self.log("📢 Starting Bonjour advertisement via dns-sd")
        
        // Use dns-sd command line tool which reliably works
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        
        // Build TXT record string
        let txtParts = [
            "model=\(localInfo.modelName)",
            "os=\(localInfo.macOSVersion)",
            "user=\(localInfo.userName)",
            "version=\(localInfo.tidalDriftVersion)"
        ]
        
        // dns-sd -R <name> <type> <domain> <port> [txt...]
        var args = ["-R", deviceName, serviceType, "local.", "5959"]
        args.append(contentsOf: txtParts)
        process.arguments = args
        
        // Silence output
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            dnssdProcess = process
            Self.log("✅ dns-sd process started with PID \(process.processIdentifier)")
            DispatchQueue.main.async {
                self.isAdvertising = true
            }
        } catch {
            Self.log("❌ Failed to start dns-sd: \(error)")
        }
    }
    
    func stopAdvertising() {
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        
        listener?.cancel()
        listener = nil
        
        if let service = netService {
            service.remove(from: .main, forMode: .common)
            service.stop()
        }
        netService = nil
        
        // Stop dns-sd process
        if let process = dnssdProcess, process.isRunning {
            process.terminate()
            Self.log("Terminated dns-sd process")
        }
        dnssdProcess = nil
        
        DispatchQueue.main.async {
            self.isAdvertising = false
        }
        Self.log("Stopped advertising")
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
    
    private func createTXTDictionary() -> [String: Data] {
        var dict = [String: Data]()
        dict["model"] = localInfo.modelName.data(using: .utf8)
        dict["modelId"] = localInfo.modelIdentifier.data(using: .utf8)
        dict["cpu"] = localInfo.processorInfo.data(using: .utf8)
        dict["mem"] = "\(localInfo.memoryGB)".data(using: .utf8)
        dict["os"] = localInfo.macOSVersion.data(using: .utf8)
        dict["user"] = localInfo.userName.data(using: .utf8)
        dict["uptime"] = "\(localInfo.uptimeHours)".data(using: .utf8)
        dict["version"] = localInfo.tidalDriftVersion.data(using: .utf8)
        dict["screen"] = (localInfo.screenSharingEnabled ? "1" : "0").data(using: .utf8)
        dict["file"] = (localInfo.fileSharingEnabled ? "1" : "0").data(using: .utf8)
        return dict.compactMapValues { $0 }
    }
    
    // MARK: - Discovery (Network.framework)
    
    private var browseProcess: Process?
    private var browseOutputPipe: Pipe?
    
    func startDiscovery() {
        guard browseProcess == nil else {
            Self.log("Already browsing, skipping")
            return
        }
        
        Self.log("Starting discovery for \(serviceType) via dns-sd")
        
        // Use dns-sd command line tool which bypasses permission issues
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        process.arguments = ["-B", serviceType, "local."]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        browseOutputPipe = pipe
        
        // Read output asynchronously
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                self?.parseBrowseOutput(output)
            }
        }
        
        do {
            try process.run()
            browseProcess = process
            Self.log("✅ dns-sd browse process started with PID \(process.processIdentifier)")
        } catch {
            Self.log("❌ Failed to start dns-sd browse: \(error)")
        }
    }
    
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        
        // Stop dns-sd browse process
        browseOutputPipe?.fileHandleForReading.readabilityHandler = nil
        if let process = browseProcess, process.isRunning {
            process.terminate()
            Self.log("Terminated dns-sd browse process")
        }
        browseProcess = nil
        browseOutputPipe = nil
        
        Self.log("Stopped discovery")
    }
    
    private func parseBrowseOutput(_ output: String) {
        // Parse dns-sd -B output format:
        // Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
        // 21:22:27.364  Add        3   1 local.               _tidaldrift._tcp.    Eli's-MacBook-Pro
        
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            // Skip header lines and empty lines
            if line.contains("Browsing for") || line.contains("DATE:") || 
               line.contains("Timestamp") || line.contains("STARTING") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            
            // Check if this is an "Add" line
            if line.contains("Add") {
                // Extract the instance name (last column)
                let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if components.count >= 7 {
                    // Instance name is everything after the service type
                    let serviceTypeIndex = components.firstIndex { $0.contains("_tidaldrift") }
                    if let idx = serviceTypeIndex, idx + 1 < components.count {
                        let instanceName = components[(idx + 1)...].joined(separator: " ")
                        
                        let isSelf = instanceName == deviceName
                        Self.log("🔎 Discovered via dns-sd: '\(instanceName)'\(isSelf ? " (self)" : "")")
                        
                        // Resolve the service to get IP
                        resolveServiceViaDnsSd(name: instanceName)
                    }
                }
            }
        }
    }
    
    private var resolveProcesses: [String: Process] = [:]
    
    private func resolveServiceViaDnsSd(name: String) {
        // Skip if already resolving this service
        guard resolveProcesses[name] == nil else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        process.arguments = ["-L", name, serviceType, "local."]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                self?.parseResolveOutput(output, name: name)
            }
        }
        
        do {
            try process.run()
            resolveProcesses[name] = process
            
            // Kill resolve process after 5 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                if let p = self?.resolveProcesses[name], p.isRunning {
                    p.terminate()
                }
                self?.resolveProcesses[name] = nil
            }
        } catch {
            Self.log("❌ Failed to resolve \(name): \(error)")
        }
    }
    
    private func parseResolveOutput(_ output: String, name: String) {
        // Parse dns-sd -L output to get host and port
        // Then use dns-sd -G to get the IP address
        
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains("can be reached at") {
                // Format: "ServiceName._tidaldrift._tcp.local. can be reached at hostname.local.:port"
                if let hostRange = line.range(of: "at "), let portRange = line.range(of: ":5959") ?? line.range(of: ":\\d+", options: .regularExpression) {
                    let hostStart = hostRange.upperBound
                    let hostEnd = portRange.lowerBound
                    let hostname = String(line[hostStart..<hostEnd])
                    
                    Self.log("Resolved \(name) -> host: \(hostname)")
                    
                    // For now, try to get IP via hostname lookup
                    lookupIP(for: name, hostname: hostname)
                }
            }
        }
    }
    
    private func lookupIP(for name: String, hostname: String) {
        // Use dns-sd -G to lookup IPv4 address
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        process.arguments = ["-G", "v4", hostname]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                // Parse IP from output
                let lines = output.components(separatedBy: "\n")
                for line in lines {
                    // Look for IPv4 address pattern
                    if let match = line.range(of: "\\d+\\.\\d+\\.\\d+\\.\\d+", options: .regularExpression) {
                        let ip = String(line[match])
                        self?.addDiscoveredPeer(name: name, ip: ip)
                        process.terminate()
                        break
                    }
                }
            }
        }
        
        do {
            try process.run()
            
            // Kill lookup process after 3 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if process.isRunning {
                    process.terminate()
                }
            }
        } catch {
            Self.log("❌ Failed to lookup IP for \(hostname): \(error)")
        }
    }
    
    private func addDiscoveredPeer(name: String, ip: String) {
        // If it's localhost (self), use actual LAN IP
        var actualIP = ip
        if ip == "127.0.0.1" || ip == "::1" {
            actualIP = localInfo.ipAddress
        }
        
        let isSelf = name == deviceName
        
        // For self, use our detailed local info
        let peer: PeerInfo
        if isSelf {
            Self.log("✅ Found self: \(name) at \(actualIP)")
            peer = localInfo
        } else {
            Self.log("✅ Discovered peer: \(name) at \(actualIP)")
            peer = PeerInfo(
                hostname: name,
                ipAddress: actualIP,
                modelName: "Unknown",
                modelIdentifier: "Unknown",
                processorInfo: "Unknown",
                memoryGB: 0,
                macOSVersion: "Unknown",
                userName: "Unknown",
                uptimeHours: 0,
                tidalDriftVersion: "1.0",
                screenSharingEnabled: true,
                fileSharingEnabled: true
            )
        }
        
        DispatchQueue.main.async {
            // Always notify network discovery to mark as TidalDrift peer
            // (even for self - this ensures the red outline shows)
            self.notifyNetworkDiscovery(peer: peer)
            
            // Only add to discoveredPeers list if not self
            if !isSelf {
                self.discoveredPeers[actualIP] = peer
            }
        }
    }
    
    private func processBrowseResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            if case .service(let name, let type, let domain, _) = result.endpoint {
                let isSelf = name == deviceName
                Self.log("Discovered service: '\(name)'\(isSelf ? " (self)" : "")")
                
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

// MARK: - NetServiceDelegate
extension TidalDriftPeerService: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        print("🎉🎉🎉 DELEGATE CALLBACK: netServiceDidPublish for \(sender.name) on port \(sender.port)")
        Self.log("✅ NetService published: \(sender.name) on port \(sender.port)")
        DispatchQueue.main.async {
            self.isAdvertising = true
        }
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        let errorCode = errorDict[NetService.errorCode]?.intValue ?? -1
        let errorDomain = errorDict[NetService.errorDomain]?.intValue ?? -1
        print("❌❌❌ DELEGATE CALLBACK: didNotPublish code=\(errorCode) domain=\(errorDomain)")
        Self.log("❌ NetService failed to publish: code=\(errorCode) domain=\(errorDomain)")
        DispatchQueue.main.async {
            self.isAdvertising = false
        }
    }
    
    func netServiceDidStop(_ sender: NetService) {
        print("🛑 DELEGATE CALLBACK: netServiceDidStop")
        Self.log("NetService stopped")
    }
    
    func netServiceWillPublish(_ sender: NetService) {
        print("📢 DELEGATE CALLBACK: netServiceWillPublish")
        Self.log("NetService will publish: \(sender.name)")
    }
}

// MARK: - NetServiceBrowserDelegate
extension TidalDriftPeerService: NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        print("🔎🔎🔎 NetServiceBrowserWillSearch")
        Self.log("NetServiceBrowser will search")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("🔎🔎🔎 FOUND SERVICE: \(service.name)")
        Self.log("🔎 Discovered service: '\(service.name)' type: \(service.type)")
        
        // Note: For single-computer testing, we don't skip ourselves
        let isSelf = service.name == deviceName
        if isSelf {
            Self.log("(This is our own service)")
        }
        
        // Resolve the service to get IP address and TXT record
        service.delegate = self
        service.resolve(withTimeout: 10.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        Self.log("Service removed: \(service.name)")
        // Could remove from discoveredPeers here if needed
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        let errorCode = errorDict[NetService.errorCode]?.intValue ?? -1
        Self.log("❌ NetServiceBrowser failed to search: code=\(errorCode)")
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        Self.log("NetServiceBrowser stopped searching")
    }
    
    // NetService resolution
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses, !addresses.isEmpty else {
            Self.log("Resolved \(sender.name) but no addresses found")
            return
        }
        
        // Extract IP address from the first address
        var ipAddress = ""
        for addressData in addresses {
            addressData.withUnsafeBytes { ptr in
                let sockaddr = ptr.load(as: sockaddr.self)
                if sockaddr.sa_family == UInt8(AF_INET) {
                    // IPv4
                    let sockaddr_in = ptr.load(as: sockaddr_in.self)
                    var addr = sockaddr_in.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                        ipAddress = String(cString: buffer)
                    }
                }
            }
            if !ipAddress.isEmpty { break }
        }
        
        guard !ipAddress.isEmpty else {
            Self.log("Could not extract IP for \(sender.name)")
            return
        }
        
        // Parse TXT record
        var txtValues: [String: String] = [:]
        if let txtData = sender.txtRecordData() {
            let txtDict = NetService.dictionary(fromTXTRecord: txtData)
            for (key, value) in txtDict {
                if let str = String(data: value, encoding: .utf8) {
                    txtValues[key] = str
                }
            }
        }
        
        Self.log("✅ Resolved \(sender.name) -> \(ipAddress)")
        
        let peer = PeerInfo(
            hostname: sender.name,
            ipAddress: ipAddress,
            modelName: txtValues["model"] ?? "Unknown",
            modelIdentifier: txtValues["modelId"] ?? "Unknown",
            processorInfo: txtValues["cpu"] ?? "Unknown",
            memoryGB: Int(txtValues["mem"] ?? "0") ?? 0,
            macOSVersion: txtValues["os"] ?? "Unknown",
            userName: txtValues["user"] ?? "Unknown",
            uptimeHours: Int(txtValues["uptime"] ?? "0") ?? 0,
            tidalDriftVersion: txtValues["version"] ?? "1.0",
            screenSharingEnabled: txtValues["screen"] == "1",
            fileSharingEnabled: txtValues["file"] == "1"
        )
        
        DispatchQueue.main.async {
            self.discoveredPeers[ipAddress] = peer
            self.notifyNetworkDiscovery(peer: peer)
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        let errorCode = errorDict[NetService.errorCode]?.intValue ?? -1
        Self.log("❌ Failed to resolve \(sender.name): code=\(errorCode)")
    }
}

