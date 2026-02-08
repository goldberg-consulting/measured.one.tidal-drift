import Foundation
import CoreMedia
import OSLog
import Network
import ScreenCaptureKit

/// Capture target for hosting - full display or specific window/app
enum HostCaptureTarget {
    case fullDisplay
    case window(CGWindowID, title: String)
    case app(pid_t, name: String)
}

class HostSession: ScreenCaptureManagerDelegate, VideoEncoderDelegate, UDPTransportDelegate {
    private let logger = Logger(subsystem: "com.tidaldrift", category: "HostSession")
    
    private let captureManager = ScreenCaptureManager()
    private let encoder = VideoEncoder()
    private let inputInjector = InputInjector()
    private let transport = UDPTransport()
    
    private let configuration: LocalCastConfiguration
    private var isRunning = false
    private var sequenceNumber: UInt32 = 0
    
    /// Current capture target
    private(set) var captureTarget: HostCaptureTarget = .fullDisplay
    
    // Store both the endpoint and the connection for proper bidirectional communication
    private var clientEndpoint: NWEndpoint?
    private var clientConnection: NWConnection?
    
    /// True when the client is on the same machine (127.0.0.1 or local IP).
    /// On loopback, input injection is skipped because CGEvent.post() moves the
    /// real cursor, which yanks it out of the viewer window creating a feedback loop.
    private var isLoopbackConnection = false
    
    init(configuration: LocalCastConfiguration) {
        self.configuration = configuration
        captureManager.delegate = self
        encoder.delegate = self
        transport.delegate = self
    }
    
    /// Start hosting with full display capture (default)
    func start() async throws {
        try await start(target: .fullDisplay)
    }
    
    /// Start hosting with a specific capture target (window or app)
    func start(target: HostCaptureTarget) async throws {
        guard !isRunning else {
            logger.info("Host session already running, skipping start")
            return
        }
        
        self.captureTarget = target
        logger.info("Starting host session with target: \(String(describing: target))")
        
        // Check and log accessibility permission status (but don't prompt repeatedly)
        if inputInjector.hasAccessibilityPermission {
            logger.info("✅ Accessibility permission granted - input forwarding will work")
        } else {
            logger.warning("⚠️ Accessibility permission NOT granted - input forwarding will NOT work!")
            logger.info("💡 Go to System Settings > Privacy & Security > Accessibility and enable TidalDrift")
            // Only log the warning - don't automatically open System Settings to avoid permission loops
            // User can manually grant permission via System Settings
        }
        
        // Start UDP transport first
        do {
            try transport.startListening(port: 5904)
            logger.info("✅ UDP transport listening on port 5904")
        } catch {
            logger.error("❌ Failed to start UDP transport: \(error.localizedDescription)")
            throw error
        }
        
        do {
            switch target {
            case .fullDisplay:
                try await startFullDisplayCapture()
                
            case .window(let windowID, let title):
                logger.info("🪟 Starting window capture: '\(title)' (ID: \(windowID))")
                try await startWindowCapture(windowID: windowID)
                
            case .app(let processID, let name):
                logger.info("📱 Starting app capture: '\(name)' (PID: \(processID))")
                try await startAppCapture(processID: processID)
            }
            
            // Update input injector with capture bounds for proper coordinate mapping
            updateInputBounds()
            
            logger.info("✅ Capture started")
        } catch {
            logger.error("❌ Failed to start capture: \(error.localizedDescription)")
            transport.stopListening()
            throw error
        }
        
        isRunning = true
        logger.info("✅ Host session started successfully - listening on port 5904")
    }
    
    /// Update the input injector with the current capture bounds
    private func updateInputBounds() {
        inputInjector.captureBounds = captureManager.captureBounds
        
        if let bounds = captureManager.captureBounds {
            logger.info("🎯 Input bounds set to: \(NSStringFromRect(bounds))")
        } else {
            logger.info("🎯 Input bounds set to full screen")
        }
    }
    
