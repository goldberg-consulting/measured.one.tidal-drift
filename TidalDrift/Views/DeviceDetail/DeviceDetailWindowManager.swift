import SwiftUI
import AppKit

/// Manages standalone floating windows for device detail sheets.
/// Each device gets its own window; re-opening brings the existing one to front.
class DeviceDetailWindowManager {
    static let shared = DeviceDetailWindowManager()
    private var windows: [UUID: NSWindow] = [:]
    
    func showDetail(for device: DiscoveredDevice) {
        // Reuse existing window for this device if open
        if let existing = windows[device.id], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let detailView = DeviceDetailSheet(device: device)
            .environmentObject(AppState.shared)
        
        let hostingView = NSHostingView(rootView: detailView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 580),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = device.name
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 450, height: 580))
        window.minSize = NSSize(width: 400, height: 400)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        windows[device.id] = window
    }
    
    func closeAll() {
        for (_, window) in windows {
            window.close()
        }
        windows.removeAll()
    }
}
