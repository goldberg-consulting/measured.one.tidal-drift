import Foundation
import Combine
import AppKit
import Network

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
        // Try to check by testing the local port 22
        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host("127.0.0.1")
            let port = NWEndpoint.Port(rawValue: 22)!
            let connection = NWConnection(host: host, port: port, using: .tcp)
            
            var didResume = false
            connection.stateUpdateHandler = { state in
                guard !didResume else { return }
                if case .ready = state {
                    didResume = true
                    connection.cancel()
                    continuation.resume(returning: true)
                } else if case .failed = state {
                    didResume = true
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
            
            connection.start(queue: .global())
            
            // Short timeout for local check
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                guard !didResume else { return }
                didResume = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
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
        let script: String
        if enable {
            script = """
            do shell script "systemsetup -setremotelogin on" with administrator privileges
            """
        } else {
            script = """
            do shell script "systemsetup -setremotelogin off" with administrator privileges
            """
        }
        
        let result = await runAppleScript(script)
        
        // If enabling, also ensure the screenshare user (if exists) is authorized
        if enable && result {
            if let screenshareUser = UserDefaults.standard.string(forKey: "screenShareUsername") {
                let authorized = await authorizeUserForSSH(username: screenshareUser)
                print("🌊 TidalDrift: SSH authorization for '\(screenshareUser)': \(authorized ? "SUCCESS" : "FAILED")")
            }
        }
        
        await refreshStatus()
        return result
    }
    
    func authorizeUserForSSH(username: String) async -> Bool {
        // macOS uses the 'com.apple.access_ssh' group to control SSH access
        let script = """
        do shell script "dseditgroup -o edit -a \(username) -t user com.apple.access_ssh" with administrator privileges
        """
        return await runAppleScript(script)
    }
    
    private func runAppleScript(_ source: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                if let script = NSAppleScript(source: source) {
                    script.executeAndReturnError(&error)
                    if error == nil {
                        continuation.resume(returning: true)
                    } else {
                        continuation.resume(returning: false)
                    }
                } else {
                    continuation.resume(returning: false)
                }
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
