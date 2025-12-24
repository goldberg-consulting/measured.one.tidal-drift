import Foundation
import ScreenCaptureKit
import AppKit

/// Comprehensive permission diagnostic and repair service
class PermissionDiagnosticService: ObservableObject {
    static let shared = PermissionDiagnosticService()
    
    // MARK: - Published Status
    
    @Published var screenSharingServiceRunning: Bool = false
    @Published var screenSharingPortOpen: Bool = false
    @Published var screenRecordingGranted: Bool = false
    @Published var localNetworkGranted: Bool = false
    @Published var lastDiagnostic: DiagnosticResult?
    @Published var isRunningDiagnostic: Bool = false
    
    private init() {}
    
    // MARK: - Diagnostic Result
    
    struct DiagnosticResult {
        let timestamp: Date
        var issues: [Issue]
        var recommendations: [String]
        
        struct Issue {
            let category: Category
            let severity: Severity
            let description: String
            let fix: String?
            
            enum Category: String {
                case screenSharing = "Screen Sharing Service"
                case screenRecording = "Screen Recording Permission"
                case localNetwork = "Local Network Access"
                case appSignature = "App Signature"
            }
            
            enum Severity {
                case critical, warning, info
            }
        }
        
        var hasCriticalIssues: Bool {
            issues.contains { $0.severity == .critical }
        }
        
        var hasWarnings: Bool {
            issues.contains { $0.severity == .warning }
        }
    }
    
    // MARK: - Run Full Diagnostic
    
    @MainActor
    func runFullDiagnostic() async -> DiagnosticResult {
        isRunningDiagnostic = true
        defer { isRunningDiagnostic = false }
        
        var issues: [DiagnosticResult.Issue] = []
        var recommendations: [String] = []
        
        // Check 1: Screen Sharing Service
        let serviceStatus = await checkScreenSharingService()
        screenSharingServiceRunning = serviceStatus.isRunning
        screenSharingPortOpen = serviceStatus.portOpen
        
        if !serviceStatus.isRunning {
            issues.append(.init(
                category: .screenSharing,
                severity: .critical,
                description: "Screen Sharing service is not running",
                fix: "Enable in System Settings → General → Sharing → Screen Sharing"
            ))
        } else if !serviceStatus.portOpen {
            issues.append(.init(
                category: .screenSharing,
                severity: .warning,
                description: "Screen Sharing service is running but port 5900 is not listening",
                fix: "Try restarting the Screen Sharing service"
            ))
        }
        
        // Check 2: Screen Recording Permission (TCC)
        let screenRecording = await checkScreenRecordingPermission()
        screenRecordingGranted = screenRecording.granted
        
        if !screenRecording.granted {
            issues.append(.init(
                category: .screenRecording,
                severity: screenRecording.denied ? .critical : .warning,
                description: screenRecording.denied 
                    ? "Screen Recording permission was denied"
                    : "Screen Recording permission not yet granted",
                fix: "Go to System Settings → Privacy & Security → Screen Recording → Enable TidalDrift"
            ))
        }
        
        // Check 3: App Signature Status
        let signatureStatus = checkAppSignature()
        if !signatureStatus.isValid {
            issues.append(.init(
                category: .appSignature,
                severity: .warning,
                description: "App signature may have changed since permissions were granted",
                fix: "Reset permissions and re-grant after rebuilding"
            ))
        }
        
        // Check 4: Multiple TidalDrift installations
        let duplicates = findDuplicateInstallations()
        if duplicates.count > 1 {
            issues.append(.init(
                category: .appSignature,
                severity: .warning,
                description: "Found \(duplicates.count) TidalDrift installations - may cause permission confusion",
                fix: "Use Settings → Maintenance to remove duplicates"
            ))
        }
        
        // Generate recommendations
        if issues.isEmpty {
            recommendations.append("✅ All permissions are correctly configured!")
        } else {
            if issues.contains(where: { $0.category == .screenRecording }) {
                recommendations.append("After granting Screen Recording, quit and restart TidalDrift")
            }
            if issues.contains(where: { $0.category == .screenSharing }) {
                recommendations.append("Use the 'Fix Screen Sharing' button to enable the service")
            }
        }
        
        let result = DiagnosticResult(
            timestamp: Date(),
            issues: issues,
            recommendations: recommendations
        )
        
        lastDiagnostic = result
        return result
    }
    
    // MARK: - Individual Checks
    
    private func checkScreenSharingService() async -> (isRunning: Bool, portOpen: Bool) {
        // Check if service is running
        let serviceRunning = await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["print", "system/com.apple.screensharing"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                // Check for "state = running"
                let isRunning = output.contains("state = running")
                continuation.resume(returning: isRunning)
            } catch {
                continuation.resume(returning: false)
            }
        }
        
