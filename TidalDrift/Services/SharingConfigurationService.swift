import Foundation
import Combine
import AppKit
import Network
import os.log

private let logger = Logger(subsystem: "com.tidaldrift", category: "SharingConfig")

class SharingConfigurationService: ObservableObject {
    static let shared = SharingConfigurationService()
    
    @Published var screenSharingEnabled: Bool = false
    @Published var fileSharingEnabled: Bool = false
    @Published var remoteLoginEnabled: Bool = false
    
    private init() {
        Task {
            await refreshStatus()
        }
    }
    
    @MainActor
    func refreshStatus() async {
        screenSharingEnabled = await isScreenSharingEnabled()
        fileSharingEnabled = await isFileSharingEnabled()
        remoteLoginEnabled = await isRemoteLoginEnabled()
    }
    
    func isScreenSharingEnabled() async -> Bool {
        // Try multiple methods to detect screen sharing status
        
        // Method 1: Check if screensharing service is loaded via launchctl print
        let method1 = await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["print", "system/com.apple.screensharing"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
        
        if method1 { return true }
        
        // Method 2: Check via system_profiler
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            task.arguments = ["SPConfigurationProfileDataType", "-json"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            do {
                try task.run()
                task.waitUntilExit()
                
                // Also check if the VNC port is listening
                let netstatTask = Process()
                netstatTask.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                netstatTask.arguments = ["-i", ":5900", "-sTCP:LISTEN"]
                
                let netstatPipe = Pipe()
                netstatTask.standardOutput = netstatPipe
                netstatTask.standardError = Pipe()
                
                try netstatTask.run()
                netstatTask.waitUntilExit()
                
                let data = netstatPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: !output.isEmpty)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    func isFileSharingEnabled() async -> Bool {
        // Try multiple methods to detect file sharing status
        
        // Method 1: Check if smbd service is loaded
        let method1 = await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["print", "system/com.apple.smbd"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
        
        if method1 { return true }
        
        // Method 2: Check if SMB port 445 is listening
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            task.arguments = ["-i", ":445", "-sTCP:LISTEN"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: !output.isEmpty)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    func isRemoteLoginEnabled() async -> Bool {
        logger.info("Checking Remote Login status...")
        
        // Method 1: Check by testing local port 22
        let portCheck = await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host("127.0.0.1")
            let port = NWEndpoint.Port(rawValue: 22)!
            let connection = NWConnection(host: host, port: port, using: .tcp)
            
            var didResume = false
            connection.stateUpdateHandler = { state in
                guard !didResume else { return }
                if case .ready = state {
                    logger.info("Port 22 check: OPEN (connection ready)")
                    didResume = true
                    connection.cancel()
                    continuation.resume(returning: true)
                } else if case .failed(let error) = state {
                    logger.info("Port 22 check: CLOSED (failed: \(error))")
                    didResume = true
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
            
            connection.start(queue: .global())
            
            // 2.0 second timeout for local check (SSH can be slow to start)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                guard !didResume else { return }
                logger.info("Port 22 check: TIMEOUT")
                didResume = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
        
        if portCheck {
            logger.info("Result: SSH ENABLED (port check passed)")
            return true
        }
        
        // Method 2: Check via launchctl list as fallback
        let launchctlCheck = await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["list"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let found = output.contains("com.openssh.sshd")
                logger.info("launchctl list check: \(found ? "FOUND com.openssh.sshd" : "NOT FOUND")")
                continuation.resume(returning: found)
            } catch {
                logger.error("launchctl list check: ERROR - \(error)")
                continuation.resume(returning: false)
            }
        }
        
        logger.info("Result: SSH \(launchctlCheck ? "ENABLED" : "DISABLED") (launchctl fallback)")
        return launchctlCheck
    }
    
    func isFirewallEnabled() async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
            task.arguments = ["--getglobalstate"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                // Output is "Firewall is enabled. (State = 1)" or "Firewall is disabled. (State = 0)"
                continuation.resume(returning: output.lowercased().contains("enabled"))
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    func isFirewallBlockingAll() async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
            task.arguments = ["--getblockall"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output.lowercased().contains("enabled"))
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Toggle Sharing Services
    
    /// Ensure screen sharing is enabled - quick fix for connection issues
    func ensureScreenSharingEnabled() async -> Bool {
        // First check if it's already enabled
        let isEnabled = await isScreenSharingEnabled()
        if isEnabled {
            return true
        }
        
        // Try to enable it
        return await toggleScreenSharing(enable: true)
    }
    
    /// Quick fix: restart screen sharing service
    func restartScreenSharing() async -> Bool {
        // Disable then enable to restart the service
        let script = """
        do shell script "launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null; launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist" with administrator privileges
        """
        let result = await runAppleScript(script)
        
        // Refresh status after
        await refreshStatus()
        return result
    }
    
    func toggleScreenSharing(enable: Bool) async -> Bool {
        let script: String
        if enable {
            script = """
            do shell script "launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist" with administrator privileges
            """
        } else {
            script = """
            do shell script "launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist" with administrator privileges
            """
        }
        
        let result = await runAppleScript(script)
        await refreshStatus()
        return result
    }
    
    func toggleFileSharing(enable: Bool) async -> Bool {
        let script: String
        if enable {
            script = """
            do shell script "launchctl load -w /System/Library/LaunchDaemons/com.apple.smbd.plist" with administrator privileges
            """
        } else {
            script = """
            do shell script "launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist" with administrator privileges
            """
        }
        
        return await runAppleScript(script)
    }
    
    func toggleRemoteLogin(enable: Bool) async -> Bool {
        let screenshareUser = UserDefaults.standard.string(forKey: "screenShareUsername")
        
        logger.info("toggleRemoteLogin called - enable: \(enable), user: \(screenshareUser ?? "none")")
        
        // Check current state first
        let currentState = await isRemoteLoginEnabled()
        logger.info("Current SSH state: \(currentState)")
        
        // Use launchctl approach instead of systemsetup (which requires Full Disk Access)
        let script: String
        
        if enable {
            // Enable SSH using launchctl bootstrap
            var command = "launchctl bootout system/com.openssh.sshd 2>/dev/null; launchctl enable system/com.openssh.sshd; launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist"
            
            // Also add user to SSH access group if specified
            if let user = screenshareUser {
                command += " && dseditgroup -o edit -a \(user) -t user com.apple.access_ssh 2>/dev/null"
            }
            
            script = """
            do shell script "\(command)" with administrator privileges
            """
        } else {
            // Disable SSH using launchctl bootout
            script = """
            do shell script "launchctl bootout system/com.openssh.sshd" with administrator privileges
            """
        }
        
        logger.info("Executing Remote Login configuration via launchctl...")
        let result = await runAppleScript(script)
        
        if result {
            logger.info("Remote Login launchctl command SUCCESS")
        } else {
            logger.error("Remote Login launchctl command FAILURE (user cancelled or error)")
        }
        
        // Wait a moment for system to settle
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Verify the new state
        let newState = await isRemoteLoginEnabled()
        logger.info("New SSH state after command: \(newState)")
        
        if enable && !newState {
            logger.warning("SSH was supposed to be enabled but port 22 is not responding - may be timing issue")
        }
        
        await refreshStatus()
        return result
    }
    
    func authorizeUserForSSH(username: String) async -> Bool {
        // This is now mostly handled by the combined script in toggleRemoteLogin,
        // but keeping it as a standalone utility if needed.
        let script = """
        do shell script "dseditgroup -o edit -a \(username) -t user com.apple.access_ssh" with administrator privileges
        """
        return await runAppleScript(script)
    }
    
    private func runAppleScript(_ source: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", source]
            
            // Capture output for debugging
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe
            
            logger.info("Running AppleScript: \(source.prefix(150))...")
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                
                logger.info("osascript exit code: \(task.terminationStatus)")
                if !stdout.isEmpty {
                    logger.info("osascript stdout: \(stdout, privacy: .public)")
                }
                if !stderr.isEmpty {
                    logger.error("osascript stderr: \(stderr, privacy: .public)")
                }
                
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                logger.error("Failed to run osascript: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Public method to execute arbitrary AppleScript (for user creation, etc.)
    func executeAppleScript(_ source: String) async -> Bool {
        return await runAppleScript(source)
    }
    
    // MARK: - Open Settings
    
    func openScreenSharingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.sharing?Services_ScreenSharing")!
        NSWorkspace.shared.open(url)
    }
    
    func openFileSharingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.sharing?Services_PersonalFileSharing")!
        NSWorkspace.shared.open(url)
    }
    
    func openFirewallSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Firewall")!
        NSWorkspace.shared.open(url)
    }
    
    func openSharingPreferences() {
        if #available(macOS 13.0, *) {
            let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")!
            NSWorkspace.shared.open(url)
        } else {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.sharing")!
            NSWorkspace.shared.open(url)
        }
    }
    
    func getComputerName() -> String {
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }
    
    func getLocalIPAddresses() -> [String] {
        var addresses: [String] = []
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return addresses
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
                    addresses.append(String(cString: hostname))
                }
            }
            
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        
        return addresses
    }
}
