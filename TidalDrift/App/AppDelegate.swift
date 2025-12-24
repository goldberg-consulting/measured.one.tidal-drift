import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureAppearance()
        // Auto-start network discovery for screen shares
        NetworkDiscoveryService.shared.startBrowsing()
        // Start TidalDrift peer discovery (advertise + discover other instances)
        TidalDriftPeerService.shared.startAdvertising()
        TidalDriftPeerService.shared.startDiscovery()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NetworkDiscoveryService.shared.stopBrowsing()
        TidalDriftPeerService.shared.stopAdvertising()
        TidalDriftPeerService.shared.stopDiscovery()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    private func configureAppearance() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
