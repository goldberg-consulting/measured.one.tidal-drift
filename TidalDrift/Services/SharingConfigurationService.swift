import Foundation
import Combine
import AppKit

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
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/systemsetup")
            task.arguments = ["-getremotelogin"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output.lowercased().contains("on"))
            } catch {
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
        
        return await runAppleScript(script)
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
