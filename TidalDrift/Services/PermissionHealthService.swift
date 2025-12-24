import Foundation
import ScreenCaptureKit

/// Self-healing permission service that detects and fixes stuck permissions
class PermissionHealthService: ObservableObject {
    static let shared = PermissionHealthService()
    
    // MARK: - Published State
    
    @Published var lastHealthCheck: HealthCheckResult?
    @Published var isRunningHealthCheck: Bool = false
    @Published var isFixingPermissions: Bool = false
    
    // Log file for debugging
    private let logFileURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("TidalDrift_PermissionHealth.log")
    }()
    
    private init() {}
    
    // MARK: - Health Check Result
    
    struct HealthCheckResult {
        let timestamp: Date
        var screenSharing: ServiceHealth
        var screenRecording: ServiceHealth
        var localNetwork: ServiceHealth
        var needsAutoFix: Bool
        var fixAttempted: Bool = false
        var fixSucceeded: Bool = false
        
        struct ServiceHealth {
            let name: String
            let enabledInSettings: Bool
            let actuallyWorking: Bool
            let isStuck: Bool // enabled but not working
            let details: String
            
            var status: Status {
                if actuallyWorking { return .working }
                if isStuck { return .stuck }
                if !enabledInSettings { return .disabled }
                return .unknown
            }
            
            enum Status: String {
                case working = "✅ Working"
                case stuck = "⚠️ Stuck (enabled but not working)"
                case disabled = "⭕ Disabled"
                case unknown = "❓ Unknown"
            }
        }
    }
    
    // MARK: - Health Check
    
    /// Run a complete health check on all permissions
    @MainActor
    func runHealthCheck() async -> HealthCheckResult {
        isRunningHealthCheck = true
        defer { isRunningHealthCheck = false }
        
        log("========== HEALTH CHECK STARTED ==========")
        log("Timestamp: \(Date())")
        
        // Check Screen Sharing
        let screenSharing = await checkScreenSharingHealth()
        log("Screen Sharing: enabled=\(screenSharing.enabledInSettings), working=\(screenSharing.actuallyWorking), stuck=\(screenSharing.isStuck)")
        
        // Check Screen Recording
        let screenRecording = await checkScreenRecordingHealth()
        log("Screen Recording: enabled=\(screenRecording.enabledInSettings), working=\(screenRecording.actuallyWorking), stuck=\(screenRecording.isStuck)")
        
        // Check Local Network
        let localNetwork = await checkLocalNetworkHealth()
        log("Local Network: enabled=\(localNetwork.enabledInSettings), working=\(localNetwork.actuallyWorking), stuck=\(localNetwork.isStuck)")
        
        let needsAutoFix = screenSharing.isStuck || screenRecording.isStuck || localNetwork.isStuck
        log("Needs auto-fix: \(needsAutoFix)")
        
        let result = HealthCheckResult(
            timestamp: Date(),
            screenSharing: screenSharing,
            screenRecording: screenRecording,
            localNetwork: localNetwork,
            needsAutoFix: needsAutoFix
        )
        
        lastHealthCheck = result
        log("========== HEALTH CHECK COMPLETE ==========")
        
        return result
    }
    
    // MARK: - Individual Health Checks
    
    private func checkScreenSharingHealth() async -> HealthCheckResult.ServiceHealth {
        // Check if service is loaded (enabled in settings)
        let serviceLoaded = await isScreenSharingServiceLoaded()
        
        // Check if port is actually listening (working)
        let portListening = await isPortListening(5900)
        
        let isStuck = serviceLoaded && !portListening
        
        return HealthCheckResult.ServiceHealth(
            name: "Screen Sharing",
            enabledInSettings: serviceLoaded,
            actuallyWorking: portListening,
            isStuck: isStuck,
            details: isStuck ? "Service loaded but port 5900 not listening" : (portListening ? "Port 5900 listening" : "Service not loaded")
        )
    }
    
    private func checkScreenRecordingHealth() async -> HealthCheckResult.ServiceHealth {
        // For screen recording, we can only really test by trying to use it
        var granted = false
        var actuallyWorks = false
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            granted = true
            actuallyWorks = !content.windows.isEmpty
        } catch {
            // If we get here, permission is either denied or not determined
            granted = false
            actuallyWorks = false
        }
        
        // Screen Recording can be "granted" in TCC but still not work if the app signature changed
        let isStuck = granted && !actuallyWorks
        
        return HealthCheckResult.ServiceHealth(
            name: "Screen Recording",
            enabledInSettings: granted,
            actuallyWorking: actuallyWorks,
            isStuck: isStuck,
            details: actuallyWorks ? "Can capture windows" : (granted ? "Permission granted but can't capture" : "Permission not granted")
        )
    }
    
    private func checkLocalNetworkHealth() async -> HealthCheckResult.ServiceHealth {
        // Local Network is tricky - we can test by trying to bind a port
        let canBind = await canBindLocalPort()
        
        // We assume it's enabled if we got this far (app launched)
        // Stuck would be if Bonjour operations fail with NoAuth
        
        return HealthCheckResult.ServiceHealth(
            name: "Local Network",
            enabledInSettings: true, // Hard to detect without triggering prompt
            actuallyWorking: canBind,
            isStuck: false, // We handle this separately via error codes
            details: canBind ? "Can bind local ports" : "Cannot bind local ports"
        )
    }
    
    // MARK: - Auto-Fix
    
    /// Attempt to automatically fix stuck permissions
    @MainActor
    func autoFixStuckPermissions() async -> Bool {
        guard let healthCheck = lastHealthCheck, healthCheck.needsAutoFix else {
            log("Auto-fix skipped: No stuck permissions detected")
            return true
        }
        
        isFixingPermissions = true
        defer { isFixingPermissions = false }
        
        log("========== AUTO-FIX STARTED ==========")
        log("Stuck services: Screen Sharing=\(healthCheck.screenSharing.isStuck), Screen Recording=\(healthCheck.screenRecording.isStuck)")
        
        var allFixed = true
        
        // Fix Screen Sharing if stuck
        if healthCheck.screenSharing.isStuck {
            log("Attempting to fix Screen Sharing...")
            let fixed = await fixScreenSharing()
            log("Screen Sharing fix result: \(fixed)")
            allFixed = allFixed && fixed
        }
        
        // Fix Screen Recording if stuck (requires user interaction)
        if healthCheck.screenRecording.isStuck {
            log("Screen Recording is stuck - requires manual reset")
            // Reset the TCC entry to force re-prompt
            let _ = await resetScreenRecordingPermission()
            allFixed = false // User needs to re-grant
        }
        
        // Update health check result
        var updatedResult = healthCheck
        updatedResult.fixAttempted = true
        updatedResult.fixSucceeded = allFixed
        lastHealthCheck = updatedResult
        
        log("========== AUTO-FIX COMPLETE ==========")
        log("All fixed: \(allFixed)")
        
        return allFixed
    }
    
    /// Fix stuck Screen Sharing by toggling the service
    private func fixScreenSharing() async -> Bool {
        log("Toggling Screen Sharing service...")
        
        // Method 1: Try kickstart (needs admin)
        let kickstartResult = ShellExecutor.execute("""
            osascript -e 'do shell script "launchctl kickstart -k system/com.apple.screensharing" with administrator privileges' 2>&1
        """)
        
        if kickstartResult.exitCode == 0 {
            // Wait for service to restart
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            // Verify it's working now
            let working = await isPortListening(5900)
            log("Kickstart result: port listening = \(working)")
            return working
        }
        
        // Method 2: Use System Events to toggle via GUI
        log("Kickstart failed, trying GUI toggle...")
        let guiResult = await toggleScreenSharingViaGUI()
        
        // Wait and verify
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let working = await isPortListening(5900)
        log("GUI toggle result: port listening = \(working)")
        
        return working
    }
    
    private func toggleScreenSharingViaGUI() async -> Bool {
        let script = """
        tell application "System Preferences"
            reveal anchor "Services_ScreenSharing" of pane id "com.apple.preferences.sharing"
            activate
        end tell
        
        delay 1
        
        tell application "System Events"
            tell process "System Preferences"
                try
                    -- Find Screen Sharing checkbox and toggle it
                    set screenSharingCheckbox to checkbox 1 of row 1 of table 1 of scroll area 1 of group 1 of window 1
                    
                    -- Turn off
                    if value of screenSharingCheckbox is 1 then
                        click screenSharingCheckbox
                        delay 2
                        -- Turn back on
                        click screenSharingCheckbox
                    end if
                end try
            end tell
        end tell
        
        delay 1
        tell application "System Preferences" to quit
        
        return true
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            return error == nil
        }
        return false
    }
    
    private func resetScreenRecordingPermission() async -> Bool {
        let result = ShellExecutor.execute("tccutil reset ScreenCapture com.goldbergconsulting.tidaldrift 2>&1")
        log("Screen Recording permission reset: \(result.exitCode == 0)")
        return result.exitCode == 0
    }
    
    // MARK: - Helper Methods
    
    private func isScreenSharingServiceLoaded() async -> Bool {
        let result = ShellExecutor.execute("launchctl print system/com.apple.screensharing 2>&1")
        return result.output.contains("state = running")
    }
    
    private func isPortListening(_ port: Int) async -> Bool {
        let result = ShellExecutor.execute("lsof -i :\(port) -sTCP:LISTEN 2>/dev/null")
        return !result.output.isEmpty
    }
    
    private func canBindLocalPort() async -> Bool {
        // Try to bind a random high port to test network permissions
        let testPort = Int.random(in: 50000...59999)
        let result = ShellExecutor.execute("""
            python3 -c "import socket; s=socket.socket(); s.bind(('', \(testPort))); s.close(); print('OK')" 2>&1
        """)
        return result.output.contains("OK")
    }
    
    // MARK: - Logging
    
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        
        #if DEBUG
        print("🏥 PermissionHealth: \(message)")
        #endif
        
        // Append to log file
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
    
    /// Get the log file contents for debugging
    func getLogContents() -> String {
        (try? String(contentsOf: logFileURL)) ?? "No logs available"
    }
    
    /// Clear the log file
    func clearLog() {
        try? FileManager.default.removeItem(at: logFileURL)
    }
}

// MARK: - Onboarding Integration

extension PermissionHealthService {
    
    /// Run health check and auto-fix during app startup/onboarding
    /// Returns true if everything is working, false if user intervention needed
    @MainActor
    func performStartupHealthCheck() async -> Bool {
        log("========== STARTUP HEALTH CHECK ==========")
        
        // Run initial health check
        let result = await runHealthCheck()
        
        // If nothing is stuck, we're good
        if !result.needsAutoFix {
            log("All permissions healthy, no fix needed")
            return true
        }
        
        // Attempt auto-fix
        log("Stuck permissions detected, attempting auto-fix...")
        let fixed = await autoFixStuckPermissions()
        
        if fixed {
            log("Auto-fix successful")
            return true
        }
        
        // Run another health check to see current state
        let _ = await runHealthCheck()
        
        log("Auto-fix incomplete, user intervention may be needed")
        return false
    }
}


