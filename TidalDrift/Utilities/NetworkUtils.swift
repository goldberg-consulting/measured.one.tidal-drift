import Foundation
import Network
import SystemConfiguration

struct NetworkUtils {
    
    static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // Skip loopback
                if name != "lo0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    
                    // Prefer en0 (Wi-Fi) but accept any valid local IP
                    if name == "en0" {
                        return ip
                    }
                    if address == nil {
                        address = ip
                    }
                }
            }
            
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        
        return address
    }
    
    static func getAllIPAddresses() -> [String: String] {
        var addresses: [String: String] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return addresses
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, socklen_t(0), NI_NUMERICHOST)
                addresses[name] = String(cString: hostname)
            }
            
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        
        return addresses
    }
    
    static func isValidIPAddress(_ string: String) -> Bool {
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()
        
        if inet_pton(AF_INET, string, &sin.sin_addr) == 1 {
            return true
        }
        if inet_pton(AF_INET6, string, &sin6.sin6_addr) == 1 {
            return true
        }
        return false
    }
    
    static func isLocalNetworkAddress(_ address: String) -> Bool {
        guard isValidIPAddress(address) else { return false }
        
        let privateRanges = [
            "10.",
            "172.16.", "172.17.", "172.18.", "172.19.",
            "172.20.", "172.21.", "172.22.", "172.23.",
            "172.24.", "172.25.", "172.26.", "172.27.",
            "172.28.", "172.29.", "172.30.", "172.31.",
            "192.168.",
            "169.254."
        ]
        
        return privateRanges.contains { address.hasPrefix($0) }
    }
    
    static func getSubnetMask(for interfaceName: String = "en0") -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let name = String(cString: interface.ifa_name)
            
            if name == interfaceName && interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                if let netmask = interface.ifa_netmask {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(netmask, socklen_t(netmask.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
                    return String(cString: hostname)
                }
            }
            
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        
        return nil
    }
    
    static func getCurrentWiFiSSID() -> String? {
        // Use CoreWLAN for macOS WiFi SSID detection
        guard let interface = CWWiFiClient.shared().interface() else {
            return nil
        }
        return interface.ssid()
    }
    
    static func isNetworkAvailable() -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let reachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return false
        }
        
        var flags: SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(reachability, &flags) {
            return false
        }
        
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        
        return isReachable && !needsConnection
    }
    
    static func getBroadcastAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return "255.255.255.255"
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // Filter for Wi-Fi (en0/en1) or Ethernet (en0/en1/en2...)
                if name.hasPrefix("en") || name.hasPrefix("eth") {
                    if let dstaddr = interface.ifa_dstaddr {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(dstaddr, socklen_t(dstaddr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, socklen_t(0), NI_NUMERICHOST)
                        let address = String(cString: hostname)
                        if address != "0.0.0.0" && address != "127.0.0.1" {
                            return address
                        }
                    }
                }
            }
            
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        
        return "255.255.255.255"
    }
    
    static func getMACAddress(for interfaceName: String = "en0") -> String? {
        return nil
    }
}

import CoreWLAN
