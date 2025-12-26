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
/// Also supports fallback to mounted SMB/AFP shares
class TidalDropService: ObservableObject {
    static let shared = TidalDropService()
    
    @Published var activeTransfers: [UUID: DropTransfer] = [:]
    @Published var isListening = false
    
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
    
    // MARK: - Smart Drop (tries mounted drives first)
    
    /// Sends a file using the best available method:
    /// 1. If target has a mounted share, copies there directly
    /// 2. Otherwise uses peer-to-peer TidalDrop protocol
    func smartSendFile(at url: URL, to device: DiscoveredDevice) {
        print("🌊 TidalDrop: Smart send - checking for mounted shares for \(device.name)")
        
        // Check for mounted volumes that might be from this device
        if let mountedPath = findMountedShare(for: device) {
            print("🌊 TidalDrop: Found mounted share: \(mountedPath)")
            copyToMountedShare(file: url, destination: mountedPath, device: device)
        } else {
            print("🌊 TidalDrop: No mounted share, using peer-to-peer")
            sendFile(at: url, to: device.ipAddress)
        }
    }
    
    /// Finds a mounted network share that belongs to the target device
    private func findMountedShare(for device: DiscoveredDevice) -> URL? {
        let volumesPath = URL(fileURLWithPath: "/Volumes")
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: volumesPath,
            includingPropertiesForKeys: [.volumeIsRemovableKey, .volumeURLForRemountingKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        
        // Look for network volumes that might match the device
        for volumeURL in contents {
            // Check if it's a network volume
            if let remountURL = try? volumeURL.resourceValues(forKeys: [.volumeURLForRemountingKey]).volumeURLForRemounting,
               let host = remountURL.host {
                // Match by IP address or hostname
                let hostLower = host.lowercased()
                let deviceHost = device.hostname.lowercased().replacingOccurrences(of: ".local", with: "")
                let deviceName = device.name.lowercased()
                
                if host == device.ipAddress ||
                   hostLower == deviceHost ||
                   hostLower.contains(deviceName) ||
                   deviceName.contains(hostLower) {
                    print("🌊 TidalDrop: Matched volume \(volumeURL.lastPathComponent) to device \(device.name)")
                    return volumeURL
                }
            }
        }
        
        return nil
    }
    
    /// Copies a file to a mounted network share
    private func copyToMountedShare(file: URL, destination: URL, device: DiscoveredDevice) {
        let transferId = UUID()
        let fileName = file.lastPathComponent
        let fileSize = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        
        let transfer = DropTransfer(
            id: transferId,
            fileName: fileName,
            fileSize: fileSize,
            progress: 0,
            isIncoming: false,
            status: .transferring,
            remoteEndpoint: device.ipAddress
        )
        
        DispatchQueue.main.async {
            self.activeTransfers[transferId] = transfer
        }
        
        // Perform copy on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let destinationFile = destination.appendingPathComponent(fileName)
            
            // Handle existing file
            if FileManager.default.fileExists(atPath: destinationFile.path) {
                try? FileManager.default.removeItem(at: destinationFile)
            }
            
            do {
                try FileManager.default.copyItem(at: file, to: destinationFile)
                
                print("✅ TidalDrop: Copied to mounted share: \(destinationFile.path)")
                
                DispatchQueue.main.async {
                    self.activeTransfers[transferId]?.progress = 1.0
                    self.activeTransfers[transferId]?.status = .completed
                }
                
                self.notifyCompletion(fileName: fileName, isIncoming: false, viaMountedShare: true)
            } catch {
                print("❌ TidalDrop: Failed to copy to mounted share: \(error)")
                
                DispatchQueue.main.async {
                    self.activeTransfers[transferId]?.status = .failed("Copy failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func notifyCompletion(fileName: String, isIncoming: Bool, viaMountedShare: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = isIncoming ? "TidalDrop Received" : "TidalDrop Sent"
        
        if viaMountedShare {
            content.body = "'\(fileName)' copied to shared folder"
        } else {
            let folderName = AppState.shared.settings.tidalDropFolder.lastPathComponent
            content.body = isIncoming ? "'\(fileName)' saved to \(folderName)" : "'\(fileName)' sent successfully"
        }
        
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func startListening() {
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: 5902)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            listener?.start(queue: queue)
            print("🌊 TidalDrop: Listening on port 5902")
        } catch {
            print("❌ TidalDrop: Listener failed: \(error)")
        }
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        
        // 1. Receive metadata size (4 bytes)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self, let d = data, error == nil else { return }
            let metadataSize = Int(d.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            
            // 2. Receive metadata JSON
            connection.receive(minimumIncompleteLength: metadataSize, maximumLength: metadataSize) { [weak self] data, _, _, error in
                guard let self = self, let d = data, let metadata = try? JSONDecoder().decode(FileMetadata.self, from: d) else { return }
                
                self.setupIncomingTransfer(connection, metadata: metadata)
            }
        }
    }
    
    private func setupIncomingTransfer(_ connection: NWConnection, metadata: FileMetadata) {
        let transferId = UUID()
        let destinationFolder = AppState.shared.settings.tidalDropFolder
        try? FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let fileURL = destinationFolder.appendingPathComponent(metadata.fileName)
        
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
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ipAddress), port: 5902)
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        let transferId = UUID()
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        
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
        
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.performSend(connection, transferId: transferId, url: url, name: name, size: size)
            } else if case .failed(let error) = state {
                DispatchQueue.main.async {
                    self?.activeTransfers[transferId]?.status = .failed(error.localizedDescription)
                }
            }
        }
        connection.start(queue: queue)
    }
    
    private func performSend(_ connection: NWConnection, transferId: UUID, url: URL, name: String, size: Int64) {
        DispatchQueue.main.async {
            self.activeTransfers[transferId]?.status = .transferring
        }
        
        let metadata = FileMetadata(fileName: name, fileSize: size)
        guard let metadataData = try? JSONEncoder().encode(metadata) else { return }
        
        var header = Data()
        var metadataSize = UInt32(metadataData.count).bigEndian
        header.append(Data([
            UInt8((metadataSize >> 24) & 0xFF),
            UInt8((metadataSize >> 16) & 0xFF),
            UInt8((metadataSize >> 8) & 0xFF),
            UInt8(metadataSize & 0xFF)
        ]))
        header.append(metadataData)
        
        connection.send(content: header, completion: .contentProcessed { [weak self] error in
            if let e = error {
                DispatchQueue.main.async { self?.activeTransfers[transferId]?.status = .failed(e.localizedDescription) }
                return
            }
            
            if let fileData = try? Data(contentsOf: url) {
                connection.send(content: fileData, completion: .contentProcessed { [weak self] error in
                    if let e = error {
                        DispatchQueue.main.async { self?.activeTransfers[transferId]?.status = .failed(e.localizedDescription) }
                    } else {
                        DispatchQueue.main.async { self?.activeTransfers[transferId]?.progress = 1.0 }
                        self?.completeTransfer(transferId: transferId, fileName: name, isIncoming: false)
                        connection.cancel()
                    }
                })
            }
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
