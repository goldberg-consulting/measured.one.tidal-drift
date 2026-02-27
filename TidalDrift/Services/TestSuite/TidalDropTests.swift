import Foundation
import Network

extension TidalDriftTestRunner {
    
    func testDropDestinationExists() async -> (Bool, String) {
        let folder = AppState.shared.settings.tidalDropFolder
        let exists = FileManager.default.fileExists(atPath: folder.path)
        if exists {
            let writable = FileManager.default.isWritableFile(atPath: folder.path)
            return (writable,
                    writable ? "Drop folder exists and is writable: \(folder.path)"
                             : "Drop folder exists but is NOT writable: \(folder.path)")
        }
        
        // Try to create it
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return (true, "Created drop folder: \(folder.path)")
        } catch {
            return (false, "Drop folder missing and cannot create: \(error.localizedDescription)")
        }
    }
    
    func testLoopbackSmallFileTransfer() async -> (Bool, String) {
        await performLoopbackTransfer(size: 256, label: "small (256B)")
    }
    
    func testLoopbackLargeFileTransfer() async -> (Bool, String) {
        await performLoopbackTransfer(size: 1_000_000, label: "1MB")
    }
    
    /// Performs a full peer-to-peer file transfer over loopback:
    /// starts a temporary listener, connects, sends metadata+payload, verifies receipt.
    private func performLoopbackTransfer(size: Int, label: String) async -> (Bool, String) {
        let testPort: UInt16 = 15920
        let testFileName = "tidaltest-\(UUID().uuidString.prefix(8)).bin"
        let testData = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
        
        var receivedFileName: String?
        var receivedData = Data()
        var receivedComplete = false
        
        let queue = DispatchQueue(label: "test.drop.loopback")
        
        // --- Server side (simulates TidalDrop receiver) ---
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: testPort)!)
        } catch {
            return (false, "Cannot bind test port \(testPort): \(error.localizedDescription)")
        }
        
        listener.newConnectionHandler = { conn in
            conn.start(queue: queue)
            
            // Read 4-byte metadata length
            conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, _ in
                guard let d = data else { return }
                let metaSize = Int(d.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                
                // Read metadata JSON
                conn.receive(minimumIncompleteLength: metaSize, maximumLength: metaSize) { data, _, _, _ in
                    guard let d = data else { return }
                    if let meta = try? JSONDecoder().decode(TidalDropService.FileMetadata.self, from: d) {
                        receivedFileName = meta.fileName
                        
                        func readChunk() {
                            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
                                if let d = data { receivedData.append(d) }
                                if receivedData.count >= Int(meta.fileSize) || isComplete {
                                    receivedComplete = true
                                    conn.cancel()
                                } else {
                                    readChunk()
                                }
                            }
                        }
                        readChunk()
                    }
                }
            }
        }
        listener.start(queue: queue)
        defer { listener.cancel() }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // --- Client side (simulates TidalDrop sender) ---
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: testPort)!)
        let conn = NWConnection(to: endpoint, using: .tcp)
        var sendComplete = false
        
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                let metadata = TidalDropService.FileMetadata(fileName: testFileName, fileSize: Int64(testData.count))
                guard let metaJSON = try? JSONEncoder().encode(metadata) else { return }
                
                var header = Data()
                let metaSize = UInt32(metaJSON.count).bigEndian
                withUnsafeBytes(of: metaSize) { header.append(contentsOf: $0) }
                header.append(metaJSON)
                
                conn.send(content: header, completion: .contentProcessed { _ in
                    conn.send(content: testData, completion: .contentProcessed { _ in
                        sendComplete = true
                        conn.cancel()
                    })
                })
            }
        }
        conn.start(queue: queue)
        
        // Wait for completion
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if receivedComplete { break }
        }
        
        guard receivedComplete else {
            return (false, "Transfer timed out (\(label)) — sent: \(sendComplete), received: \(receivedData.count)/\(size)")
        }
        guard receivedFileName == testFileName else {
            return (false, "Filename mismatch: expected '\(testFileName)', got '\(receivedFileName ?? "nil")'")
        }
        guard receivedData == testData else {
            return (false, "Data mismatch (\(label)): \(receivedData.count) bytes received, \(testData.count) expected")
        }
        
        return (true, "Loopback transfer \(label): \(size) bytes sent, received, and verified")
    }
}
