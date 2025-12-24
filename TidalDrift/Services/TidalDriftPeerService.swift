import Foundation
import Network
import IOKit

/// Service to advertise this TidalDrift instance and discover peers
class TidalDriftPeerService: ObservableObject {
    static let shared = TidalDriftPeerService()
    
    @Published var discoveredPeers: [String: PeerInfo] = [:] // keyed by hostname/IP
    @Published var isAdvertising = false
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let serviceType = "_tidaldrift._tcp"
    private let port: UInt16 = 51235
    
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
    
    private init() {
        // Gather local system info
        localInfo = PeerInfo(
            hostname: Host.current().localizedName ?? "Unknown",
            ipAddress: NetworkUtils.getLocalIPAddress() ?? "Unknown",
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
    }
    
    // MARK: - Advertising
    
    func startAdvertising() {
        guard listener == nil else { return }
        
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            
            // Create TXT record with our info
            let txtRecord = createTXTRecord()
            listener?.service = NWListener.Service(
                name: localInfo.hostname,
                type: serviceType,
                txtRecord: txtRecord
            )
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isAdvertising = true
                        print("🌊 TidalDrift: Advertising on network")
                    case .failed(let error):
                        print("🌊 TidalDrift: Advertising failed - \(error)")
                        self?.isAdvertising = false
                    case .cancelled:
                        self?.isAdvertising = false
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            listener?.start(queue: .global(qos: .userInitiated))
            
        } catch {
            print("🌊 TidalDrift: Failed to start advertising - \(error)")
        }
    }
    
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
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
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Connection established - could exchange more data here
                break
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }
    
    // MARK: - Discovery
    
    func startDiscovery() {
        guard browser == nil else { return }
        
        let params = NWParameters()
        params.includePeerToPeer = true
        
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: params)
        
        browser?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("🌊 TidalDrift: Browsing for peers")
            case .failed(let error):
                print("🌊 TidalDrift: Browse failed - \(error)")
            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleBrowseResults(results)
        }
        
        browser?.start(queue: .global(qos: .userInitiated))
    }
    
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        print("🌊 TidalDrift: Found \(results.count) peer results")
        
        for result in results {
            switch result.endpoint {
            case .service(let name, let type, let domain, let interface):
                print("🌊 TidalDrift: Found service: \(name) type=\(type) domain=\(domain)")
                
                // Skip ourselves
                if name == localInfo.hostname {
                    print("🌊 TidalDrift: Skipping self: \(name)")
                    continue
                }
                
                // Extract TXT record data
                if case .bonjour(let txtRecord) = result.metadata {
                    var peer = parseTXTRecord(txtRecord, name: name)
                    
                    // Resolve the IP address
                    resolveEndpoint(result.endpoint) { [weak self] ipAddress in
                        if let ip = ipAddress {
                            // Create updated peer with IP
                            let updatedPeer = PeerInfo(
                                hostname: peer.hostname,
                                ipAddress: ip,
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
                                self?.discoveredPeers[name] = updatedPeer
                                self?.notifyNetworkDiscovery(peer: updatedPeer)
                                print("🌊 TidalDrift: Added peer \(name) at IP \(ip)")
                            }
                        } else {
                            DispatchQueue.main.async {
                                self?.discoveredPeers[name] = peer
                                self?.notifyNetworkDiscovery(peer: peer)
                                print("🌊 TidalDrift: Added peer \(name) (no IP resolved)")
                            }
                        }
                    }
                } else {
                    print("🌊 TidalDrift: No TXT record for \(name)")
                }
                
            default:
                break
            }
        }
    }
    
    private func resolveEndpoint(_ endpoint: NWEndpoint, completion: @escaping (String?) -> Void) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
                    if case .ipv4(let ipv4) = host {
                        let ip = ipv4.debugDescription
                        connection.cancel()
                        completion(ip)
                        return
                    } else if case .ipv6(let ipv6) = host {
                        let ip = ipv6.debugDescription
                        connection.cancel()
                        completion(ip)
                        return
                    }
                }
                connection.cancel()
                completion(nil)
            case .failed, .cancelled:
                completion(nil)
            default:
                break
            }
        }
        
        connection.start(queue: .global(qos: .userInitiated))
        
        // Timeout after 2 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if connection.state != .ready && connection.state != .cancelled {
                connection.cancel()
                completion(nil)
            }
        }
    }
    
    private func parseTXTRecord(_ record: NWTXTRecord, name: String) -> PeerInfo {
        return PeerInfo(
            hostname: name,
            ipAddress: "", // Will be resolved separately
            modelName: record["model"] ?? "Unknown",
            modelIdentifier: record["modelId"] ?? "",
            processorInfo: record["cpu"] ?? "",
            memoryGB: Int(record["mem"] ?? "0") ?? 0,
            macOSVersion: record["os"] ?? "",
            userName: record["user"] ?? "",
            uptimeHours: Int(record["uptime"] ?? "0") ?? 0,
            tidalDriftVersion: record["version"] ?? "",
            screenSharingEnabled: record["screen"] == "1",
            fileSharingEnabled: record["file"] == "1"
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
    func markAsTidalDriftPeer(hostname: String, peerInfo: TidalDriftPeerService.PeerInfo) {
        DispatchQueue.main.async {
            // Try to find matching device by hostname, name, or IP address
            let normalizedHostname = hostname.lowercased().replacingOccurrences(of: ".local", with: "")
            
            if let index = self.discoveredDevices.firstIndex(where: { device in
                let deviceName = device.name.lowercased()
                let deviceHostname = device.hostname.lowercased().replacingOccurrences(of: ".local", with: "")
                let deviceIP = device.ipAddress
                
                return deviceName == normalizedHostname ||
                       deviceHostname == normalizedHostname ||
                       deviceName.contains(normalizedHostname) ||
                       normalizedHostname.contains(deviceName) ||
                       (!peerInfo.ipAddress.isEmpty && deviceIP == peerInfo.ipAddress)
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
                print("🌊 Marked \(device.name) as TidalDrift peer (matched from \(hostname))")
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
                print("🌊 Added new TidalDrift peer: \(displayName)")
            }
        }
    }
}

