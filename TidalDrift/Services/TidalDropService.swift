import Foundation
import Network
import SwiftUI
import UserNotifications

/// Protocol-agnostic transfer status
enum TidalDropStatus: Equatable {
    case pending
    case transferring
    case completed
    case failed(String)
    
    var isTransferring: Bool {
        if case .transferring = self { return true }
        return false
    }
}

/// Handles peer-to-peer file transfers over the TidalDrop protocol
class TidalDropService: ObservableObject {
    static let shared = TidalDropService()
    
    @Published var activeTransfers: [UUID: DropTransfer] = [:]
    
    struct DropTransfer: Identifiable {
        let id: UUID
        let fileName: String
        let fileSize: Int64
        var progress: Double
        let isIncoming: Bool
        var status: TidalDropStatus
        let remoteEndpoint: String
    }
    
    struct FileMetadata: Codable {
        let fileName: String
        let fileSize: Int64
    }
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.tidaldrift.drop", qos: .userInitiated)
    
    private init() {
        startListening()
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func startListening() {
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: 5902)
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("🌊 TidalDrop: Listener ready on port 5902")
                case .failed(let error):
                    print("❌ TidalDrop: Listener failed: \(error)")
                case .cancelled:
                    print("🌊 TidalDrop: Listener cancelled")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                print("🌊 TidalDrop: Incoming connection from \(connection.endpoint)")
                self?.handleIncomingConnection(connection)
            }
            
