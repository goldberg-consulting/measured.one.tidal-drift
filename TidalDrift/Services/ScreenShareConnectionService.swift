import Foundation
import AppKit
import Network

enum ConnectionError: LocalizedError {
    case invalidAddress
    case connectionFailed
    case authenticationFailed
    case timeout
    case scriptError(String)
    case screenSharingNotPermitted(String) // The "sticky" macOS bug
    case remoteServiceDown
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
        case .screenSharingNotPermitted(let ip):
            return "Screen Sharing not permitted on \(ip). The remote machine needs to restart its Screen Sharing service."
        case .remoteServiceDown:
            return "Remote Screen Sharing service is not running"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .screenSharingNotPermitted:
            return """
            This is a known macOS bug. To fix:
            
            ON THE REMOTE MACHINE:
            1. System Settings → General → Sharing
            2. Turn OFF Screen Sharing
            3. Wait 5 seconds
            4. Turn ON Screen Sharing
            
            Or if TidalDrift is running there, use "Fix Remote" button.
            """
        case .remoteServiceDown:
            return "Enable Screen Sharing on the remote machine in System Settings → General → Sharing"
        default:
            return nil
        }
    }
}

enum ScreenShareMode {
    case control
    case observe
}

class ScreenShareConnectionService {
    static let shared = ScreenShareConnectionService()
    
    // Store active connections to prevent premature deallocation
    private var activeConnections: [UUID: NWConnection] = [:]
    private let connectionsLock = NSLock()
    
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
    
