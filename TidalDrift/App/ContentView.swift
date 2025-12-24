import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showOnboarding: Bool = false
    
    var body: some View {
        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingContainerView()
            } else {
                DashboardView()
            }
        }
        .onAppear {
            appState.loadTrustedDevices()
            appState.loadConnectionHistory()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