            listener?.start(queue: queue)
        } catch {
            print("❌ TidalDrop: Failed to create listener: \(error)")
        }
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        
        // 1. Receive metadata size (4 bytes)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            if let error = error {
                print("❌ TidalDrop: Error receiving header size: \(error)")
                return
            }
            guard let self = self, let d = data else {
                print("❌ TidalDrop: No data received for header size")
                return
            }
            
            let metadataSize = Int(d.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            print("🌊 TidalDrop: Expecting metadata of \(metadataSize) bytes")
            
            // 2. Receive metadata JSON
            connection.receive(minimumIncompleteLength: metadataSize, maximumLength: metadataSize) { [weak self] data, _, _, error in
                if let error = error {
                    print("❌ TidalDrop: Error receiving metadata: \(error)")
                    return
                }
                guard let self = self, let d = data else {
                    print("❌ TidalDrop: No metadata received")
                    return
                }
                
                guard let metadata = try? JSONDecoder().decode(FileMetadata.self, from: d) else {
                    print("❌ TidalDrop: Failed to decode metadata")
                    return
                }
                
                self.setupIncomingTransfer(connection, metadata: metadata)
            }
        }
    }
    
    private func setupIncomingTransfer(_ connection: NWConnection, metadata: FileMetadata) {
        print("🌊 TidalDrop: Receiving '\(metadata.fileName)' (\(metadata.fileSize) bytes)")
        
        let transferId = UUID()
        let destinationFolder = AppState.shared.settings.tidalDropFolder
        
        // Create destination folder
        do {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true, attributes: nil)
            print("🌊 TidalDrop: Destination folder: \(destinationFolder.path)")
        } catch {
            print("❌ TidalDrop: Failed to create destination folder: \(error)")
        }
        
        let fileURL = destinationFolder.appendingPathComponent(metadata.fileName)
        print("🌊 TidalDrop: Saving to: \(fileURL.path)")
        
        let transfer = DropTransfer(
            id: transferId,
            fileName: metadata.fileName,
            fileSize: metadata.fileSize,
            progress: 0,
            isIncoming: true,
            status: .transferring,
            remoteEndpoint: "\(connection.endpoint)"
        )
        
        DispatchQueue.main.async {
            self.activeTransfers[transferId] = transfer
            self.notifyTransferStarted(fileName: metadata.fileName, isIncoming: true)
        }
        
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        
        receiveFileData(connection, transferId: transferId, fileURL: fileURL, fileSize: metadata.fileSize, receivedSoFar: 0)
    }
    
    private func receiveFileData(_ connection: NWConnection, transferId: UUID, fileURL: URL, fileSize: Int64, receivedSoFar: Int64) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self else { return }
            
            if let d = data {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(d)
                    handle.closeFile()
                }
                
                let newReceived = receivedSoFar + Int64(d.count)
                let progress = Double(newReceived) / Double(fileSize)
                
                DispatchQueue.main.async {
                    self.activeTransfers[transferId]?.progress = progress
                }
                
                if newReceived < fileSize {
                    self.receiveFileData(connection, transferId: transferId, fileURL: fileURL, fileSize: fileSize, receivedSoFar: newReceived)
                } else {
                    self.completeTransfer(transferId: transferId, fileName: fileURL.lastPathComponent, isIncoming: true)
                    connection.cancel()
                }
            }
            
            if let e = error {
                DispatchQueue.main.async {
                    self.activeTransfers[transferId]?.status = .failed(e.localizedDescription)
                }
            }
        }
    }
    
    func sendFile(at url: URL, to ipAddress: String) {
        print("🌊 TidalDrop: Attempting to send \(url.lastPathComponent) to \(ipAddress)")
        
        // Start security-scoped access for sandboxed files
        let didStartAccess = url.startAccessingSecurityScopedResource()
        
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Check file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ TidalDrop: File does not exist: \(url.path)")
            return
        }
        
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            print("❌ TidalDrop: File is not readable: \(url.path)")
            return
        }
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ipAddress), port: 5902)
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        let transferId = UUID()
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        
        print("🌊 TidalDrop: File size: \(size) bytes")
        
        let transfer = DropTransfer(
            id: transferId,
            fileName: name,
            fileSize: size,
            progress: 0,
            isIncoming: false,
            status: .pending,
            remoteEndpoint: ipAddress
        )
        
        DispatchQueue.main.async {
            self.activeTransfers[transferId] = transfer
            self.notifyTransferStarted(fileName: name, isIncoming: false)
        }
        
        // Copy file data before connection (in case security scope ends)
        guard let fileData = try? Data(contentsOf: url) else {
            print("❌ TidalDrop: Failed to read file data")
            return
        }
        
        print("🌊 TidalDrop: Read \(fileData.count) bytes, connecting to \(ipAddress):5902")
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("🌊 TidalDrop: Connection ready, sending...")
                self?.performSendWithData(connection, transferId: transferId, name: name, size: size, fileData: fileData)
            case .failed(let error):
                print("❌ TidalDrop: Connection failed: \(error)")
                DispatchQueue.main.async {
                    self?.activeTransfers[transferId]?.status = .failed(error.localizedDescription)
                }
            case .waiting(let error):
                print("🌊 TidalDrop: Connection waiting: \(error)")
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
    
    private func performSendWithData(_ connection: NWConnection, transferId: UUID, name: String, size: Int64, fileData: Data) {
        DispatchQueue.main.async {
            self.activeTransfers[transferId]?.status = .transferring
        }
        
        let metadata = FileMetadata(fileName: name, fileSize: size)
        guard let metadataData = try? JSONEncoder().encode(metadata) else {
            print("❌ TidalDrop: Failed to encode metadata")
            return
        }
        
        var header = Data()
        let metadataSize = UInt32(metadataData.count).bigEndian
        header.append(Data([
            UInt8((metadataSize >> 24) & 0xFF),
            UInt8((metadataSize >> 16) & 0xFF),
            UInt8((metadataSize >> 8) & 0xFF),
            UInt8(metadataSize & 0xFF)
        ]))
        header.append(metadataData)
        
        print("🌊 TidalDrop: Sending header (\(header.count) bytes)")
        
        connection.send(content: header, completion: .contentProcessed { [weak self] error in
            if let e = error {
                print("❌ TidalDrop: Header send failed: \(e)")
                DispatchQueue.main.async { self?.activeTransfers[transferId]?.status = .failed(e.localizedDescription) }
                return
            }
            
            print("🌊 TidalDrop: Header sent, sending file data (\(fileData.count) bytes)")
            
            connection.send(content: fileData, completion: .contentProcessed { [weak self] error in
                if let e = error {
                    print("❌ TidalDrop: File send failed: \(e)")
                    DispatchQueue.main.async { self?.activeTransfers[transferId]?.status = .failed(e.localizedDescription) }
                } else {
                    print("✅ TidalDrop: File sent successfully!")
                    DispatchQueue.main.async { self?.activeTransfers[transferId]?.progress = 1.0 }
                    self?.completeTransfer(transferId: transferId, fileName: name, isIncoming: false)
                    connection.cancel()
                }
            })
        })
    }
    
    
    private func completeTransfer(transferId: UUID, fileName: String, isIncoming: Bool) {
        DispatchQueue.main.async {
            self.activeTransfers[transferId]?.status = .completed
        }
        
        let content = UNMutableNotificationContent()
        content.title = isIncoming ? "TidalDrop Received" : "TidalDrop Sent"
        let folderName = AppState.shared.settings.tidalDropFolder.lastPathComponent
        content.body = isIncoming ? "'\(fileName)' saved to \(folderName)" : "'\(fileName)' sent successfully"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    
    private func notifyTransferStarted(fileName: String, isIncoming: Bool) {
        let content = UNMutableNotificationContent()
        content.title = isIncoming ? "Incoming TidalDrop" : "Sending TidalDrop"
        content.body = isIncoming ? "Receiving '\(fileName)'..." : "Transferring '\(fileName)'..."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
