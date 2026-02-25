import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

extension TidalDriftTestRunner {
    
    func testScreenRecordingPermission() async -> (Bool, String) {
        let granted = CGPreflightScreenCaptureAccess()
        return (granted, granted
            ? "Screen Recording permission granted"
            : "Not granted — go to System Settings > Privacy > Screen Recording")
    }
    
    func testAccessibilityPermission() async -> (Bool, String) {
        let granted = AXIsProcessTrusted()
        return (granted, granted
            ? "Accessibility permission granted"
            : "Not granted — go to System Settings > Privacy > Accessibility")
    }
    
    func testLocalNetworkIP() async -> (Bool, String) {
        guard let ip = NetworkUtils.getLocalIPAddress(), !ip.isEmpty, ip != "Unknown" else {
            return (false, "No local IP address found — check Wi-Fi/Ethernet connection")
        }
        return (true, "Local IP: \(ip)")
    }
}
