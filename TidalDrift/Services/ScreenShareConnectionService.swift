import Foundation
import AppKit

enum ConnectionError: LocalizedError {
    case invalidAddress
    case connectionFailed
    case authenticationFailed
    case timeout
    case scriptError(String)
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
        case .scriptError(let message):
            return "Script error: \(message)"
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
    
    func connect(to device: DiscoveredDevice, mode: ScreenShareMode = .control, username: String? = nil, password: String? = nil) async throws {
        // If we have both username and password, use AppleScript to connect with credentials
        if let username = username, !username.isEmpty,
           let password = password, !password.isEmpty {
            try await connectWithCredentials(to: device.ipAddress, port: device.port, username: username, password: password)
        } else {
            // Otherwise, just open the VNC URL and let Screen Sharing handle auth
            let urlString: String
            
            if let username = username, !username.isEmpty {
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
    }
    
    /// Connect using AppleScript to pass credentials directly to Screen Sharing
    private func connectWithCredentials(to ipAddress: String, port: Int, username: String, password: String) async throws {
        // Validate IP address format to prevent injection
        guard isValidIPAddress(ipAddress) else {
            throw ConnectionError.invalidAddress
        }
        
        // Escape special characters for AppleScript string
        let escapedUsername = escapeForAppleScript(username)
        let escapedPassword = escapeForAppleScript(password)
        
        // Build VNC URL with properly escaped credentials
        let vncURL = "vnc://\(escapedUsername):\(escapedPassword)@\(ipAddress):\(port)"
        
        // Use AppleScript to open the connection
        let script = """
        tell application "Screen Sharing"
            activate
            open location "\(vncURL)"
        end tell
        """
        
        let result = await MainActor.run { () -> (Bool, String?) in
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    return (false, error[NSAppleScript.errorMessage] as? String)
                }
                return (true, nil)
            }
            return (false, "Failed to create AppleScript")
        }
        
        if !result.0 {
            // Fall back to URL method (without password - macOS will prompt)
            let escapedUsernameForURL = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            let urlString = "vnc://\(escapedUsernameForURL)@\(ipAddress):\(port)"
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
    }
    
    /// Validate IP address format
    private func isValidIPAddress(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part) else { return false }
            return num >= 0 && num <= 255
        }
    }
    
    /// Escape string for safe use in AppleScript
    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }
    
    func connectWithScreenSharingApp(to device: DiscoveredDevice) throws {
        let screenSharingPath = "/System/Library/CoreServices/Applications/Screen Sharing.app"
        let screenSharingURL = URL(fileURLWithPath: screenSharingPath)
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [device.ipAddress]
        
        NSWorkspace.shared.openApplication(at: screenSharingURL, configuration: configuration) { _, _ in
            // Connection handled by Screen Sharing app
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
