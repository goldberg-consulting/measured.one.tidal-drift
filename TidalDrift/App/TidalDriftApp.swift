import SwiftUI

@main
struct TidalDriftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Text("TD").font(.system(size: 11, weight: .bold, design: .rounded))
                .help("TidalDrift")
        }
        .menuBarExtraStyle(.window)
    }
}

extension Notification.Name {
    static let scanNetwork = Notification.Name("scanNetwork")
    static let addDeviceManually = Notification.Name("addDeviceManually")
    static let showOnboarding = Notification.Name("showOnboarding")
}
