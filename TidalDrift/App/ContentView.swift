import SwiftUI

/// ContentView is no longer used as the primary app window.
/// The app is entirely menu-bar driven. This file is retained for
/// compatibility but the WindowGroup scene has been removed.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        OnboardingContainerView()
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
