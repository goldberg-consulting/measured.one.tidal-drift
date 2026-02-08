import SwiftUI
import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureAppearance()
        
        // Setup notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Defer network operations to avoid blocking app launch
        // This gives the UI time to render before potentially slow network ops
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Auto-start network discovery for screen shares
            NetworkDiscoveryService.shared.startBrowsing()
            // Start TidalDrift peer discovery (advertise + discover other instances)
            TidalDriftPeerService.shared.startAdvertising()
            TidalDriftPeerService.shared.startDiscovery()
            
            // Ensure TidalDrop service is initialized and listening
            _ = TidalDropService.shared
            
            // Auto-start LocalCast hosting if enabled in preferences
            if UserDefaults.standard.bool(forKey: "localCastAutoHost") {
                print("🌊 LocalCast: Auto-host enabled, starting hosting...")
                Task {
                    do {
                        try await LocalCastService.shared.startHosting()
                        print("🌊 LocalCast: Auto-host started successfully")
                    } catch {
                        print("🌊 LocalCast: Auto-host failed: \(error.localizedDescription)")
                    }
                }
            }
        }
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
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .list, .sound])
    }
}
