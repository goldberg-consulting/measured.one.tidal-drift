import Foundation
import AppKit
import ScreenCaptureKit
import ApplicationServices
import CoreGraphics
import OSLog

@MainActor
class LocalCastPermissions: ObservableObject {
    private let logger = Logger(subsystem: "com.tidaldrift", category: "Permissions")

    @Published var screenCaptureGranted = false
    @Published var accessibilityGranted = false

    var allPermissionsGranted: Bool {
        screenCaptureGranted && accessibilityGranted
    }

    /// Passive check -- reads current permission state without triggering any prompts.
    /// Safe to call from views, timers, etc.
    func checkPermissions() async {
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// Request screen capture permission. Triggers the system dialog the first time;
    /// after the user has responded, just returns the current status.
    /// Only call this in response to an explicit user action (e.g. toggling Screen Streaming).
    func requestScreenCaptureIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            screenCaptureGranted = true
            return true
        }
        let granted = CGRequestScreenCaptureAccess()
        screenCaptureGranted = granted
        return granted
    }

    /// Open System Settings to the Screen Recording privacy pane.
    func openScreenCapturePreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Prompt the user for Accessibility permission (triggers the system dialog).
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
