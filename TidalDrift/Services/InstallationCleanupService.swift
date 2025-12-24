import Foundation
import AppKit

/// Service to detect and clean up duplicate TidalDrift installations
class InstallationCleanupService {
    static let shared = InstallationCleanupService()
    
    private init() {}
    
    /// Locations to search for TidalDrift installations
    private let searchPaths = [
        "/Applications",
        NSHomeDirectory() + "/Applications",
        NSHomeDirectory() + "/Desktop",
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents"
    ]
    
    /// Find all TidalDrift app bundles on the system
    func findAllInstallations() -> [URL] {
        var installations: [URL] = []
        let fileManager = FileManager.default
        let currentAppPath = Bundle.main.bundlePath
        
        for searchPath in searchPaths {
            let searchURL = URL(fileURLWithPath: searchPath)
            
            guard let contents = try? fileManager.contentsOfDirectory(
                at: searchURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for item in contents {
                let name = item.lastPathComponent
                
                // Match TidalDrift*.app patterns
                if name.hasPrefix("TidalDrift") && name.hasSuffix(".app") {
                    // Don't include the currently running app
                    if item.path != currentAppPath {
                        installations.append(item)
                    }
                }
            }
        }
        
        // Also check for running instances
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier?.contains("tidaldrift") == true ||
            $0.localizedName?.contains("TidalDrift") == true
        }
        
        // Sort by name
        return installations.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    /// Get info about an installation
    func getInstallationInfo(_ url: URL) -> InstallationInfo {
        let fileManager = FileManager.default
        var info = InstallationInfo(url: url)
        
        // Get modification date
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let modDate = attrs[.modificationDate] as? Date {
            info.modificationDate = modDate
        }
        
        // Get bundle version
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        if let plistData = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] {
            info.version = plist["CFBundleShortVersionString"] as? String ?? "Unknown"
            info.bundleIdentifier = plist["CFBundleIdentifier"] as? String
        }
        
        // Get file size
        if let size = directorySize(url) {
            info.sizeBytes = size
        }
        
        // Check if it's the current app
        info.isCurrentApp = url.path == Bundle.main.bundlePath
        
        return info
    }
    
    /// Delete an installation (moves to Trash)
    func deleteInstallation(_ url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            print("Failed to delete \(url.path): \(error)")
            return false
        }
    }
    
    /// Delete multiple installations
    func deleteInstallations(_ urls: [URL]) -> Int {
        var deleted = 0
        for url in urls {
            if deleteInstallation(url) {
                deleted += 1
            }
        }
        return deleted
    }
    
    /// Calculate directory size
    private func directorySize(_ url: URL) -> Int64? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }
    
    /// Check if there are duplicate installations on startup
    func checkForDuplicatesOnStartup() {
        let installations = findAllInstallations()
        if installations.count > 0 {
            // Post notification that duplicates were found
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .duplicateInstallationsFound,
                    object: nil,
                    userInfo: ["installations": installations]
                )
            }
        }
    }
}

/// Info about a TidalDrift installation
struct InstallationInfo {
    let url: URL
    var version: String = "Unknown"
    var bundleIdentifier: String?
    var modificationDate: Date?
    var sizeBytes: Int64 = 0
    var isCurrentApp: Bool = false
    
    var name: String {
        url.lastPathComponent
    }
    
    var location: String {
        url.deletingLastPathComponent().path
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
    
    var formattedDate: String {
        guard let date = modificationDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

extension Notification.Name {
    static let duplicateInstallationsFound = Notification.Name("duplicateInstallationsFound")
}

