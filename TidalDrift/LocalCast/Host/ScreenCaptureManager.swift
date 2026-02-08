import Foundation
import ScreenCaptureKit
import OSLog

protocol ScreenCaptureManagerDelegate: AnyObject {
    func screenCaptureManager(_ manager: ScreenCaptureManager, didOutput sampleBuffer: CMSampleBuffer)
    func screenCaptureManager(_ manager: ScreenCaptureManager, didFailWithError error: Error)
}

/// Capture mode for LocalCast streaming
enum CaptureMode {
    case fullDisplay(CGDirectDisplayID)
    case singleWindow(CGWindowID)
    case singleApp(pid_t)
}

/// Window capture specific errors
enum WindowCaptureError: LocalizedError {
    case windowNotFound
    case appNotFound
    case capturePermissionDenied
    
    var errorDescription: String? {
        switch self {
        case .windowNotFound:
            return "The specified window could not be found"
        case .appNotFound:
            return "The specified application could not be found"
        case .capturePermissionDenied:
            return "Screen capture permission is required"
        }
    }
}

class ScreenCaptureManager: NSObject, SCStreamOutput, SCStreamDelegate {
    private let logger = Logger(subsystem: "com.tidaldrift", category: "ScreenCapture")
    
    weak var delegate: ScreenCaptureManagerDelegate?
    
    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "com.tidaldrift.localcast.capture", qos: .userInteractive)
    
    /// Current capture mode
    private(set) var captureMode: CaptureMode?
    
    /// The screen bounds of the captured content (for input coordinate mapping)
    /// For full display: the display bounds
    /// For window: the window's frame on screen
    /// For app: the bounding box of all app windows
    private(set) var captureBounds: CGRect?
    
    // MARK: - Full Display Capture
    
    func startCapture(displayID: CGDirectDisplayID, width: Int, height: Int, frameRate: Int) async throws {
        logger.info("Requesting shareable content...")
        
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            logger.info("Got shareable content: \(content.displays.count) displays, \(content.windows.count) windows")
        } catch {
            logger.error("Failed to get shareable content (permission denied?): \(error.localizedDescription)")
            throw error
        }
        
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            logger.error("Display \(displayID) not found in available displays: \(content.displays.map { $0.displayID })")
            throw LocalCastError.noDisplayAvailable
        }
        
        logger.info("Found display: \(display.displayID) (\(display.width)x\(display.height))")
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Full display capture - bounds are the full display
        captureBounds = nil  // nil means full screen, use main display dimensions
        captureMode = .fullDisplay(displayID)
        try await startStream(with: filter, width: width, height: height, frameRate: frameRate, description: "display \(displayID)")
    }
    
    // MARK: - Single Window Capture
    
    /// Start capturing a specific window by its window ID
    func startWindowCapture(windowID: CGWindowID, frameRate: Int = 30) async throws {
        logger.info("Starting window capture for windowID: \(windowID)")
        
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            logger.info("Got shareable content: \(content.windows.count) windows")
        } catch {
            logger.error("Failed to get shareable content: \(error.localizedDescription)")
            throw error
        }
        
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            logger.error("Window \(windowID) not found in available windows")
            throw WindowCaptureError.windowNotFound
        }
        
        logger.info("Found window: '\(window.title ?? "Untitled")' at frame \(NSStringFromRect(window.frame))")
        
        let filter = SCContentFilter(desktopIndependentWindow: window)
        
        let maxDimension = 2560
        let scale: Double
        if window.frame.width > CGFloat(maxDimension) || window.frame.height > CGFloat(maxDimension) {
            scale = Double(maxDimension) / Double(max(window.frame.width, window.frame.height))
        } else {
            scale = 1.0
        }
        
        let width = Int(window.frame.width * scale)
        let height = Int(window.frame.height * scale)
        
        // Store the window's screen bounds for input mapping
        captureBounds = window.frame
        captureMode = .singleWindow(windowID)
        
        logger.info("🪟 Window capture bounds: \(NSStringFromRect(window.frame))")
        try await startStream(with: filter, width: width, height: height, frameRate: frameRate, description: "window '\(window.title ?? "Untitled")'")
    }
    
    // MARK: - Single App Capture
    
    /// Start capturing all windows of a specific application
    func startAppCapture(processID: pid_t, frameRate: Int = 30) async throws {
        logger.info("Starting app capture for PID: \(processID)")
        
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            logger.error("Failed to get shareable content: \(error.localizedDescription)")
            throw error
        }
        
        guard let app = content.applications.first(where: { $0.processID == processID }) else {
            logger.error("App with PID \(processID) not found")
            throw WindowCaptureError.appNotFound
        }
        
        guard let display = content.displays.first else {
            logger.error("No display found")
            throw LocalCastError.noDisplayAvailable
        }
        
        logger.info("Found app: '\(app.applicationName)' with display \(display.displayID)")
        
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        
        let appWindows = content.windows.filter { $0.owningApplication?.processID == processID && $0.isOnScreen }
        let bounds = appWindows.reduce(CGRect.null) { result, window in
            result.union(window.frame)
        }
        
        let maxDimension = 2560
        let width: Int
        let height: Int
        
        if bounds.isNull || bounds.isEmpty {
            width = 1920
            height = 1080
            captureBounds = nil  // Use full screen mapping
        } else {
            let scale = min(1.0, Double(maxDimension) / Double(max(bounds.width, bounds.height)))
            width = Int(bounds.width * scale)
            height = Int(bounds.height * scale)
            captureBounds = bounds
            logger.info("📱 App capture bounds: \(NSStringFromRect(bounds))")
        }
        
        captureMode = .singleApp(processID)
        try await startStream(with: filter, width: width, height: height, frameRate: frameRate, description: "app '\(app.applicationName)'")
    }
    
    // MARK: - Shared Stream Setup
    
    private func startStream(with filter: SCContentFilter, width: Int, height: Int, frameRate: Int, description: String) async throws {
        if stream != nil {
            await stopCapture()
        }
        
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 5
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
        
        logger.info("Creating SCStream for \(description)...")
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        do {
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            logger.info("Added stream output")
        } catch {
            logger.error("Failed to add stream output: \(error.localizedDescription)")
            throw error
        }
        
        do {
            try await stream?.startCapture()
            logger.info("Capture started for \(description) at \(width)x\(height)@\(frameRate)fps")
        } catch {
            logger.error("Failed to start capture: \(error.localizedDescription)")
            throw error
        }
    }
    
    func stopCapture() async {
        do {
            try await stream?.stopCapture()
            stream = nil
            captureMode = nil
            captureBounds = nil
            logger.info("Stopped screen capture")
        } catch {
            logger.error("Failed to stop screen capture: \(error.localizedDescription)")
        }
    }
    
    // MARK: - SCStreamOutput
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        delegate?.screenCaptureManager(self, didOutput: sampleBuffer)
    }
    
    // MARK: - SCStreamDelegate
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("Stream stopped with error: \(error.localizedDescription)")
        delegate?.screenCaptureManager(self, didFailWithError: error)
    }
}
