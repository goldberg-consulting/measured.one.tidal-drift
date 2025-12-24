import Foundation

struct ConnectionRecord: Identifiable, Codable {
    let id: UUID
    let deviceId: UUID
    let deviceName: String
    let deviceIP: String
    let timestamp: Date
    let connectionType: ConnectionType
    let wasSuccessful: Bool
    let duration: TimeInterval?
    
    init(id: UUID = UUID(),
         deviceId: UUID,
         deviceName: String,
         deviceIP: String,
         timestamp: Date = Date(),
         connectionType: ConnectionType,
         wasSuccessful: Bool,
         duration: TimeInterval? = nil) {
        self.id = id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceIP = deviceIP
        self.timestamp = timestamp
        self.connectionType = connectionType
        self.wasSuccessful = wasSuccessful
        self.duration = duration
    }
    
    enum ConnectionType: String, Codable {
        case screenShare
        case fileShare
        
        var displayName: String {
            switch self {
            case .screenShare: return "Screen Share"
            case .fileShare: return "File Share"
            }
        }
        
        var icon: String {
            switch self {
            case .screenShare: return "rectangle.on.rectangle"
            case .fileShare: return "folder"
            }
        }
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

extension ConnectionRecord {
    static var preview: ConnectionRecord {
        ConnectionRecord(
            deviceId: UUID(),
            deviceName: "iMac Office",
            deviceIP: "192.168.1.101",
            connectionType: .screenShare,
            wasSuccessful: true,
            duration: 3600
        )
    }
    
    static var previewList: [ConnectionRecord] {
        [
            ConnectionRecord(deviceId: UUID(), deviceName: "iMac Office", deviceIP: "192.168.1.101", connectionType: .screenShare, wasSuccessful: true),
            ConnectionRecord(deviceId: UUID(), deviceName: "Mac Mini", deviceIP: "192.168.1.102", timestamp: Date().addingTimeInterval(-3600), connectionType: .fileShare, wasSuccessful: true),
            ConnectionRecord(deviceId: UUID(), deviceName: "MacBook Air", deviceIP: "192.168.1.103", timestamp: Date().addingTimeInterval(-86400), connectionType: .screenShare, wasSuccessful: false)
        ]
    }
}
