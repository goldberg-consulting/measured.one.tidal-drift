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
    
    @Published var isListening = false
    
    private init() {
        // Start listener immediately - it's non-blocking
        startListening()
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func startListening() {
        // If already listening, skip
        guard listener == nil else {
            print("🌊 TidalDrop: Listener already active")
            return
        }
        
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: 5902)
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        print("🌊 TidalDrop: Listener ready on port 5902")
                        self?.isListening = true
                    case .failed(let error):
                        print("❌ TidalDrop: Listener failed: \(error)")
                        self?.isListening = false
                        // Try to restart after failure
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self?.listener = nil
                            self?.startListening()
                        }
                    case .cancelled:
                        print("🌊 TidalDrop: Listener cancelled")
                        self?.isListening = false
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                let remoteEndpoint = "\(connection.endpoint)"
                print("🌊 TidalDrop: Incoming connection from \(remoteEndpoint)")
                self?.handleIncomingConnection(connection)
            }
            
            listener?.start(queue: queue)
            print("🌊 TidalDrop: Starting listener on port 5902...")
        } catch {
            print("❌ TidalDrop: Failed to create listener: \(error)")
            isListening = false
        }
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        let remoteEndpoint = "\(connection.endpoint)"
        print("🌊 TidalDrop: Setting up connection from \(remoteEndpoint)")
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("🌊 TidalDrop: Incoming connection ready from \(remoteEndpoint)")
            case .failed(let error):
                print("❌ TidalDrop: Incoming connection failed: \(error)")
            case .cancelled:
                print("🌊 TidalDrop: Incoming connection cancelled")
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        
        // 1. Receive metadata size (4 bytes)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("❌ TidalDrop: Error receiving header size from \(remoteEndpoint): \(error)")
                connection.cancel()
                return
            }
            guard let self = self, let d = data, d.count == 4 else {
                print("❌ TidalDrop: No/incomplete data received for header size from \(remoteEndpoint) (got \(data?.count ?? 0) bytes)")
                connection.cancel()
                return
            }
            
            let metadataSize = Int(d.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            print("🌊 TidalDrop: Expecting metadata of \(metadataSize) bytes from \(remoteEndpoint)")
            
            // Sanity check metadata size
            guard metadataSize > 0 && metadataSize < 10000 else {
                print("❌ TidalDrop: Invalid metadata size: \(metadataSize)")
                connection.cancel()
                return
            }
            
            // 2. Receive metadata JSON
            connection.receive(minimumIncompleteLength: metadataSize, maximumLength: metadataSize) { [weak self] data, _, _, error in
                if let error = error {
                    print("❌ TidalDrop: Error receiving metadata from \(remoteEndpoint): \(error)")
                    connection.cancel()
                    return
                }
                guard let self = self, let d = data, d.count == metadataSize else {
                    print("❌ TidalDrop: Incomplete metadata received from \(remoteEndpoint)")
                    connection.cancel()
                    return
                }
                
                guard let metadata = try? JSONDecoder().decode(FileMetadata.self, from: d) else {
                    print("❌ TidalDrop: Failed to decode metadata from \(remoteEndpoint). Raw: \(String(data: d, encoding: .utf8) ?? "not utf8")")
                    connection.cancel()
                    return
                }
                
                print("🌊 TidalDrop: Received metadata - file: '\(metadata.fileName)', size: \(metadata.fileSize) bytes")
                self.setupIncomingTransfer(connection, metadata: metadata, remoteEndpoint: remoteEndpoint)
            }
        }
    }
    
    private func setupIncomingTransfer(_ connection: NWConnection, metadata: FileMetadata, remoteEndpoint: String) {
        print("🌊 TidalDrop: Receiving '\(metadata.fileName)' (\(metadata.fileSize) bytes) from \(remoteEndpoint)")
        
        let transferId = UUID()
        let destinationFolder = AppState.shared.settings.tidalDropFolder
        
        // Create destination folder
        do {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true, attributes: nil)
            print("🌊 TidalDrop: Destination folder created/verified: \(destinationFolder.path)")
        } catch {
            print("❌ TidalDrop: Failed to create destination folder: \(error)")
            DispatchQueue.main.async {
                self.activeTransfers[transferId] = DropTransfer(
                    id: transferId,
                    fileName: metadata.fileName,
                    fileSize: metadata.fileSize,
                    progress: 0,
                    isIncoming: true,
                    status: .failed("Cannot create destination folder: \(error.localizedDescription)"),
                    remoteEndpoint: remoteEndpoint
                )
            }
            connection.cancel()
            return
        }
        
        let fileURL = destinationFolder.appendingPathComponent(metadata.fileName)
        print("🌊 TidalDrop: Will save to: \(fileURL.path)")
        
        let transfer = DropTransfer(
            id: transferId,
            fileName: metadata.fileName,
            fileSize: metadata.fileSize,
            progress: 0,
            isIncoming: true,
            status: .transferring,
            remoteEndpoint: remoteEndpoint
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let d = data, !d.isEmpty {
                do {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    handle.seekToEndOfFile()
                    handle.write(d)
                    try handle.close()
                } catch {
                    print("❌ TidalDrop: Failed to write data to file: \(error)")
                    DispatchQueue.main.async {
                        self.activeTransfers[transferId]?.status = .failed("Failed to write file: \(error.localizedDescription)")
                    }
                    connection.cancel()
                    return
                }
                
                let newReceived = receivedSoFar + Int64(d.count)
                let progress = Double(newReceived) / Double(fileSize)
                
                // Log every ~10% progress
                let oldPercent = Int((Double(receivedSoFar) / Double(fileSize)) * 10)
                let newPercent = Int(progress * 10)
                if newPercent > oldPercent {
                    print("🌊 TidalDrop: Receiving \(fileURL.lastPathComponent) - \(Int(progress * 100))%")
                }
                
                DispatchQueue.main.async {
                    self.activeTransfers[transferId]?.progress = progress
                }
                
                if newReceived < fileSize {
                    self.receiveFileData(connection, transferId: transferId, fileURL: fileURL, fileSize: fileSize, receivedSoFar: newReceived)
                } else {
                    print("✅ TidalDrop: File received completely: \(fileURL.lastPathComponent)")
                    self.completeTransfer(transferId: transferId, fileName: fileURL.lastPathComponent, isIncoming: true)
                    connection.cancel()
                }
            } else if let e = error {
                print("❌ TidalDrop: Error receiving file data: \(e)")
                DispatchQueue.main.async {
                    self.activeTransfers[transferId]?.status = .failed(e.localizedDescription)
                }
                connection.cancel()
            } else if isComplete && receivedSoFar < fileSize {
                // Connection closed early
                print("❌ TidalDrop: Connection closed before transfer complete (\(receivedSoFar)/\(fileSize) bytes)")
                DispatchQueue.main.async {
                    self.activeTransfers[transferId]?.status = .failed("Transfer incomplete: connection closed")
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
        
        // Use TCP with optimized parameters for local transfers
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 10  // 10 second timeout
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.prohibitExpensivePaths = false
        params.prohibitConstrainedPaths = false
        
        let connection = NWConnection(to: endpoint, using: params)
        
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
        
        var didConnect = false
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                didConnect = true
                print("🌊 TidalDrop: Connection ready, sending...")
                self?.performSendWithData(connection, transferId: transferId, name: name, size: size, fileData: fileData)
            case .failed(let error):
                print("❌ TidalDrop: Connection failed: \(error)")
                print("   Tip: Make sure the receiving TidalDrift app is running and port 5902 is not blocked by firewall")
                DispatchQueue.main.async {
                    self?.activeTransfers[transferId]?.status = .failed("Connection failed: \(error.localizedDescription). Is TidalDrift running on the remote Mac?")
                }
            case .waiting(let error):
                print("🌊 TidalDrop: Connection waiting: \(error)")
                // Log specific NWError details
                if case .posix(let posixError) = error {
                    print("   POSIX error code: \(posixError.rawValue)")
                    if posixError == .ECONNREFUSED {
                        print("   Connection refused - remote TidalDrift likely not running or port blocked")
                    } else if posixError == .ETIMEDOUT {
                        print("   Connection timed out - network issue or firewall")
                    } else if posixError == .EHOSTUNREACH {
                        print("   Host unreachable - check if target is on same network")
                    }
                }
                // Don't fail yet, might still connect
            case .cancelled:
                if !didConnect {
                    print("❌ TidalDrop: Connection cancelled before ready")
                    DispatchQueue.main.async {
                        self?.activeTransfers[transferId]?.status = .failed("Connection timed out")
                    }
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        
        // Add connection timeout - if not connected after 10 seconds, fail
        queue.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard !didConnect else { return }
            print("❌ TidalDrop: Connection timeout to \(ipAddress)")
            connection.cancel()
            DispatchQueue.main.async {
                self?.activeTransfers[transferId]?.status = .failed("Connection timeout. Remote TidalDrift may not be running or port 5902 is blocked.")
            }
        }
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
