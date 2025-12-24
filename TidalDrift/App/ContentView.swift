import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var healthService = PermissionHealthService.shared
    @State private var showHealthAlert = false
    @State private var healthAlertMessage = ""
    @State private var isRunningStartupCheck = false
    
    var body: some View {
        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingContainerView()
            } else {
                ZStack {
                    DashboardView()
                    
                    // Show overlay while running startup health check
                    if isRunningStartupCheck {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Checking permissions...")
                                .font(.headline)
                            Text("Auto-fixing any stuck services")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .shadow(radius: 10)
                        )
                    }
                }
            }
        }
        .onAppear {
            appState.loadTrustedDevices()
            appState.loadConnectionHistory()
            
            // Run startup health check
            Task {
                await runStartupHealthCheck()
            }
        }
        .alert("Permission Issue Detected", isPresented: $showHealthAlert) {
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
            Button("Ignore", role: .cancel) {}
        } message: {
            Text(healthAlertMessage)
        }
    }
    
    @MainActor
    private func runStartupHealthCheck() async {
        // Only run if onboarding is complete
        guard appState.hasCompletedOnboarding else { return }
        
        isRunningStartupCheck = true
        
        // Run health check and auto-fix
        let success = await healthService.performStartupHealthCheck()
        
        isRunningStartupCheck = false
        
        // Start network discovery regardless
        NetworkDiscoveryService.shared.startBrowsing()
        
        // Show alert if issues remain
        if !success, let result = healthService.lastHealthCheck {
            var issues: [String] = []
            
            if result.screenSharing.isStuck {
                issues.append("• Screen Sharing is enabled but not responding")
            }
            if result.screenRecording.isStuck {
                issues.append("• Screen Recording permission needs to be re-granted")
            }
            
            if !issues.isEmpty {
                healthAlertMessage = """
                TidalDrift detected stuck permissions that couldn't be auto-fixed:
                
                \(issues.joined(separator: "\n"))
                
                Go to Settings → Permissions to fix manually.
                """
                showHealthAlert = true
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState.shared)
    }
}
