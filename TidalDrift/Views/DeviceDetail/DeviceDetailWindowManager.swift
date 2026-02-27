import SwiftUI
import AppKit

/// Manages standalone floating windows for device detail sheets.
/// Each device gets its own window; re-opening brings the existing one to front.
class DeviceDetailWindowManager: NSObject, NSWindowDelegate {
    static let shared = DeviceDetailWindowManager()
    private var windows: [UUID: NSWindow] = [:]
    private var windowToDeviceID: [ObjectIdentifier: UUID] = [:]
    
    func showDetail(for device: DiscoveredDevice) {
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
        window.title = device.displayName
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 450, height: 580))
        window.minSize = NSSize(width: 400, height: 400)
        window.delegate = self
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        windows[device.id] = window
        windowToDeviceID[ObjectIdentifier(window)] = device.id
    }
    
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let deviceID = windowToDeviceID.removeValue(forKey: ObjectIdentifier(window)) {
            windows.removeValue(forKey: deviceID)
        }
    }
    
    func closeAll() {
        for (_, window) in windows { window.close() }
        windows.removeAll()
        windowToDeviceID.removeAll()
    }
}
