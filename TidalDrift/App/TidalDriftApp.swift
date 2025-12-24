import SwiftUI

@main
struct TidalDriftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Devices") {
                Button("Scan Network") {
                    NotificationCenter.default.post(name: .scanNetwork, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("Add Device Manually...") {
                    NotificationCenter.default.post(name: .addDeviceManually, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        
        MenuBarExtra("TidalDrift", systemImage: "network") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

extension Notification.Name {
    static let scanNetwork = Notification.Name("scanNetwork")
    static let addDeviceManually = Notification.Name("addDeviceManually")
}
