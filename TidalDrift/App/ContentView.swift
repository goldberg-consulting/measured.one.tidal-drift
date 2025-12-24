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
            NetworkDiscoveryService.shared.startBrowsing()
            
            // Start TidalDrift peer discovery and advertising
            TidalDriftPeerService.shared.startAdvertising()
            TidalDriftPeerService.shared.startDiscovery()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState.shared)
    }
}
