import Foundation
import ServiceManagement

class SettingsService {
    static let shared = SettingsService()
    
    private let settingsKey = "appSettings"
    
    private init() {}
    
    func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    func saveSettings(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
        
        applySettings(settings)
    }
    
    private func applySettings(_ settings: AppSettings) {
        setLaunchAtLogin(settings.launchAtLogin)
    }
    
    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to set launch at login: \(error)")
            }
        }
    }
    
    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
    
    func resetToDefaults() {
        saveSettings(.default)
    }
    
    func exportSettings() -> Data? {
        let settings = loadSettings()
        return try? JSONEncoder().encode(settings)
    }
    
    func importSettings(from data: Data) -> Bool {
        guard let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return false
        }
        saveSettings(settings)
        return true
    }
}
