import Foundation
import Network
import SwiftUI
import UserNotifications

/// Handles peer-to-peer file transfers over the TidalDrop protocol
class TidalDropServiceNew: ObservableObject {
    static let shared = TidalDropServiceNew()
    
    @Published var activeTransfers: [UUID: DropTransfer] = [:]
    
    enum TidalDropTransferStatus: Equatable {
        case pending
        case transferring
        case completed
        case failed(String)
        
        var isCurrentlyTransferring: Bool {
            if case .transferring = self { return true }
            return false
        }
    }
    
    struct DropTransfer: Identifiable {
        let id: UUID
        let fileName: String
        let fileSize: Int64
        var progress: Double
        let isIncoming: Bool
        var status: TidalDropTransferStatus
        let remoteEndpoint: String
    }
    
    private init() {}
    
    func sendFile(at url: URL, to ipAddress: String) {}
    func startListening() {}
}