        // Check if port 5900 is listening
        let portOpen = await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            task.arguments = ["-i", ":5900", "-sTCP:LISTEN"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: !output.isEmpty)
            } catch {
                continuation.resume(returning: false)
            }
        }
        
        return (serviceRunning, portOpen)
    }
    
    private func checkScreenRecordingPermission() async -> (granted: Bool, denied: Bool) {
        // Try to get content - this is the definitive test
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            // If we get windows, permission is granted
            let hasWindows = !content.windows.isEmpty
            return (hasWindows, false)
        } catch let error as NSError {
            // Error code -3801 means permission denied
            // Error code -3802 means not determined
            if error.code == -3801 {
                return (false, true) // Denied
            }
            return (false, false) // Not determined
        }
    }
    
    private func checkAppSignature() -> (isValid: Bool, identifier: String?) {
        guard let bundlePath = Bundle.main.bundlePath as String? else {
            return (false, nil)
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", bundlePath]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let isValid = task.terminationStatus == 0
            
            // Extract identifier
            var identifier: String?
            if let range = output.range(of: "Identifier=") {
                let start = output[range.upperBound...]
                if let end = start.firstIndex(of: "\n") {
                    identifier = String(start[..<end])
                }
            }
            
            return (isValid, identifier)
        } catch {
            return (false, nil)
        }
    }
    
    private func findDuplicateInstallations() -> [URL] {
        let searchPaths = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            NSHomeDirectory() + "/Desktop",
            NSHomeDirectory() + "/Downloads"
        ]
        
        var installations: [URL] = []
        let fm = FileManager.default
        
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                for item in contents {
                    if item.lastPathComponent.hasPrefix("TidalDrift") && item.lastPathComponent.hasSuffix(".app") {
                        installations.append(item)
                    }
                }
            }
        }
        
        return installations
    }
    
    // MARK: - Fix Actions
    
    /// Reset all TidalDrift TCC permissions (requires app restart)
    func resetAllPermissions() async -> Bool {
        let result = ShellExecutor.execute("tccutil reset All com.goldbergconsulting.tidaldrift 2>&1")
        return result.exitCode == 0
    }
    
    /// Reset just Screen Recording permission
    func resetScreenRecordingPermission() async -> Bool {
        let result = ShellExecutor.execute("tccutil reset ScreenCapture com.goldbergconsulting.tidaldrift 2>&1")
        return result.exitCode == 0
    }
    
    /// Kickstart the Screen Sharing service
    func kickstartScreenSharing() async -> Bool {
        // First try to enable via System Preferences automation
        let script = """
        tell application "System Preferences"
            activate
            set current pane to pane "com.apple.preference.sharing"
        end tell
        
        delay 1
        
        tell application "System Events"
            tell process "System Preferences"
                -- Click on Screen Sharing checkbox if it exists
                try
                    click checkbox 1 of row 1 of table 1 of scroll area 1 of group 1 of window 1
                end try
            end tell
        end tell
        """
        
        // For now, just restart the launchd service
        let result = ShellExecutor.execute("""
            sudo launchctl kickstart -k system/com.apple.screensharing 2>&1 || \
            sudo launchctl enable system/com.apple.screensharing 2>&1
        """)
        
        return result.exitCode == 0
    }
    
    /// Open Screen Recording settings directly
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Open Screen Sharing settings directly
    func openScreenSharingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.sharing?Services_ScreenSharing") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Request screen recording permission by triggering the prompt
    func requestScreenRecordingPermission() async {
        // The only way to trigger the prompt is to actually try to capture
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // Expected - will trigger the permission prompt
        }
    }
}

// MARK: - Why Permissions Are "Sticky"

/*
 UNDERSTANDING macOS PERMISSION BEHAVIOR:
 
 1. TCC (Transparency, Consent, Control) Database
    - Stores app permissions keyed by CODE SIGNATURE, not just bundle ID
    - When you rebuild an app, the signature changes
    - macOS may see the rebuilt app as a "new" app
    - Old permission entries become orphaned
 
 2. Permission Caching
    - macOS caches permission decisions in memory
    - Changes don't take effect until:
      a) The app quits completely (not just closes window)
      b) Sometimes requires logout/login
      c) In rare cases, requires reboot
 
 3. Multiple App Bundles
    - If you have TidalDrift.app, TidalDrift 2.app, etc.
    - Each has its own permission entry
    - Granting permission to wrong one has no effect
 
 4. Sandbox vs Non-Sandbox
    - Sandboxed apps have different permission requirements
    - Switching sandbox status invalidates previous permissions
 
 SOLUTIONS:
 
 a) For Development:
    - Use: tccutil reset ScreenCapture com.goldbergconsulting.tidaldrift
    - Quit and restart the app
    - Grant permission when prompted
 
 b) For Production:
    - Sign with a stable Developer ID
    - Permissions persist across updates
    - Use proper entitlements
 
 c) Quick Fixes:
    - Quit all TidalDrift instances: pkill -f TidalDrift
    - Reset permission: tccutil reset ScreenCapture com.goldbergconsulting.tidaldrift
    - Restart app and grant when prompted
*/

