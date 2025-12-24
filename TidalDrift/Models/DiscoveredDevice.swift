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
    
    init(id: UUID = UUID(),
         name: String,
         hostname: String,
         ipAddress: String,
         services: Set<ServiceType> = [],
         lastSeen: Date = Date(),
         isTrusted: Bool = false,
         savedCredentialRef: String? = nil,
         port: Int = 5900) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.ipAddress = ipAddress
        self.services = services
        self.lastSeen = lastSeen
        self.isTrusted = isTrusted
        self.savedCredentialRef = savedCredentialRef
        self.port = port
    }
    
    enum ServiceType: String, Codable, CaseIterable {
        case screenSharing = "_rfb._tcp."
        case fileSharing = "_smb._tcp."
        case afp = "_afpovertcp._tcp."
        
        var displayName: String {
            switch self {
            case .screenSharing: return "Screen Sharing"
            case .fileSharing: return "File Sharing"
            case .afp: return "AFP"
            }
        }
        
        var icon: String {
            switch self {
            case .screenSharing: return "rectangle.on.rectangle"
            case .fileSharing: return "folder"
            case .afp: return "externaldrive.connected.to.line.below"
            }
        }
    }
    
    var isOnline: Bool {
        Date().timeIntervalSince(lastSeen) < 60
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
