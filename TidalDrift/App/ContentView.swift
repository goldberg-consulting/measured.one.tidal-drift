import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState.shared)
    }
}