    func connectToSSH(device: DiscoveredDevice, username: String? = nil) {
        let user = username ?? NSUserName()
        let host = device.ipAddress
        
        print("🔌 SSH: Connecting to \(user)@\(host)")
        
        // Guard against invalid host
        guard !host.isEmpty, host != "Unknown" else {
            print("❌ SSH: Invalid host address: \(host)")
            return
        }
        
        // Use Process to run osascript for more reliable Terminal control
        let sshCommand = "ssh -o StrictHostKeyChecking=accept-new \(user)@\(host)"
        
        let appleScript = """
        tell application "Terminal"
            activate
            set newWindow to do script "\(sshCommand)"
            set current settings of newWindow to settings set "Basic"
        end tell
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        
        do {
            try process.run()
            print("✅ SSH: Terminal launched for \(user)@\(host)")
        } catch {
            print("❌ SSH: Failed to launch Terminal: \(error)")
            
            // Fallback: try opening terminal URL
            if let url = URL(string: "ssh://\(user)@\(host)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    func testConnection(to ipAddress: String, port: Int = 5900) async -> Bool {
        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(ipAddress)
            let port = NWEndpoint.Port(rawValue: UInt16(port))!
            let connection = NWConnection(host: host, port: port, using: .tcp)
            let connectionId = UUID()
            
            // Store connection to prevent premature deallocation
            self.connectionsLock.lock()
            self.activeConnections[connectionId] = connection
            self.connectionsLock.unlock()
            
            let didResume = AtomicFlag()
            
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard !didResume.value else { return }
                    didResume.value = true
                    self?.cleanupConnection(id: connectionId)
                    continuation.resume(returning: true)
                case .failed:
                    guard !didResume.value else { return }
                    didResume.value = true
                    self?.cleanupConnection(id: connectionId)
                    continuation.resume(returning: false)
                case .cancelled:
                    self?.connectionsLock.lock()
                    self?.activeConnections.removeValue(forKey: connectionId)
                    self?.connectionsLock.unlock()
                    
                    guard !didResume.value else { return }
                    didResume.value = true
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                guard !didResume.value else { return }
                didResume.value = true
                self?.cleanupConnection(id: connectionId)
                continuation.resume(returning: false)
            }
        }
    }
    
    private func cleanupConnection(id: UUID) {
        connectionsLock.lock()
        if let connection = activeConnections[id] {
            connection.cancel()
        }
        connectionsLock.unlock()
    }
    
    // MARK: - Remote Screen Sharing Fix
    
    /// Restart the local Screen Sharing service (fixes "not permitted" error)
    /// This can be called locally or triggered remotely by another TidalDrift instance
    func restartLocalScreenSharing() async -> Bool {
        // Method 1: Try AppleScript (works without admin for toggle)
        let toggleScript = """
        tell application "System Preferences"
            reveal anchor "Services_ScreenSharing" of pane id "com.apple.preferences.sharing"
            activate
        end tell
        
        delay 0.5
        
        tell application "System Events"
            tell process "System Preferences"
                -- Find and toggle Screen Sharing
                try
                    set screenSharingRow to row 1 of table 1 of scroll area 1 of group 1 of window 1
                    set checkboxElement to checkbox 1 of screenSharingRow
                    
                    -- Toggle off then on
                    if value of checkboxElement is 1 then
                        click checkboxElement
                        delay 1
                        click checkboxElement
                    end if
                end try
            end tell
        end tell
        
        tell application "System Preferences" to quit
        """
        
        // Method 2: Use launchctl (may need sudo)
        let launchctlCommands = [
            "launchctl bootout system/com.apple.screensharing 2>/dev/null; sleep 1; launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null",
            "sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null"
        ]
        
        // Try AppleScript first (user-friendly)
        var error: NSDictionary?
        if let script = NSAppleScript(source: toggleScript) {
            script.executeAndReturnError(&error)
            if error == nil {
                // Wait a moment for the service to restart
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return true
            }
        }
        
        // Fall back to launchctl
        for cmd in launchctlCommands {
            let result = ShellExecutor.execute(cmd)
            if result.exitCode == 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                return true
            }
        }
        
        return false
    }
    
    /// Request a remote TidalDrift peer to restart its Screen Sharing service
    func requestRemoteScreenSharingRestart(ipAddress: String) async -> Bool {
        // Connect to the remote TidalDrift's control port
        let port: UInt16 = 5901 // TidalDrift's streaming port
        
        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(ipAddress)
            let portEndpoint = NWEndpoint.Port(rawValue: port)!
            let connection = NWConnection(host: host, port: portEndpoint, using: .tcp)
            let connectionId = UUID()
            
            // Store connection to prevent premature deallocation
            self.connectionsLock.lock()
            self.activeConnections[connectionId] = connection
            self.connectionsLock.unlock()
            
            let didResume = AtomicFlag()
            
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard !didResume.value else { return }
                    
                    // Send the restart command
                    let command = "RESTART_SCREEN_SHARING\n"
                    let data = Data(command.utf8)
                    
                    connection.send(content: data, completion: .contentProcessed { error in
                        guard !didResume.value else { return }
                        didResume.value = true
                        self?.cleanupConnection(id: connectionId)
                        
                        if error == nil {
                            continuation.resume(returning: true)
                        } else {
                            continuation.resume(returning: false)
                        }
                    })
                    
                case .failed:
                    guard !didResume.value else { return }
                    didResume.value = true
                    self?.cleanupConnection(id: connectionId)
                    continuation.resume(returning: false)
                    
                case .cancelled:
                    self?.connectionsLock.lock()
                    self?.activeConnections.removeValue(forKey: connectionId)
                    self?.connectionsLock.unlock()
                    
                    guard !didResume.value else { return }
                    didResume.value = true
                    continuation.resume(returning: false)
                    
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
            
            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                guard !didResume.value else { return }
                didResume.value = true
                self?.cleanupConnection(id: connectionId)
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Check if the "not permitted" error is happening
    func diagnoseScreenSharingError(for ipAddress: String) async -> ConnectionError? {
        // First check if port is even open
        let portOpen = await testConnection(to: ipAddress, port: 5900)
        
        if !portOpen {
            return .remoteServiceDown
        }
        
        // Try to do a VNC handshake to see if we get rejected
        // The "not permitted" error happens at the protocol level, not connection level
        // For now, we can't easily detect it programmatically before attempting
        // but we can check if TidalDrift is running on that machine
        
        let tidalDriftRunning = await testConnection(to: ipAddress, port: 5901)
        
        if !tidalDriftRunning {
            // TidalDrift not running, can't remotely fix
            return nil
        }
        
        return nil
    }
}
