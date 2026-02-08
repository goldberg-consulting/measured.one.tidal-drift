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
    
    static let `default` = LocalCastConfiguration()
    
    /// Default UDP port used by LocalCast host sessions.
    static let hostPort: UInt16 = 5904
}

