import Foundation
import Combine

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
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["list", "com.apple.screensharing"]
            
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
    }
    
    func isFileSharingEnabled() async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["list", "com.apple.smbd"]
            
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
