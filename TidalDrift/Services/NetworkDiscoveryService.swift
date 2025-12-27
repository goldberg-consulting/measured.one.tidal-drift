import Foundation
import Network
import Combine

class NetworkDiscoveryService: ObservableObject {
    static let shared = NetworkDiscoveryService()
    
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var lastScanDate: Date?
    
    private var browsers: [NWBrowser] = []
    private var udpListener: NWListener?
    private var deviceCache: [String: DiscoveredDevice] = [:]
    private let deviceCacheLock = NSLock()  // Thread-safe access to deviceCache
    private var scanTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.tidaldrift.discovery", qos: .userInitiated)
    
    // Store active connections to prevent premature deallocation
    private var activeConnections: [UUID: NWConnection] = [:]
    private let connectionsLock = NSLock()
    
    // Persistence keys
    private let savedDevicesKey = "com.tidaldrift.savedDevices"
    private let lastScanDateKey = "com.tidaldrift.lastScanDate"
    
    // Extended service types for better discovery
    private let serviceTypes: [String] = [
        "_rfb._tcp",           // VNC/Screen Sharing
        "_smb._tcp",           // Windows/Samba File Sharing
        "_afpovertcp._tcp",    // AFP (Apple Filing Protocol)
        "_ssh._tcp",           // SSH
        "_tidaldrift._tcp",    // TidalDrift Discovery
        "_tidaldrop._tcp"      // TidalDrop Transfer
    ]
    