    /// Start full display capture (original behavior)
    private func startFullDisplayCapture() async throws {
        let displayID = CGMainDisplayID()
        logger.info("Using display ID: \(displayID)")
        
        // Get display mode for native resolution info
        let mode = CGDisplayCopyDisplayMode(displayID)
        let nativeWidth = mode?.pixelWidth ?? CGDisplayPixelsWide(displayID)
        let nativeHeight = mode?.pixelHeight ?? CGDisplayPixelsHigh(displayID)
        
        // Cap resolution to prevent massive frames that clog the network
        // Max 2560x1440 (1440p) for reliable streaming over WiFi
        let maxDimension = 2560
        let scale: Double
        if nativeWidth > maxDimension || nativeHeight > maxDimension {
            scale = Double(maxDimension) / Double(max(nativeWidth, nativeHeight))
        } else {
            scale = 1.0
        }
        
        let width = Int(Double(nativeWidth) * scale)
        let height = Int(Double(nativeHeight) * scale)
        
        logger.info("🚀 LocalCast: Capturing at \(width)x\(height) (native: \(nativeWidth)x\(nativeHeight), scale: \(String(format: "%.2f", scale)))")
        
        encoder.setup(
            width: width,
            height: height,
            codec: configuration.codec,
            bitrateMbps: configuration.bitrateMbps,
            fps: configuration.targetFrameRate
        )
        logger.info("✅ Video encoder configured: \(self.configuration.codec.rawValue), \(self.configuration.bitrateMbps)Mbps, \(self.configuration.targetFrameRate)fps")
        
        try await captureManager.startCapture(
            displayID: displayID,
            width: width,
            height: height,
            frameRate: configuration.targetFrameRate
        )
    }
    
    /// Start window-specific capture
    private func startWindowCapture(windowID: CGWindowID) async throws {
        // Set up encoder BEFORE starting capture to avoid race condition where
        // frames arrive with no encoder session ready (causing silent drops / freeze).
        encoder.setup(
            width: 1920,
            height: 1080,
            codec: configuration.codec,
            bitrateMbps: configuration.bitrateMbps,
            fps: configuration.targetFrameRate
        )
        encoder.forceKeyFrame()
        
        try await captureManager.startWindowCapture(windowID: windowID, frameRate: configuration.targetFrameRate)
    }
    
    /// Start app-specific capture
    private func startAppCapture(processID: pid_t) async throws {
        // Set up encoder BEFORE starting capture to avoid race condition.
        encoder.setup(
            width: 1920,
            height: 1080,
            codec: configuration.codec,
            bitrateMbps: configuration.bitrateMbps,
            fps: configuration.targetFrameRate
        )
        encoder.forceKeyFrame()
        
        try await captureManager.startAppCapture(processID: processID, frameRate: configuration.targetFrameRate)
    }
    
    func stop() async {
        guard isRunning else { return }
        
        await captureManager.stopCapture()
        encoder.invalidate()
        transport.stopListening()
        
        // Clear input bounds
        inputInjector.captureBounds = nil
        
        clientConnection = nil
        clientEndpoint = nil
        isRunning = false
        logger.info("Host session stopped")
    }
    
    func handleRemoteInput(_ input: InputInjector.RemoteInput) {
        inputInjector.inject(input)
    }
    
    // MARK: - ScreenCaptureManagerDelegate
    
    func screenCaptureManager(_ manager: ScreenCaptureManager, didOutput sampleBuffer: CMSampleBuffer) {
        encoder.encode(sampleBuffer)
    }
    
    func screenCaptureManager(_ manager: ScreenCaptureManager, didFailWithError error: Error) {
        logger.error("Capture failure: \(error.localizedDescription)")
    }
    
    // MARK: - VideoEncoderDelegate
    
