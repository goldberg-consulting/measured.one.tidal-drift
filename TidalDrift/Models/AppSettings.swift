import Foundation

struct AppSettings: Codable, Equatable {
    var launchAtLogin: Bool
    var scanIntervalSeconds: Int
    var showNotifications: Bool
    var useBiometrics: Bool
    var enableConnectionLogging: Bool
    var showMenuBarIcon: Bool
    var autoConnectTrustedDevices: Bool
    var theme: AppTheme
    
    init(launchAtLogin: Bool = false,
         scanIntervalSeconds: Int = 30,
         showNotifications: Bool = true,
         useBiometrics: Bool = false,
         enableConnectionLogging: Bool = true,
         showMenuBarIcon: Bool = true,
         autoConnectTrustedDevices: Bool = false,
         theme: AppTheme = .system) {
        self.launchAtLogin = launchAtLogin
        self.scanIntervalSeconds = scanIntervalSeconds
        self.showNotifications = showNotifications
        self.useBiometrics = useBiometrics
        self.enableConnectionLogging = enableConnectionLogging
        self.showMenuBarIcon = showMenuBarIcon
        self.autoConnectTrustedDevices = autoConnectTrustedDevices
        self.theme = theme
    }
    
    enum AppTheme: String, Codable, CaseIterable {
        case system
        case light
        case dark
        
        var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }
    
    static var `default`: AppSettings {
        AppSettings()
    }
}

extension AppSettings {
    var scanInterval: TimeInterval {
        TimeInterval(scanIntervalSeconds)
    }
    
    static let scanIntervalOptions: [Int] = [15, 30, 60, 120, 300]
    
    static func scanIntervalDisplayName(for seconds: Int) -> String {
        switch seconds {
        case 15: return "15 seconds"
        case 30: return "30 seconds"
        case 60: return "1 minute"
        case 120: return "2 minutes"
        case 300: return "5 minutes"
        default: return "\(seconds) seconds"
        }
    }
}
