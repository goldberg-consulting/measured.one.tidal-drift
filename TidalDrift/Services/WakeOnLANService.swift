import Foundation
import Network

/// Service for sending Wake-on-LAN magic packets to wake sleeping Macs
class WakeOnLANService {
    static let shared = WakeOnLANService()
    
    private init() {}
    
    // MARK: - Magic Packet Generation
    
    /// Wake a device using its MAC address
    /// - Parameters:
    ///   - macAddress: MAC address in format "AA:BB:CC:DD:EE:FF" or "AA-BB-CC-DD-EE-FF"
    ///   - broadcastAddress: Broadcast address (default: 255.255.255.255)
    ///   - port: WOL port (uses settings if nil)
    /// - Returns: True if packet was sent successfully
    func wake(macAddress: String, broadcastAddress: String = "255.255.255.255", port: UInt16? = nil) async -> Bool {
        // Check if WOL is enabled in settings
        let settings = AppState.shared.settings
        guard settings.wakeOnLANEnabled else {
            return false
        }
        
        guard let macBytes = parseMACAddress(macAddress) else {
            return false
        }
        
        let wolPort = port ?? UInt16(settings.wakeOnLANPort)
        let retries = settings.wakeOnLANRetries
        
        let magicPacket = createMagicPacket(macBytes: macBytes)
        
        // Send multiple packets based on retry setting
        var success = false
        for _ in 0..<retries {
            if await sendPacket(magicPacket, to: broadcastAddress, port: wolPort) {
                success = true
            }
            // Small delay between retries
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        return success
    }
    
    /// Wake a device and wait for it to come online
    /// - Parameters:
    ///   - macAddress: MAC address
    ///   - ipAddress: Expected IP address to ping
    ///   - timeout: Maximum time to wait (seconds)
    /// - Returns: True if device came online within timeout
    func wakeAndWait(macAddress: String, ipAddress: String, timeout: TimeInterval = 60) async -> Bool {
        // Send wake packet
        guard await wake(macAddress: macAddress) else {
            return false
        }
        
        // Wait for device to come online
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            // Check if device is responding
            if await NetworkDiscoveryService.shared.scanIP(ipAddress, port: 5900) {
                return true
            }
            
            // Wait before retrying
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
        
        return false
    }
    
    /// Check if Wake-on-LAN is enabled in settings
    var isEnabled: Bool {
        AppState.shared.settings.wakeOnLANEnabled
    }
    
    /// Check if auto-wake before connect is enabled
    var shouldAutoWakeBeforeConnect: Bool {
        let settings = AppState.shared.settings
        return settings.wakeOnLANEnabled && settings.autoWakeBeforeConnect
    }
    
    // MARK: - MAC Address Parsing
    
    private func parseMACAddress(_ mac: String) -> [UInt8]? {
        // Support both ":" and "-" separators
        let cleanMAC = mac.replacingOccurrences(of: "-", with: ":")
        let parts = cleanMAC.split(separator: ":")
        
        guard parts.count == 6 else { return nil }
        
        var bytes: [UInt8] = []
        for part in parts {
            guard let byte = UInt8(part, radix: 16) else { return nil }
            bytes.append(byte)
        }
        
        return bytes
    }
    
    /// Validate MAC address format
    func isValidMACAddress(_ mac: String) -> Bool {
        return parseMACAddress(mac) != nil
    }
    
    /// Format MAC address consistently
    func formatMACAddress(_ mac: String) -> String? {
        guard let bytes = parseMACAddress(mac) else { return nil }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
    
    // MARK: - Magic Packet Creation
    
    private func createMagicPacket(macBytes: [UInt8]) -> Data {
        var packet = Data()
        
        // Magic packet header: 6 bytes of 0xFF
        for _ in 0..<6 {
            packet.append(0xFF)
        }
        
        // Followed by MAC address repeated 16 times
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        
        return packet
    }
    
    // MARK: - Network Transmission
    
    private func sendPacket(_ packet: Data, to address: String, port: UInt16) async -> Bool {
        return await withCheckedContinuation { continuation in
            // Create UDP socket
            var sock: Int32 = -1
            
            sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard sock >= 0 else {
                continuation.resume(returning: false)
                return
            }
            
            defer { close(sock) }
            
            // Enable broadcast
            var broadcastEnable: Int32 = 1
            let optResult = setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))
            guard optResult >= 0 else {
                continuation.resume(returning: false)
                return
            }
            
            // Setup destination address
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr(address)
            
            // Send packet
            let sent = packet.withUnsafeBytes { buffer -> Int in
                withUnsafePointer(to: &addr) { addrPtr -> Int in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr -> Int in
                        sendto(sock, buffer.baseAddress, buffer.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            
            continuation.resume(returning: sent == packet.count)
        }
    }
    
    // MARK: - MAC Address Discovery
    
    /// Get MAC address from IP using ARP table
    func getMACAddress(for ipAddress: String) -> String? {
        let result = ShellExecutor.execute("arp -n \(ipAddress)")
        
        // Parse ARP output: "? (192.168.1.100) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]"
        let pattern = "([0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2})"
        
        if let range = result.output.range(of: pattern, options: .regularExpression) {
            let mac = String(result.output[range])
            return formatMACAddress(mac)
        }
        
        return nil
    }
    
    /// Scan network and get MAC addresses for all discovered devices
    func discoverMACAddresses() -> [String: String] {
        // First, ping the broadcast to populate ARP table
        _ = ShellExecutor.execute("ping -c 1 -t 1 255.255.255.255 2>/dev/null")
        
        // Get ARP table
        let result = ShellExecutor.execute("arp -a")
        
        var macAddresses: [String: String] = [:]
        let lines = result.output.split(separator: "\n")
        
        for line in lines {
            // Parse: "? (192.168.1.100) at aa:bb:cc:dd:ee:ff on en0"
            let lineStr = String(line)
            
            // Extract IP
            if let ipRange = lineStr.range(of: "\\([0-9.]+\\)", options: .regularExpression) {
                var ip = String(lineStr[ipRange])
                ip = ip.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                
                // Extract MAC
                if let macRange = lineStr.range(of: "([0-9a-fA-F]{1,2}:){5}[0-9a-fA-F]{1,2}", options: .regularExpression) {
                    let mac = String(lineStr[macRange])
                    if let formatted = formatMACAddress(mac) {
                        macAddresses[ip] = formatted
                    }
                }
            }
        }
        
        return macAddresses
    }
}

// MARK: - DiscoveredDevice Extension

extension DiscoveredDevice {
    /// Store MAC address in UserDefaults
    var storedMACAddress: String? {
        get {
            UserDefaults.standard.string(forKey: "mac_\(ipAddress)")
        }
        set {
            if let mac = newValue {
                UserDefaults.standard.set(mac, forKey: "mac_\(ipAddress)")
            } else {
                UserDefaults.standard.removeObject(forKey: "mac_\(ipAddress)")
            }
        }
    }
    
    /// Check if device supports Wake-on-LAN
    var supportsWOL: Bool {
        storedMACAddress != nil
    }
}

