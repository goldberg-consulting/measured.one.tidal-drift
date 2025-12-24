import Foundation

/// Simple permission reset service - no detection, just fixes
class PermissionHealthService: ObservableObject {
    static let shared = PermissionHealthService()
    
    @Published var isResetting: Bool = false
    @Published var lastResetResult: ResetResult?
    
    private init() {}
    
    struct ResetResult {
        let timestamp: Date
        let screenSharingRestarted: Bool
        let screenRecordingReset: Bool
        let localNetworkReset: Bool
        let message: String
    }
    
    // MARK: - Single Fix Button
    
    /// Reset all permissions that tend to get stuck
    @MainActor
    func fixAllPermissions() async -> ResetResult {
        isResetting = true
        defer { isResetting = false }
        
        print("🔧 PermissionHealthService: Starting permission fix...")
        
        var screenSharingOK = false
        var screenRecordingOK = false
        var localNetworkOK = false
        var messages: [String] = []
        
        // 1. Restart Screen Sharing service (doesn't require quit)
        screenSharingOK = await restartScreenSharing()
        if screenSharingOK {
            messages.append("✅ Screen Sharing service restarted")
        } else {
            messages.append("⚠️ Screen Sharing restart needs admin approval")
        }
        
        // 2. Reset Screen Recording permission (will require re-grant)
        screenRecordingOK = resetScreenRecording()
        if screenRecordingOK {
            messages.append("✅ Screen Recording permission reset - please re-grant if prompted")
        } else {
            messages.append("⚠️ Screen Recording reset failed")
        }
        
        // 3. Reset Local Network permission
        localNetworkOK = resetLocalNetwork()
        if localNetworkOK {
            messages.append("✅ Local Network permission reset")
        } else {
            messages.append("⚠️ Local Network reset failed")
        }
        
        let result = ResetResult(
            timestamp: Date(),
            screenSharingRestarted: screenSharingOK,
            screenRecordingReset: screenRecordingOK,
            localNetworkReset: localNetworkOK,
            message: messages.joined(separator: "\n")
        )
        
        lastResetResult = result
        print("🔧 PermissionHealthService: Fix complete - \(messages)")
        
        return result
    }
    
    // MARK: - Individual Fixes
    
    /// Restart Screen Sharing without needing app restart
    func restartScreenSharing() async -> Bool {
        let result = ShellExecutor.execute("""
            osascript -e 'do shell script "launchctl kickstart -k system/com.apple.screensharing" with administrator privileges' 2>&1
        """)
        return result.exitCode == 0
    }
    
    /// Reset Screen Recording TCC entry
    func resetScreenRecording() -> Bool {
        let result = ShellExecutor.execute("tccutil reset ScreenCapture com.goldbergconsulting.tidaldrift 2>&1")
        return result.exitCode == 0
    }
    
    /// Reset Local Network TCC entry
    func resetLocalNetwork() -> Bool {
        let result = ShellExecutor.execute("tccutil reset LocalNetwork com.goldbergconsulting.tidaldrift 2>&1")
        return result.exitCode == 0
    }
    
    /// Just restart Screen Sharing (quick fix for connection issues)
    @MainActor
    func quickFixScreenSharing() async -> Bool {
        isResetting = true
        defer { isResetting = false }
        
        print("🔧 Quick fix: Restarting Screen Sharing service...")
        return await restartScreenSharing()
    }
}
