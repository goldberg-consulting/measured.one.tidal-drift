import Foundation

struct LocalCastConfiguration: Codable {
    enum QualityPreset: String, CaseIterable, Codable {
        case ultra      // 100 Mbps, native resolution, 60fps
        case high       // 50 Mbps, native resolution, 60fps
        case balanced   // 30 Mbps, native resolution, 30fps
        case low        // 15 Mbps, 75% resolution, 30fps
    }
    
    enum Codec: String, CaseIterable, Codable {
        case h264       // Wider compatibility, faster encode
        case hevc       // Better compression, newer Macs only
    }
    
    var qualityPreset: QualityPreset = .ultra
    var codec: Codec = .h264  // Use H.264 for reliable NAL parsing (HEVC has different NAL format)
    var targetFrameRate: Int = 60
    var adaptiveQuality: Bool = false // Disable by default for "fastest pipe" on LAN
    var showLatencyOverlay: Bool = false
    var captureCursor: Bool = true
    var captureAudio: Bool = false  // Future
    
    // Security
    var requireAuthentication: Bool = true
    var inputRateLimit: Int = 120  // events per second, 0 = unlimited
    
    // Derived properties
    var bitrateMbps: Int {
        switch qualityPreset {
        case .ultra: return 100
        case .high: return 50
        case .balanced: return 30
        case .low: return 15
        }
    }
    
    var scaleFactor: CGFloat {
        qualityPreset == .low ? 0.75 : 1.0
    }
    
    /// Maximum capture dimension (longest edge). Higher quality presets allow
    /// larger captures to preserve detail on high-DPI / large displays.
    var maxCaptureDimension: Int {
        switch qualityPreset {
        case .ultra: return 3840    // Up to 4K
        case .high: return 2560     // Up to 1440p
        case .balanced: return 1920 // 1080p
        case .low: return 1280      // 720p
        }
    }
    
    /// Encoder quality hint passed to VTCompressionSession (0.0 = min, 1.0 = lossless).
    var encoderQuality: Float {
        switch qualityPreset {
        case .ultra: return 0.92
        case .high: return 0.80
        case .balanced: return 0.70
        case .low: return 0.55
        }
    }
    
    /// Preset choices for the input rate-limit picker in settings UI.
    static let inputRateLimitOptions: [Int] = [60, 120, 240, 500, 0]
    
    static let `default` = LocalCastConfiguration()
    
    /// Default UDP port used by LocalCast host sessions.
    static let hostPort: UInt16 = 5904
}

