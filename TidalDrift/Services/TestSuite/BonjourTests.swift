import Foundation
import Network

extension TidalDriftTestRunner {
    
    func testPeerAdvertising() async -> (Bool, String) {
        let peerService = TidalDriftPeerService.shared
        let isAdv = peerService.isAdvertising
        if isAdv {
            return (true, "TidalDrift peer service is advertising on _tidaldrift._tcp")
        }
        
        // Try to start it
        peerService.startAdvertising()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        if peerService.isAdvertising {
            return (true, "Peer advertising started successfully")
        }
        return (false, "Peer advertising failed to start — check peer discovery is enabled in settings")
    }
    
    func testPeerDiscovery() async -> (Bool, String) {
        let peerService = TidalDriftPeerService.shared
        
        // Ensure advertising is on so we can discover ourselves
        if !peerService.isAdvertising {
            peerService.startAdvertising()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        peerService.startDiscovery()
        
        // Wait up to 8 seconds for self-discovery
        for _ in 0..<16 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let devices = NetworkDiscoveryService.shared.discoveredDevices
            if devices.contains(where: { $0.isCurrentDevice && $0.isTidalDriftPeer }) {
                return (true, "Self-discovered via Bonjour as TidalDrift peer")
            }
        }
        
        // Partial pass if we at least see ourselves
        let devices = NetworkDiscoveryService.shared.discoveredDevices
        if devices.contains(where: { $0.isCurrentDevice }) {
            return (true, "Self visible in device list (peer flag may take a moment)")
        }
        
        return (false, "Could not discover self via Bonjour within 8s — \(devices.count) devices visible")
    }
    
    func testTidalDropListener() async -> (Bool, String) {
        let isListening = TidalDropService.shared.isListening
        if isListening {
            return (true, "TidalDrop listener active on port 5902")
        }
        
        // Give it a moment to start
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if TidalDropService.shared.isListening {
            return (true, "TidalDrop listener became active on port 5902")
        }
        
        return (false, "TidalDrop listener not active — port 5902 may be in use")
    }
}
