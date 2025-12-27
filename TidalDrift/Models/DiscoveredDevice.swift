import Foundation

struct DiscoveredDevice: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var hostname: String
    var ipAddress: String
    var services: Set<ServiceType>
    var lastSeen: Date
    var isTrusted: Bool
    var savedCredentialRef: String?
    var port: Int
    
    // TidalDrift peer info (if running on remote machine)
    var isTidalDriftPeer: Bool
    var peerModelName: String?
    var peerModelIdentifier: String?
    var peerProcessorInfo: String?
    var peerMemoryGB: Int?
    var peerMacOSVersion: String?
    var peerUserName: String?
    var peerUptimeHours: Int?
    
    /// Stable identifier based on name + IP for credential storage
    var stableId: String {
        "\(name.lowercased().replacingOccurrences(of: " ", with: "-"))_\(ipAddress)"
    }
    
    init(id: UUID = UUID(),
         name: String,
         hostname: String,
         ipAddress: String,
         services: Set<ServiceType> = [],
         lastSeen: Date = Date(),
         isTrusted: Bool = false,
         savedCredentialRef: String? = nil,
         port: Int = 5900,
         isTidalDriftPeer: Bool = false,
         peerModelName: String? = nil,
         peerModelIdentifier: String? = nil,
         peerProcessorInfo: String? = nil,
         peerMemoryGB: Int? = nil,
         peerMacOSVersion: String? = nil,
         peerUserName: String? = nil,
         peerUptimeHours: Int? = nil) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.ipAddress = ipAddress
        self.services = services
        self.lastSeen = lastSeen
        self.isTrusted = isTrusted
        self.savedCredentialRef = savedCredentialRef
        self.port = port
        self.isTidalDriftPeer = isTidalDriftPeer
        self.peerModelName = peerModelName
        self.peerModelIdentifier = peerModelIdentifier
        self.peerProcessorInfo = peerProcessorInfo
        self.peerMemoryGB = peerMemoryGB
        self.peerMacOSVersion = peerMacOSVersion
        self.peerUserName = peerUserName
        self.peerUptimeHours = peerUptimeHours
    }
    
    enum ServiceType: String, Codable, CaseIterable {
        case screenSharing = "_rfb._tcp."
        case fileSharing = "_smb._tcp."
        case afp = "_afpovertcp._tcp."
        case ssh = "_ssh._tcp."
        case tidalDrift = "_tidaldrift._tcp."
        case tidalDrop = "_tidaldrop._tcp."
        
        var displayName: String {
            switch self {
            case .screenSharing: return "Screen Sharing"
            case .fileSharing: return "File Sharing"
            case .afp: return "AFP"
            case .ssh: return "SSH"
            case .tidalDrift: return "TidalDrift"
            case .tidalDrop: return "TidalDrop"
            }
        }
        
        var icon: String {
            switch self {
            case .screenSharing: return "rectangle.on.rectangle"
            case .fileSharing: return "folder"
            case .afp: return "externaldrive.connected.to.line.below"
            case .ssh: return "terminal"
            case .tidalDrift: return "wave.3.right"
            case .tidalDrop: return "arrow.down.doc"
            }
        }
    }
    
    var isOnline: Bool {
        Date().timeIntervalSince(lastSeen) < 60
    }
    
    /// Check if this device is the current Mac (by IP address)
    var isCurrentDevice: Bool {
        guard let localIP = NetworkUtils.getLocalIPAddress() else { return false }
        return ipAddress == localIP
    }
    
    /// Device hasn't been seen in 24+ hours
    var isStale: Bool {
        Date().timeIntervalSince(lastSeen) > 24 * 60 * 60
    }
    
    /// Device was seen in this session (within the last 5 minutes)
    var isRecentlyConfirmed: Bool {
        Date().timeIntervalSince(lastSeen) < 5 * 60
    }
    
    var statusText: String {
        if isOnline {
            return "Online"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Last seen \(formatter.localizedString(for: lastSeen, relativeTo: Date()))"
        }
    }
    
    var lastSeenText: String {
        let interval = Date().timeIntervalSince(lastSeen)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 60 * 60 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 24 * 60 * 60 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    var deviceIcon: String {
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("imac") {
            return "desktopcomputer"
        } else if lowercaseName.contains("macbook") {
            return "laptopcomputer"
        } else if lowercaseName.contains("mac mini") {
            return "macmini"
        } else if lowercaseName.contains("mac pro") {
            return "macpro.gen3"
        } else if lowercaseName.contains("mac studio") {
            return "macstudio"
        }
        return "desktopcomputer"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

extension DiscoveredDevice {
    static var preview: DiscoveredDevice {
        DiscoveredDevice(
            name: "iMac Office",
            hostname: "imac-office.local",
            ipAddress: "192.168.1.101",
            services: [.screenSharing, .fileSharing],
            lastSeen: Date(),
            isTrusted: true
        )
    }
    
    static var previewList: [DiscoveredDevice] {
        [
            DiscoveredDevice(name: "iMac Office", hostname: "imac.local", ipAddress: "192.168.1.101", services: [.screenSharing, .fileSharing]),
            DiscoveredDevice(name: "Mac Mini Server", hostname: "mini.local", ipAddress: "192.168.1.102", services: [.screenSharing, .fileSharing]),
            DiscoveredDevice(name: "MacBook Air", hostname: "air.local", ipAddress: "192.168.1.103", services: [.screenSharing], lastSeen: Date().addingTimeInterval(-120)),
            DiscoveredDevice(name: "Mac Pro Studio", hostname: "pro.local", ipAddress: "192.168.1.104", services: [.screenSharing, .fileSharing, .afp])
        ]
    }
}
