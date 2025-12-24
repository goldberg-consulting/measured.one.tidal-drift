import Foundation
import Network
import Combine

class NetworkDiscoveryService: ObservableObject {
    static let shared = NetworkDiscoveryService()
    
    @Published var discoveredDevices: [DiscoveredDevice] = []
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
        guard browsers.isEmpty else { return }
        
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
        case .ready, .cancelled:
            break
        case .failed(let error):
            #if DEBUG
            print("Browser failed for \(serviceType): \(error)")
            #endif
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
        
        let portNumber = Int(port.rawValue)
        let service = mapServiceType(serviceType)
        
        switch host {
        case .ipv4(let addr):
            let ipAddress = cleanIPAddress("\(addr)")
            DispatchQueue.main.async { [weak self] in
                self?.addOrUpdateDevice(name: name, ipAddress: ipAddress, port: portNumber, service: service)
            }
        case .ipv6(let addr):
            // Only use IPv6 if it's not a link-local address
            let ipAddress = cleanIPAddress("\(addr)")
            if !ipAddress.hasPrefix("fe80") {
                DispatchQueue.main.async { [weak self] in
                    self?.addOrUpdateDevice(name: name, ipAddress: ipAddress, port: portNumber, service: service)
                }
            }
        case .name(let hostname, _):
            // Resolve hostname to IP address
            resolveHostnameToIP(hostname) { [weak self] resolvedIP in
                if let ip = resolvedIP {
                    DispatchQueue.main.async {
                        self?.addOrUpdateDevice(name: name, ipAddress: self?.cleanIPAddress(ip) ?? ip, port: portNumber, service: service)
                    }
                }
            }
        @unknown default:
            break
        }
    }
    
    /// Remove interface suffix from IP addresses (e.g., "192.168.1.125%en0" -> "192.168.1.125")
    private func cleanIPAddress(_ ip: String) -> String {
        if let percentIndex = ip.firstIndex(of: "%") {
            return String(ip[..<percentIndex])
        }
        return ip
    }
    
    private func resolveHostnameToIP(_ hostname: String, completion: @escaping (String?) -> Void) {
        // Use getaddrinfo to resolve hostname to IP
        queue.async {
            var hints = addrinfo()
            hints.ai_family = AF_INET  // Prefer IPv4
            hints.ai_socktype = SOCK_STREAM
            
            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(hostname, nil, &hints, &result)
            
            defer {
                if result != nil {
                    freeaddrinfo(result)
                }
            }
            
            guard status == 0, let addrInfo = result else {
                // Try IPv6 if IPv4 fails
                var hints6 = addrinfo()
                hints6.ai_family = AF_INET6
                hints6.ai_socktype = SOCK_STREAM
                
                var result6: UnsafeMutablePointer<addrinfo>?
                let status6 = getaddrinfo(hostname, nil, &hints6, &result6)
                
                defer {
                    if result6 != nil {
                        freeaddrinfo(result6)
                    }
                }
                
                guard status6 == 0, let addrInfo6 = result6 else {
                    completion(nil)
                    return
                }
                
                // Extract IPv6 address
                if let sockaddr = addrInfo6.pointee.ai_addr {
                    var ipBuffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    sockaddr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { addr in
                        var sin6_addr = addr.pointee.sin6_addr
                        inet_ntop(AF_INET6, &sin6_addr, &ipBuffer, socklen_t(INET6_ADDRSTRLEN))
                    }
                    let ip = String(cString: ipBuffer)
                    if !ip.isEmpty && !ip.hasPrefix("fe80") {
                        completion(ip)
                        return
                    }
                }
                completion(nil)
                return
            }
            
            // Extract IPv4 address
            if let sockaddr = addrInfo.pointee.ai_addr {
                var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addr in
                    var sin_addr = addr.pointee.sin_addr
                    inet_ntop(AF_INET, &sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
                }
                let ip = String(cString: ipBuffer)
                if !ip.isEmpty {
                    completion(ip)
                    return
                }
            }
            
            completion(nil)
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
        // Use IP as primary key to avoid duplicates
        let cacheKey = ipAddress
        
        if var existingDevice = deviceCache[cacheKey] {
            existingDevice.lastSeen = Date()
            if let service = service {
                existingDevice.services.insert(service)
            }
            // Prefer more descriptive names over generic ones
            if existingDevice.name.hasPrefix("Mac at ") && !name.hasPrefix("Mac at ") {
                existingDevice.name = name
                existingDevice.hostname = "\(name).local"
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
            // Find and remove device by name match
            deviceCache = deviceCache.filter { !$0.value.name.lowercased().contains(name.lowercased()) }
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
        
        let cacheKey = ipAddress
        deviceCache[cacheKey] = device
        updatePublishedDevices()
    }
    
    /// Mark a device as a TidalDrift peer with enhanced info
    func markAsTidalDriftPeer(ipAddress: String, peerInfo: PeerDiscoveryService.PeerInfo) {
        let cacheKey = ipAddress
        
        if var existingDevice = deviceCache[cacheKey] {
            // Update existing device with peer info
            existingDevice.isTidalDriftPeer = true
            existingDevice.name = peerInfo.computerName
            existingDevice.peerModelName = peerInfo.modelName
            existingDevice.peerModelIdentifier = peerInfo.modelIdentifier
            existingDevice.peerProcessorInfo = peerInfo.processorInfo
            existingDevice.peerMemoryGB = peerInfo.memoryGB
            existingDevice.peerMacOSVersion = peerInfo.macOSVersion
            existingDevice.peerUserName = peerInfo.userName
            existingDevice.peerUptimeHours = peerInfo.uptimeHours
            existingDevice.lastSeen = Date()
            deviceCache[cacheKey] = existingDevice
        } else {
            // Create new device with peer info
            let newDevice = DiscoveredDevice(
                name: peerInfo.computerName,
                hostname: "\(peerInfo.computerName).local",
                ipAddress: ipAddress,
                services: [.screenSharing], // Assume screen sharing since TidalDrift is running
                lastSeen: Date(),
                port: 5900,
                isTidalDriftPeer: true,
                peerModelName: peerInfo.modelName,
                peerModelIdentifier: peerInfo.modelIdentifier,
                peerProcessorInfo: peerInfo.processorInfo,
                peerMemoryGB: peerInfo.memoryGB,
                peerMacOSVersion: peerInfo.macOSVersion,
                peerUserName: peerInfo.userName,
                peerUptimeHours: peerInfo.uptimeHours
            )
            deviceCache[cacheKey] = newDevice
        }
        
        updatePublishedDevices()
    }
    
    // MARK: - Active IP Scanning (for VPNs and when Bonjour fails)
    
    @Published var isScanningSubnet: Bool = false
    @Published var scanProgress: Double = 0
    
    /// Scan a specific IP address for screen sharing service
    func scanIP(_ ipAddress: String, port: Int = 5900) async -> Bool {
        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(ipAddress)
            let port = NWEndpoint.Port(rawValue: UInt16(port))!
            let connection = NWConnection(host: host, port: port, using: .tcp)
            
            var didResume = false
            
            connection.stateUpdateHandler = { state in
                guard !didResume else { return }
                
                switch state {
                case .ready:
                    didResume = true
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    didResume = true
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            
            connection.start(queue: self.queue)
            
            // 2 second timeout per IP
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                guard !didResume else { return }
                didResume = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Scan a range of IPs (e.g., 192.168.1.1 to 192.168.1.254)
    func scanSubnet(baseIP: String, startHost: Int = 1, endHost: Int = 254) async {
        await MainActor.run {
            isScanningSubnet = true
            scanProgress = 0
        }
        
        // Parse base IP (e.g., "192.168.1" from "192.168.1.100")
        let components = baseIP.split(separator: ".")
        guard components.count >= 3 else {
            await MainActor.run { isScanningSubnet = false }
            return
        }
        let subnet = components.prefix(3).joined(separator: ".")
        
        let totalIPs = endHost - startHost + 1
        var scanned = 0
        
        // Scan in batches to avoid overwhelming the network
        let batchSize = 15
        for batchStart in stride(from: startHost, through: endHost, by: batchSize) {
            let batchEnd = min(batchStart + batchSize - 1, endHost)
            
            // Structure to hold scan results for an IP
            struct ScanResult {
                let ip: String
                let hasScreenSharing: Bool
                let hasFileSharing: Bool
                let hasAFP: Bool
            }
            
            await withTaskGroup(of: ScanResult.self) { group in
                for hostNum in batchStart...batchEnd {
                    let ip = "\(subnet).\(hostNum)"
                    group.addTask {
                        // Check all three services in parallel for each IP
                        async let screenShare = self.scanIP(ip, port: 5900)
                        async let fileShare = self.scanIP(ip, port: 445)
                        async let afp = self.scanIP(ip, port: 548)
                        
                        return ScanResult(
                            ip: ip,
                            hasScreenSharing: await screenShare,
                            hasFileSharing: await fileShare,
                            hasAFP: await afp
                        )
                    }
                }
                
                for await result in group {
                    scanned += 1
                    await MainActor.run {
                        scanProgress = Double(scanned) / Double(totalIPs)
                    }
                    
                    let hasAnyService = result.hasScreenSharing || result.hasFileSharing || result.hasAFP
                    
                    if hasAnyService {
                        let name = self.getHostname(for: result.ip) ?? "Mac at \(result.ip)"
                        
                        await MainActor.run {
                            if result.hasScreenSharing {
                                self.addOrUpdateDevice(name: name, ipAddress: result.ip, port: 5900, service: .screenSharing)
                            }
                            if result.hasFileSharing {
                                self.addOrUpdateDevice(name: name, ipAddress: result.ip, port: 445, service: .fileSharing)
                            }
                            if result.hasAFP {
                                self.addOrUpdateDevice(name: name, ipAddress: result.ip, port: 548, service: .afp)
                            }
                        }
                    }
                }
            }
        }
        
        await MainActor.run {
            isScanningSubnet = false
            scanProgress = 1.0
        }
    }
    
    /// Scan common VNC/screen sharing ports on a single IP
    func scanIPForAllServices(_ ipAddress: String) async {
        // Check VNC (screen sharing)
        if await scanIP(ipAddress, port: 5900) {
            let name = getHostname(for: ipAddress) ?? "Mac at \(ipAddress)"
            await MainActor.run {
                addOrUpdateDevice(name: name, ipAddress: ipAddress, port: 5900, service: .screenSharing)
            }
        }
        
        // Check SMB (file sharing)
        if await scanIP(ipAddress, port: 445) {
            let name = getHostname(for: ipAddress) ?? "Mac at \(ipAddress)"
            await MainActor.run {
                addOrUpdateDevice(name: name, ipAddress: ipAddress, port: 445, service: .fileSharing)
            }
        }
        
        // Check AFP
        if await scanIP(ipAddress, port: 548) {
            let name = getHostname(for: ipAddress) ?? "Mac at \(ipAddress)"
            await MainActor.run {
                addOrUpdateDevice(name: name, ipAddress: ipAddress, port: 548, service: .afp)
            }
        }
    }
    
    private func getHostname(for ipAddress: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ipAddress, nil, &hints, &result) == 0, let addrInfo = result else {
            return nil
        }
        defer { freeaddrinfo(result) }
        
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let error = getnameinfo(
            addrInfo.pointee.ai_addr,
            addrInfo.pointee.ai_addrlen,
            &hostname,
            socklen_t(hostname.count),
            nil,
            0,
            0
        )
        
        if error == 0 {
            let name = String(cString: hostname)
            // Return nil if it just returned the IP back
            if name != ipAddress && !name.isEmpty {
                // Clean up .local suffix for display
                return name.replacingOccurrences(of: ".local", with: "")
            }
        }
        return nil
    }
}
