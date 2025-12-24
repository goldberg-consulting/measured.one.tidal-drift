import Foundation
import Security
import LocalAuthentication

class KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "com.tidaldrift.credentials"
    
    /// Whether to require biometric authentication for credential access
    var requireBiometricAuth: Bool = true
    
    private init() {}
    
    /// Credential structure for JSON encoding (safer than delimiter-based storage)
    private struct StoredCredential: Codable {
        let username: String
        let password: String
    }
    
    /// Create access control with optional biometric requirement
    private func createAccessControl() -> SecAccessControl? {
        if requireBiometricAuth {
            // Require biometric auth (Touch ID/Face ID) or device passcode
            return SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.userPresence],
                nil
            )
        }
        return nil
    }
    
    func saveCredential(for deviceId: String, username: String, password: String) throws {
        let credential = StoredCredential(username: username, password: password)
        guard let data = try? JSONEncoder().encode(credential) else {
            throw KeychainError.encodingFailed
        }
        
        try? deleteCredential(for: deviceId)
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: deviceId,
            kSecValueData as String: data
        ]
        
        // Add biometric access control if available
        if let accessControl = createAccessControl() {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    func getCredential(for deviceId: String) throws -> (username: String, password: String)? {
        let context = LAContext()
        context.localizedReason = "Access saved credentials for \(deviceId)"
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: deviceId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        // Provide authentication context for biometric-protected items
        if requireBiometricAuth {
            query[kSecUseAuthenticationContext as String] = context
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            if status == errSecItemNotFound {
                return nil
            }
            if status == errSecUserCanceled || status == errSecAuthFailed {
                throw KeychainError.authenticationFailed
            }
            throw KeychainError.retrieveFailed(status)
        }
        
        // Try new JSON format first
        if let credential = try? JSONDecoder().decode(StoredCredential.self, from: data) {
            return (username: credential.username, password: credential.password)
        }
        
        // Fall back to legacy colon-separated format for existing credentials
        if let credentials = String(data: data, encoding: .utf8) {
            let parts = credentials.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                return (username: parts[0], password: parts[1])
            }
        }
        
        throw KeychainError.invalidData
    }
    
    func deleteCredential(for deviceId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: deviceId
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    func hasCredential(for deviceId: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: deviceId,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func getAllSavedDeviceIds() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            if status == errSecItemNotFound {
                return []
            }
            throw KeychainError.retrieveFailed(status)
        }
        
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
    
    func authenticateWithBiometrics(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                continuation.resume(returning: success)
            }
        }
    }
}

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    case authenticationFailed
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode credentials"
        case .saveFailed(let status):
            return "Failed to save credentials (error: \(status))"
        case .retrieveFailed(let status):
            return "Failed to retrieve credentials (error: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete credentials (error: \(status))"
        case .invalidData:
            return "Invalid credential data"
        case .authenticationFailed:
            return "Biometric authentication failed or was cancelled"
        }
    }
}