    private init() {
        loadSavedDevices()
        
        // Defer network setup to avoid blocking on init
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.setupNetworkMonitor()
            self?.startUDPListener()
        }
    }
    
    func startUDPListener() {
        let params = NWParameters.udp
        
        do {
            udpListener = try NWListener(using: params, on: 5903)
            udpListener?.stateUpdateHandler = { state in
                if case .ready = state { print("🌊 UDP Listener: Ready on port 5903") }
            }
            
            udpListener?.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.queue ?? .main)
                self?.receiveMessages(on: connection)
            }
            udpListener?.start(queue: queue)
        } catch {
            print("❌ UDP Listener: Initialization failed: \(error)")
        }
    }
    
    private func receiveMessages(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            if let data = data, !data.isEmpty {
                if let peerInfo = try? JSONDecoder().decode(TidalDriftPeerService.PeerInfo.self, from: data) {
                    print("🌊 UDP Heartbeat: Received from \(peerInfo.hostname) (\(peerInfo.ipAddress))")
                    self?.markAsTidalDriftPeer(hostname: peerInfo.hostname, peerInfo: peerInfo)
                }
            }
            
            if error == nil {
                self?.receiveMessages(on: connection)
            } else {
                connection.cancel()
            }
        }
    }
    
    // MARK: - Persistence
    
    /// Load previously discovered devices from storage
    private func loadSavedDevices() {
        if let data = UserDefaults.standard.data(forKey: savedDevicesKey) {
            do {
                let devices = try JSONDecoder().decode([DiscoveredDevice].self, from: data)
                
                // Load into cache with IP as key
                deviceCacheLock.lock()
                for device in devices {
                    deviceCache[device.ipAddress] = device
                }
                deviceCacheLock.unlock()
                
                // Update published devices
                discoveredDevices = devices.sorted { $0.name < $1.name }
                
                // Load last scan date
                if let scanDate = UserDefaults.standard.object(forKey: lastScanDateKey) as? Date {
                    lastScanDate = scanDate
                }
                
                #if DEBUG
                print("✅ Loaded \(devices.count) saved devices")
                #endif
            } catch {
                #if DEBUG
                print("❌ Failed to load saved devices: \(error)")
                #endif
            }
        }
    }
    
    /// Save current devices to storage
    private func saveDevices() {
        deviceCacheLock.lock()
        let devices = Array(deviceCache.values)
        deviceCacheLock.unlock()
        
        do {
            let data = try JSONEncoder().encode(devices)
            UserDefaults.standard.set(data, forKey: savedDevicesKey)
            
            if let scanDate = lastScanDate {
                UserDefaults.standard.set(scanDate, forKey: lastScanDateKey)
            }
            
            #if DEBUG
            print("💾 Saved \(devices.count) devices")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save devices: \(error)")
            #endif
        }
    }
    
    /// Clear all saved devices
    func clearSavedDevices() {
        deviceCacheLock.lock()
        deviceCache.removeAll()
        deviceCacheLock.unlock()
        discoveredDevices.removeAll()
        lastScanDate = nil
        UserDefaults.standard.removeObject(forKey: savedDevicesKey)
        UserDefaults.standard.removeObject(forKey: lastScanDateKey)
    }
    
    /// Check if a device is stale (not seen recently)
    func isDeviceStale(_ device: DiscoveredDevice) -> Bool {
        let staleThreshold: TimeInterval = 24 * 60 * 60 // 24 hours
        return Date().timeIntervalSince(device.lastSeen) > staleThreshold
    }
    
    /// Remove a specific device by IP
    func removeDevice(ipAddress: String) {
        deviceCacheLock.lock()
        deviceCache.removeValue(forKey: ipAddress)
        deviceCacheLock.unlock()
        updatePublishedDevices()
        saveDevices()
    }
    
    /// Remove all stale devices
    func removeStaleDevices() {
        deviceCacheLock.lock()
        let staleIPs = deviceCache.filter { isDeviceStale($0.value) }.map { $0.key }
        for ip in staleIPs {
            deviceCache.removeValue(forKey: ip)
        }
        deviceCacheLock.unlock()
        updatePublishedDevices()
        saveDevices()
    }
    
    private func setupNetworkMonitor() {
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                // Network became available - refresh discovery
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.refreshScan()
                }
            }
        }
        pathMonitor?.start(queue: queue)
    }
    
    func startBrowsing() {
        guard browsers.isEmpty else { return }
        
        for serviceType in serviceTypes {
            // Use parameters that enable better discovery
            let params = NWParameters()
            params.includePeerToPeer = true
            
            // Try both local. domain and nil for broader discovery
            for domain in ["local.", ""] {
                let actualDomain = domain.isEmpty ? nil : domain
                let browser = NWBrowser(for: .bonjour(type: serviceType, domain: actualDomain), using: params)
                
                browser.stateUpdateHandler = { [weak self] state in
                    self?.handleBrowserState(state, for: serviceType)
                }
                
                browser.browseResultsChangedHandler = { [weak self] results, changes in
                    self?.handleBrowseResults(results, changes: changes, serviceType: serviceType)
                }
                
                browser.start(queue: queue)
                browsers.append(browser)
            }
        }
        
        lastScanDate = Date()
        
        // Also do an initial ARP scan to find devices that might not advertise services
        Task {
            await scanARPTable()
        }
    }
    
    /// Scan ARP table for additional devices that might not advertise Bonjour services
    private func scanARPTable() async {
        let result = ShellExecutor.execute("arp -a")
        let lines = result.output.split(separator: "\n")
        
        for line in lines {
            let lineStr = String(line)
            
            // Parse: "? (192.168.1.100) at aa:bb:cc:dd:ee:ff on en0"
            if let ipRange = lineStr.range(of: "\\([0-9.]+\\)", options: .regularExpression) {
                var ip = String(lineStr[ipRange])
                ip = ip.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                
                // Skip broadcast and self
                if ip.hasSuffix(".255") || ip.hasSuffix(".1") { continue }
                
                // Check if we already know this device
                let knownIPs = await MainActor.run { discoveredDevices.map { $0.ipAddress } }
                if knownIPs.contains(ip) { continue }
                
                // Try to discover services on this IP
                await scanIPForAllServices(ip)
            }
        }
    }
    
    func stopBrowsing() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
    }
    
    func refreshScan() {
        stopBrowsing()
        
        deviceCacheLock.lock()
        // Preserve TidalDrift peer info before clearing cache
        let tidalDriftPeers = deviceCache.filter { $0.value.isTidalDriftPeer }
        
        deviceCache.removeAll()
        
        // Restore TidalDrift peer entries (they'll be updated when rediscovered)
        for (key, device) in tidalDriftPeers {
            deviceCache[key] = device
        }
        deviceCacheLock.unlock()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startBrowsing()
            
            // Also trigger TidalDrift peer re-discovery
            if AppState.shared.settings.peerDiscoveryEnabled {
                // Restart peer discovery to re-sync
                TidalDriftPeerService.shared.stopDiscovery()
                TidalDriftPeerService.shared.startDiscovery()
            }
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
        // Method 1: Use NWConnection to resolve
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let connection = NWConnection(to: endpoint, using: params)
        let connectionId = UUID()
        
        // Store connection to prevent premature deallocation
        connectionsLock.lock()
        activeConnections[connectionId] = connection
        connectionsLock.unlock()
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint {
                    self?.extractIPAddress(from: innerEndpoint, name: name, serviceType: serviceType)
                }
                self?.cleanupConnection(id: connectionId)
            case .failed:
                // Try fallback resolution via dns-sd
                self?.resolveServiceViaDNSSD(name: name, type: type, domain: domain, serviceType: serviceType)
                self?.cleanupConnection(id: connectionId)
            case .cancelled:
                // Remove from storage once fully cancelled
                self?.connectionsLock.lock()
                self?.activeConnections.removeValue(forKey: connectionId)
                self?.connectionsLock.unlock()
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.connectionsLock.lock()
            let conn = self?.activeConnections[connectionId]
            self?.connectionsLock.unlock()
            
            if let conn = conn, conn.state != .ready && conn.state != .cancelled {
                // Timeout - try fallback
                self?.resolveServiceViaDNSSD(name: name, type: type, domain: domain, serviceType: serviceType)
                self?.cleanupConnection(id: connectionId)
            }
        }
    }
    
    private func cleanupConnection(id: UUID) {
        connectionsLock.lock()
        if let connection = activeConnections[id] {
            connection.cancel()
            // Don't remove here - wait for .cancelled state
        }
        connectionsLock.unlock()
    }
    
    /// Fallback resolution using dns-sd command
    private func resolveServiceViaDNSSD(name: String, type: String, domain: String, serviceType: String) {
        // Sanitize inputs to prevent command injection
        let escapedName = name.replacingOccurrences(of: "'", with: "'\\''")
        // Service type should only contain alphanumeric, underscore, hyphen, period
        let safeType = type.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
        let safeDomain = domain.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
        
        guard !safeType.isEmpty else { return }
        
        let result = ShellExecutor.execute("timeout 2 dns-sd -L '\(escapedName)' '\(safeType)' '\(safeDomain)' 2>/dev/null | head -5")
        
        // Parse output for host info
        // Example: "hostname.local.:5900"
        let lines = result.output.split(separator: "\n")
        for line in lines {
            let lineStr = String(line)
            if lineStr.contains("can be reached at") {
                // Extract hostname
                if let hostRange = lineStr.range(of: "[a-zA-Z0-9-]+\\.local\\.", options: .regularExpression) {
                    let hostname = String(lineStr[hostRange])
                    // Resolve hostname to IP
                    resolveHostname(hostname, name: name, serviceType: serviceType)
                }
            }
        }
    }
    
    /// Resolve a hostname to IP address
    private func resolveHostname(_ hostname: String, name: String, serviceType: String) {
        let cleanHostname = hostname.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        
        var hints = addrinfo()
        hints.ai_family = AF_INET // IPv4
        hints.ai_socktype = SOCK_STREAM
        
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(cleanHostname, nil, &hints, &result)
        
        defer { freeaddrinfo(result) }
        
        guard status == 0, let addrInfo = result else { return }
        
        var addr = addrInfo.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr.sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
        let ipAddress = String(cString: ipBuffer)
        
        let service = mapServiceType(serviceType)
        DispatchQueue.main.async { [weak self] in
            self?.addOrUpdateDevice(name: name, ipAddress: ipAddress, port: 5900, service: service)
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
        case "_ssh._tcp", "_ssh._tcp.":
            return .ssh
        case "_tidaldrift._tcp", "_tidaldrift._tcp.":
            return .tidalDrift
        case "_tidaldrop._tcp", "_tidaldrop._tcp.":
            return .tidalDrop
        default:
            return nil
        }
    }
    
    private func addOrUpdateDevice(name: String, ipAddress: String, port: Int, service: DiscoveredDevice.ServiceType?) {
        // Use IP as primary key to avoid duplicates
        let cacheKey = ipAddress
        
        deviceCacheLock.lock()
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
        deviceCacheLock.unlock()
        
        updatePublishedDevices()
    }
    
    private func handleDeviceRemoved(_ result: NWBrowser.Result) {
        switch result.endpoint {
        case .service(let name, _, _, _):
            // Find and remove device by name match
            deviceCacheLock.lock()
            deviceCache = deviceCache.filter { !$0.value.name.lowercased().contains(name.lowercased()) }
            deviceCacheLock.unlock()
            updatePublishedDevices()
        default:
            break
        }
    }
    
    private func updatePublishedDevices() {
        deviceCacheLock.lock()
        let devices = Array(deviceCache.values).sorted { $0.name < $1.name }
        deviceCacheLock.unlock()
        
        DispatchQueue.main.async {
            self.discoveredDevices = devices
            // Auto-save when devices change
            self.saveDevices()
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
        deviceCacheLock.lock()
        deviceCache[cacheKey] = device
        deviceCacheLock.unlock()
        updatePublishedDevices()
    }
    
    /// Mark a device as a TidalDrift peer with enhanced info from TidalDriftPeerService
    func markAsTidalDriftPeer(hostname: String, peerInfo: TidalDriftPeerService.PeerInfo) {
        print("🌊 TidalDrift PEER: Attempting to mark '\(hostname)' at \(peerInfo.ipAddress) as peer")
        
        DispatchQueue.main.async {
            // Normalize input hostname
            let inputHostname = hostname.lowercased().replacingOccurrences(of: ".local", with: "")
            let inputIP = peerInfo.ipAddress
            
            self.deviceCacheLock.lock()
            
            // Check cache directly first
            var matchedIP: String?
            
            // Match by IP
            if !inputIP.isEmpty && self.deviceCache[inputIP] != nil {
                matchedIP = inputIP
            } else {
                // Match by hostname or name in cache
                for (ip, device) in self.deviceCache {
                    let dName = device.name.lowercased()
                    let dHost = device.hostname.lowercased().replacingOccurrences(of: ".local", with: "")
                    
                    if dName == inputHostname || dHost == inputHostname || 
                       dName.contains(inputHostname) || inputHostname.contains(dName) {
                        matchedIP = ip
                        break
                    }
                }
            }
            
            if let ip = matchedIP, var device = self.deviceCache[ip] {
                device.isTidalDriftPeer = true
                device.services.insert(.ssh)
                device.services.insert(.tidalDrift)
                device.peerModelName = peerInfo.modelName
                device.peerModelIdentifier = peerInfo.modelIdentifier
                device.peerProcessorInfo = peerInfo.processorInfo
                device.peerMemoryGB = peerInfo.memoryGB
                device.peerMacOSVersion = peerInfo.macOSVersion
                device.peerUserName = peerInfo.userName
                device.peerUptimeHours = peerInfo.uptimeHours
                
                // Keep the most accurate IP
                if !inputIP.isEmpty && inputIP != "Unknown" {
                    device.ipAddress = inputIP
                }
                
                self.deviceCache[device.ipAddress] = device
                self.deviceCacheLock.unlock()
                print("🌊 TidalDrift PEER: ✅ Updated cache entry '\(device.name)' as peer")
            } else {
                // Create a new device entry for this TidalDrift peer
                let displayName = hostname.replacingOccurrences(of: ".local", with: "")
                let newDevice = DiscoveredDevice(
                    name: displayName,
                    hostname: hostname.hasSuffix(".local") ? hostname : "\(hostname).local",
                    ipAddress: peerInfo.ipAddress.isEmpty || peerInfo.ipAddress == "Unknown" ? "Resolving..." : peerInfo.ipAddress,
                    services: [.screenSharing, .ssh, .tidalDrift],
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
                self.deviceCache[newDevice.ipAddress] = newDevice
                self.deviceCacheLock.unlock()
                print("🌊 TidalDrift PEER: ✅ Created new device entry for peer '\(displayName)'")
            }
            self.updatePublishedDevices()
        }
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
            let connectionId = UUID()
            
            // Store connection to prevent premature deallocation
            self.connectionsLock.lock()
            self.activeConnections[connectionId] = connection
            self.connectionsLock.unlock()
            
            let didResume = AtomicFlag()
            
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard !didResume.value else { return }
                    didResume.value = true
                    self?.cleanupConnection(id: connectionId)
                    continuation.resume(returning: true)
                case .failed:
                    guard !didResume.value else { return }
                    didResume.value = true
                    self?.cleanupConnection(id: connectionId)
                    continuation.resume(returning: false)
                case .cancelled:
                    // Clean up storage once fully cancelled
                    self?.connectionsLock.lock()
                    self?.activeConnections.removeValue(forKey: connectionId)
                    self?.connectionsLock.unlock()
                    
                    // Resume if not already done (timeout case)
                    guard !didResume.value else { return }
                    didResume.value = true
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            
            connection.start(queue: self.queue)
            
            // 2 second timeout per IP
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard !didResume.value else { return }
                didResume.value = true
                self?.cleanupConnection(id: connectionId)
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Scan a range of IPs (e.g., 192.168.1.1 to 192.168.1.254)
    func scanSubnet(baseIP: String, startHost: Int = 1, endHost: Int = 254) async {
        await MainActor.run {
            isScanningSubnet = true
            scanProgress = 0.01 // Show immediate progress
        }
        
        // Parse base IP (e.g., "192.168.1" from "192.168.1.100")
        let components = baseIP.split(separator: ".")
        guard components.count >= 3 else {
            await MainActor.run { isScanningSubnet = false }
            return
        }
        let subnet = components.prefix(3).joined(separator: ".")
        
        // Get the current host number to prioritize nearby IPs
        let currentHost = Int(components.last ?? "1") ?? 1
        
        // Reorder to scan nearby IPs first (more likely to find devices quickly)
        var hostsToScan = Array(startHost...endHost)
        hostsToScan.sort { abs($0 - currentHost) < abs($1 - currentHost) }
        
        let totalIPs = hostsToScan.count
        
        // Track which IPs responded during this scan
        final class ScanTracker: @unchecked Sendable {
            var scannedCount: Int = 0
            var respondedIPs: Set<String> = []
            let lock = NSLock()
            
            func addRespondedIP(_ ip: String) {
                lock.lock()
                respondedIPs.insert(ip)
                lock.unlock()
            }
            
            func incrementScanned() {
                lock.lock()
                scannedCount += 1
                lock.unlock()
            }
            
            func getScannedCount() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return scannedCount
            }
            
            func getRespondedIPs() -> Set<String> {
                lock.lock()
                defer { lock.unlock() }
                return respondedIPs
            }
        }
        let tracker = ScanTracker()
        
        // Structure to hold scan results for an IP
        struct ScanResult: Sendable {
            let ip: String
            let hasScreenSharing: Bool
            let hasFileSharing: Bool
            let hasAFP: Bool
            let hasSSH: Bool
        }
        
        // Scan in batches, processing nearby IPs first for faster initial results
        let batchSize = 25 // Larger batches for faster scanning
        for batchStart in stride(from: 0, to: hostsToScan.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, hostsToScan.count)
            let batch = Array(hostsToScan[batchStart..<batchEnd])
            
            await withTaskGroup(of: ScanResult.self) { group in
                for hostNum in batch {
                    let ip = "\(subnet).\(hostNum)"
                    group.addTask {
                        // Check all services in parallel for each IP
                        async let screenShare = self.scanIP(ip, port: 5900)
                        async let fileShare = self.scanIP(ip, port: 445)
                        async let afp = self.scanIP(ip, port: 548)
                        
                        // Only scan for SSH if enabled in settings
                        let shouldScanSSH = await MainActor.run { AppState.shared.settings.sshDiscoveryEnabled }
                        async let ssh = shouldScanSSH ? self.scanIP(ip, port: 22) : false
                        
                        return ScanResult(
                            ip: ip,
                            hasScreenSharing: await screenShare,
                            hasFileSharing: await fileShare,
                            hasAFP: await afp,
                            hasSSH: await ssh
                        )
                    }
                }
                
                for await result in group {
                    tracker.incrementScanned()
                    await MainActor.run {
                        scanProgress = Double(tracker.getScannedCount()) / Double(totalIPs)
                    }
                    
                    let hasAnyService = result.hasScreenSharing || result.hasFileSharing || result.hasAFP || result.hasSSH
                    
                    if hasAnyService {
                        tracker.addRespondedIP(result.ip)
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
                            if result.hasSSH {
                                self.addOrUpdateDevice(name: name, ipAddress: result.ip, port: 22, service: .ssh)
                            }
                        }
                    }
                }
            }
        }
        
        // After scan completes, remove devices on this subnet that didn't respond
        // (but keep TidalDrift peers and manually added devices)
        let respondedIPs = tracker.getRespondedIPs()
        await MainActor.run {
            removeUnresponsiveDevices(onSubnet: subnet, respondedIPs: respondedIPs)
            isScanningSubnet = false
            scanProgress = 1.0
        }
    }
    
    /// Remove devices on the given subnet that didn't respond during scan
    /// Preserves TidalDrift peers (they're discovered via Bonjour, not port scan)
    private func removeUnresponsiveDevices(onSubnet subnet: String, respondedIPs: Set<String>) {
        var devicesToRemove: [String] = []
        
        deviceCacheLock.lock()
        for (ip, device) in deviceCache {
            // Skip if not on the scanned subnet
            guard ip.hasPrefix(subnet + ".") else { continue }
            
            // Skip TidalDrift peers - they may not have open ports but are valid
            if device.isTidalDriftPeer { continue }
            
            // Skip if this IP responded during the scan
            if respondedIPs.contains(ip) { continue }
            
            // This device is on our subnet but didn't respond - mark for removal
            devicesToRemove.append(ip)
        }
        
        // Remove unresponsive devices
        for ip in devicesToRemove {
            deviceCache.removeValue(forKey: ip)
            #if DEBUG
            print("🧹 Removed unresponsive device: \(ip)")
            #endif
        }
        deviceCacheLock.unlock()
        
        if !devicesToRemove.isEmpty {
            updatePublishedDevices()
            #if DEBUG
            print("🧹 Cleaned up \(devicesToRemove.count) devices that didn't respond during subnet scan")
            #endif
        }
    }
    
    /// Scan common ports on a single IP
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

        // Check SSH (only if enabled)
        if AppState.shared.settings.sshDiscoveryEnabled {
            if await scanIP(ipAddress, port: 22) {
                let name = getHostname(for: ipAddress) ?? "Mac at \(ipAddress)"
                await MainActor.run {
                    addOrUpdateDevice(name: name, ipAddress: ipAddress, port: 22, service: .ssh)
                }
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
