import Foundation
import AppKit

enum ConnectionError: LocalizedError {
    case invalidAddress
    case connectionFailed
    case authenticationFailed
    case timeout
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid IP address or hostname"
        case .connectionFailed:
            return "Failed to establish connection"
        case .authenticationFailed:
            return "Authentication failed"
        case .timeout:
            return "Connection timed out"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

enum ScreenShareMode {
    case control
    case observe
}

class ScreenShareConnectionService {
    static let shared = ScreenShareConnectionService()
    
    private init() {}
    
    func connect(to device: DiscoveredDevice, mode: ScreenShareMode = .control, username: String? = nil) async throws {
        let urlString: String
        
        if let username = username {
            urlString = "vnc://\(username)@\(device.ipAddress):\(device.port)"
        } else {
            urlString = "vnc://\(device.ipAddress):\(device.port)"
        }
        
        guard let url = URL(string: urlString) else {
            throw ConnectionError.invalidAddress
        }
        
        let success = await MainActor.run {
            NSWorkspace.shared.open(url)
        }
        
        if !success {
            throw ConnectionError.connectionFailed
        }
    }
    
    func connectWithScreenSharingApp(to device: DiscoveredDevice) throws {
        let screenSharingPath = "/System/Library/CoreServices/Applications/Screen Sharing.app"
        let screenSharingURL = URL(fileURLWithPath: screenSharingPath)
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [device.ipAddress]
        
        NSWorkspace.shared.openApplication(at: screenSharingURL, configuration: configuration) { app, error in
            if let error = error {
                print("Failed to open Screen Sharing: \(error.localizedDescription)")
            }
        }
    }
    
    func connectToFileShare(device: DiscoveredDevice, username: String? = nil) async throws {
        let urlString: String
        
        if let username = username {
            urlString = "smb://\(username)@\(device.ipAddress)"
        } else {
            urlString = "smb://\(device.ipAddress)"
        }
        
        guard let url = URL(string: urlString) else {
            throw ConnectionError.invalidAddress
        }
        
        let success = await MainActor.run {
            NSWorkspace.shared.open(url)
        }
        
        if !success {
            throw ConnectionError.connectionFailed
        }
    }
    
    func connectToAFP(device: DiscoveredDevice, username: String? = nil) async throws {
        let urlString: String
        
        if let username = username {
            urlString = "afp://\(username)@\(device.ipAddress)"
        } else {
            urlString = "afp://\(device.ipAddress)"
        }
        
        guard let url = URL(string: urlString) else {
            throw ConnectionError.invalidAddress
        }
        
        let success = await MainActor.run {
            NSWorkspace.shared.open(url)
        }
        
        if !success {
            throw ConnectionError.connectionFailed
        }
    }
    
    func testConnection(to ipAddress: String, port: Int = 5900) async -> Bool {
        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(ipAddress)
            let port = NWEndpoint.Port(rawValue: UInt16(port))!
            let connection = NWConnection(host: host, port: port, using: .tcp)
            
            var didResume = false
            
            connection.stateUpdateHandler = { state in
                guard !didResume else { return }
                
                switch state {
                case .ready:
                    didResume = true
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    didResume = true
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                guard !didResume else { return }
                didResume = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }
}

import Network