    func videoEncoder(_ encoder: VideoEncoder, didOutput packet: Data, isKeyFrame: Bool, timestamp: CMTime) {
        // Prefer using the stored connection for reliable delivery
        guard clientConnection != nil || clientEndpoint != nil else { return }
        
        sequenceNumber += 1
        let castPacket = LocalCastPacket(
            type: .videoFrame,
            sequenceNumber: sequenceNumber,
            timestamp: Date().timeIntervalSince1970,
            payload: packet
        )
        
        // Use the connection directly if available, otherwise fall back to endpoint
        if let connection = clientConnection {
            transport.send(packet: castPacket, on: connection)
        } else if let endpoint = clientEndpoint {
            transport.send(packet: castPacket, to: endpoint)
        }
    }
    
    // MARK: - UDPTransportDelegate
    
    func udpTransport(_ transport: UDPTransport, clientDidConnect endpoint: NWEndpoint, connection: NWConnection) {
        // Store the connection from the client for reliable bidirectional communication
        clientConnection = connection
        clientEndpoint = endpoint
        
        // Detect loopback: check if client IP is localhost or our own IP
        isLoopbackConnection = Self.isLocalEndpoint(endpoint)
        
        logger.info("LocalCast: Client connected from \(String(describing: endpoint)) (loopback: \(self.isLoopbackConnection))")
        print("🔌 HostSession: Client connected from \(endpoint) (loopback: \(isLoopbackConnection))")
        
        // Send initial keyframe request to encoder
        encoder.forceKeyFrame()
    }
    
    /// Check if an endpoint is a loopback/local address
    private static func isLocalEndpoint(_ endpoint: NWEndpoint) -> Bool {
        let desc = String(describing: endpoint)
        if desc.contains("127.0.0.1") || desc.contains("::1") { return true }
        // Also check if it matches our own LAN IP
        if let localIP = NetworkUtils.getLocalIPAddress(), desc.contains(localIP) { return true }
        return false
    }
    
    private var receivedInputCount = 0
    
    func udpTransport(_ transport: UDPTransport, didReceivePacket packet: LocalCastPacket, from endpoint: NWEndpoint) {
        // Update client endpoint if not already set
        if clientEndpoint == nil {
            clientEndpoint = endpoint
            logger.info("LocalCast: Client connected from \(String(describing: endpoint))")
            print("🔌 HostSession: Client connected from \(endpoint)")
        }
        
        switch packet.type {
        case .inputEvent:
            receivedInputCount += 1
            
            if let input = InputInjector.RemoteInput.deserialize(packet.payload) {
                // Log clicks/keys always, moves periodically
                let isSignificant: Bool
                switch input {
                case .mouseDown, .mouseUp, .keyDown, .keyUp:
                    isSignificant = true
                default:
                    isSignificant = receivedInputCount <= 5 || receivedInputCount % 200 == 0
                }
                
                if isSignificant {
                    print("🎮 HostSession: Input #\(receivedInputCount): \(input)")
                }
                
                if isLoopbackConnection {
                    // On loopback, skip CGEvent injection -- it moves the real cursor
                    // which yanks it out of the viewer window (feedback loop).
                    // The input pipeline is proven: capture -> serialize -> UDP -> deserialize.
                    if isSignificant {
                        print("   ⏭️ Loopback mode: input received but injection skipped (would cause cursor feedback)")
                    }
                } else {
                    inputInjector.inject(input)
                }
            } else {
                if receivedInputCount <= 10 {
                    print("❌ HostSession: Failed to deserialize input event (payload: \(packet.payload.count) bytes)")
                }
            }
            
        case .heartbeat:
            // Respond with heartbeat (pong)
            let pong = LocalCastPacket(type: .heartbeat, sequenceNumber: 0, timestamp: Date().timeIntervalSince1970, payload: Data())
            transport.send(packet: pong, to: endpoint)
            
        case .keyframeRequest:
            // Client requested a keyframe
            logger.info("🔑 LocalCast: Received keyframe request from client")
            print("🔑 HostSession: Received keyframe request")
            encoder.forceKeyFrame()
            
        case .appListRequest:
            // Client wants to know what apps are available to stream
            print("📋 HostSession: Received app list request from client")
            Task {
                await handleAppListRequest(replyTo: endpoint)
            }
            
        case .streamAppRequest:
            // Client wants to stream a specific app/window
            print("🎬 HostSession: Received stream request from client")
            Task {
                await handleStreamRequest(payload: packet.payload, replyTo: endpoint)
            }
            
        default:
            print("❓ HostSession: Received unknown packet type: \(packet.type)")
        }
    }
    
    // MARK: - App List & Stream Request Handling
    
    /// Gather available apps and send to client
    private func handleAppListRequest(replyTo endpoint: NWEndpoint) async {
        print("📋 HostSession: Gathering available apps...")
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            
            // System/background bundle ID prefixes and exact matches to exclude
            let excludedBundlePrefixes = [
                "com.apple.dock",
                "com.apple.WindowManager",
                "com.apple.controlcenter",
                "com.apple.notificationcenterui",
                "com.apple.Spotlight",
                "com.apple.SystemUIServer",
                "com.apple.loginwindow",
                "com.apple.finder.SharedFileList",
                "com.apple.universalcontrol",
                "com.apple.AirPlayUIAgent",
                "com.apple.accessibility",
                "com.apple.TextInputMenuAgent",
                "com.apple.TextInputSwitcher",
                "com.apple.CoreLocationAgent",
                "com.apple.ViewBridgeAuxiliary",
                "com.apple.BKAgentService",
                "com.apple.cloudd",
                "com.apple.inputmethod",
                "com.apple.ScreenTimeWidgetExtension"
            ]
            
            // Group windows by application -- only include on-screen windows
            var appDict: [pid_t: (app: SCRunningApplication, windows: [SCWindow])] = [:]
            
            for window in content.windows {
                guard let app = window.owningApplication else { continue }
                
                // Skip TidalDrift itself
                if app.bundleIdentifier == Bundle.main.bundleIdentifier { continue }
                
                // Skip system/background apps
                if excludedBundlePrefixes.contains(where: { app.bundleIdentifier.hasPrefix($0) }) { continue }
                
                // Only include windows that are on-screen and reasonably sized
                guard window.isOnScreen else { continue }
                guard window.frame.width >= 100 && window.frame.height >= 50 else { continue }
                
                // Require a title (windows without titles are usually invisible/system)
                guard let title = window.title, !title.isEmpty else { continue }
                
                if appDict[app.processID] == nil {
                    appDict[app.processID] = (app: app, windows: [])
                }
                appDict[app.processID]?.windows.append(window)
            }
            
            // Convert to RemoteAppInfo -- only include apps that have at least one visible window
            var apps: [RemoteAppInfo] = []
            for (pid, data) in appDict {
                let windows = data.windows.map { window in
                    RemoteWindowInfo(
                        windowID: window.windowID,
                        title: window.title ?? "Untitled",
                        width: Int(window.frame.width),
                        height: Int(window.frame.height),
                        isOnScreen: window.isOnScreen
                    )
                }
                
                // Skip apps with no visible windows
                guard !windows.isEmpty else { continue }
                
                // Skip apps with empty names (background agents)
                guard !data.app.applicationName.isEmpty else { continue }
                
                apps.append(RemoteAppInfo(
                    processID: pid,
                    name: data.app.applicationName,
                    bundleIdentifier: data.app.bundleIdentifier,
                    windows: windows
                ))
            }
            
            // Sort by name
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            print("📋 HostSession: Found \(apps.count) streamable apps")
            
            // Encode and send
            let encoder = JSONEncoder()
            let payload = try encoder.encode(apps)
            
            let packet = LocalCastPacket(
                type: .appListResponse,
                sequenceNumber: 0,
                timestamp: Date().timeIntervalSince1970,
                payload: payload
            )
            
            transport.send(packet: packet, to: endpoint)
            print("📋 HostSession: Sent app list to client (\(payload.count) bytes)")
            
        } catch {
            print("❌ HostSession: Failed to get app list: \(error)")
        }
    }
    
    /// Handle a request to stream a specific app/window
    private func handleStreamRequest(payload: Data, replyTo endpoint: NWEndpoint) async {
        print("🎬 HostSession: Processing stream request...")
        print("🎬 HostSession: Payload size: \(payload.count) bytes")
        
        do {
            let decoder = JSONDecoder()
            let request = try decoder.decode(StreamRequest.self, from: payload)
            
            print("🎬 HostSession: Stream request decoded:")
            print("   Type: \(request.type)")
            print("   ProcessID: \(request.processID ?? -1)")
            print("   WindowID: \(request.windowID ?? 0)")
            print("   AppName: \(request.appName ?? "nil")")
            
            // Stop any existing capture
            if isRunning {
                print("🎬 HostSession: Stopping existing capture...")
                await captureManager.stopCapture()
                encoder.invalidate()
                isRunning = false
                print("🎬 HostSession: Existing capture stopped")
            }
            
            // Start the requested capture
            print("🎬 HostSession: Starting new capture...")
            switch request.type {
            case .fullDisplay:
                print("🎬 HostSession: Starting FULL DISPLAY capture")
                try await startFullDisplayCapture()
                captureTarget = .fullDisplay
                
            case .window:
                guard let windowID = request.windowID else {
                    print("❌ HostSession: No window ID in request!")
                    throw LocalCastError.connectionFailed("No window ID provided")
                }
                let title = request.appName ?? "Window"
                print("🎬 HostSession: Starting WINDOW capture: '\(title)' (ID: \(windowID))")
                try await startWindowCapture(windowID: CGWindowID(windowID))
                captureTarget = .window(CGWindowID(windowID), title: title)
                
            case .app:
                guard let processID = request.processID else {
                    print("❌ HostSession: No process ID in request!")
                    throw LocalCastError.connectionFailed("No process ID provided")
                }
                let name = request.appName ?? "App"
                print("🎬 HostSession: Starting APP capture: '\(name)' (PID: \(processID))")
                try await startAppCapture(processID: processID)
                captureTarget = .app(processID, name: name)
            }
            
            updateInputBounds()
            isRunning = true
            
            // Force a keyframe so the client decoder can sync to the new stream.
            // The encoder was already primed with forceKeyFrame() before capture started,
            // but send another just in case frames slipped through.
            encoder.forceKeyFrame()
            print("🎬 HostSession: ✅ New capture running, keyframe forced")
            
            // Send success response
            let response = StreamResponse(
                success: true,
                message: "Streaming started",
                streamingTarget: request.appName ?? "Display"
            )
            let responsePayload = try JSONEncoder().encode(response)
            
            let packet = LocalCastPacket(
                type: .streamAppResponse,
                sequenceNumber: 0,
                timestamp: Date().timeIntervalSince1970,
                payload: responsePayload
            )
            transport.send(packet: packet, to: endpoint)
            
            print("🎬 HostSession: ✅ Started streaming '\(request.appName ?? "Display")'")
            print("🎬 HostSession: Response sent to client")
            
        } catch {
            print("❌ HostSession: Stream request failed: \(error.localizedDescription)")
            
            // Try to recover by falling back to full display capture
            print("🔄 HostSession: Recovering -- falling back to full display capture")
            do {
                try await startFullDisplayCapture()
                captureTarget = .fullDisplay
                updateInputBounds()
                isRunning = true
                encoder.forceKeyFrame()
                print("🔄 HostSession: ✅ Recovered to full display")
            } catch {
                print("❌ HostSession: Recovery also failed: \(error.localizedDescription)")
            }
            
            // Send error response to client
            let response = StreamResponse(
                success: false,
                message: error.localizedDescription,
                streamingTarget: nil
            )
            if let responsePayload = try? JSONEncoder().encode(response) {
                let packet = LocalCastPacket(
                    type: .streamAppResponse,
                    sequenceNumber: 0,
                    timestamp: Date().timeIntervalSince1970,
                    payload: responsePayload
                )
                transport.send(packet: packet, to: endpoint)
            }
        }
    }
}
