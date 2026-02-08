import Foundation
import Network
import OSLog
import Combine
import CoreMedia
import CoreVideo

protocol ClientSessionDelegate: AnyObject {
    func clientSession(_ session: ClientSession, didDisconnectWithReason reason: String)
    func clientSession(_ session: ClientSession, didUpdateResolution size: CGSize)
    func clientSession(_ session: ClientSession, didReceiveAppList apps: [RemoteAppInfo])
    func clientSession(_ session: ClientSession, didReceiveStreamResponse response: StreamResponse)
}

// Default implementations for optional delegate methods
extension ClientSessionDelegate {
    func clientSession(_ session: ClientSession, didReceiveAppList apps: [RemoteAppInfo]) {}
    func clientSession(_ session: ClientSession, didReceiveStreamResponse response: StreamResponse) {}
}

class ClientSession: ObservableObject, UDPTransportDelegate, VideoDecoderDelegate {
    private let logger = Logger(subsystem: "com.tidaldrift", category: "ClientSession")
    
    private let transport = UDPTransport()
    private let decoder = VideoDecoder()
    var renderer: MetalRenderer?
    weak var delegate: ClientSessionDelegate?
    
    private var remoteResolution: CGSize?
    
    @Published var stats: LocalCastStats?
    @Published var isConnected = false
    @Published var connectionStatus: String = "Connecting..."
    @Published var remoteApps: [RemoteAppInfo] = []
    @Published var isLoadingApps = false
    
    private let device: DiscoveredDevice
    private var hostEndpoint: NWEndpoint?
    private var heartbeatTimer: Timer?
    private var lastHeartbeatResponse: Date?
    private var frameCount: Int = 0
    private var lastStatsUpdate: Date = Date()
    
    init(device: DiscoveredDevice) {
        self.device = device
        transport.delegate = self
        decoder.delegate = self
    }
    
    func connect() async throws {
        logger.info("Connecting to LocalCast host '\(self.device.name)'...")
        connectionStatus = "Resolving \(device.name)..."
        
        // Use ConnectionResolver to get the best address (hostname-first strategy)
        // This handles stale IPs and DHCP changes automatically
        let resolvedAddress: String
        do {
            let resolved = try await ConnectionResolver.shared.resolve(
                device: device,
                strategy: .hostnameFirst,
                timeout: 8.0
            )
            resolvedAddress = resolved.address
            logger.info("LocalCast: Resolved to \(resolved.address) via \(resolved.method.rawValue)")
        } catch {
            // Fall back to cached IP if resolution fails
            resolvedAddress = self.device.ipAddress
            logger.warning("LocalCast: Resolution failed, using cached IP: \(self.device.ipAddress)")
        }
        
        await MainActor.run {
            self.connectionStatus = "Connecting to \(self.device.name)..."
        }
        
        // Store the host endpoint with resolved address
        hostEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(resolvedAddress), port: 5904)
        logger.info("LocalCast: Host endpoint set to \(resolvedAddress):5904")
        
        // Start listening on an ephemeral port to receive video frames
        // The transport will also be able to receive on the connection we create when sending
        do {
            try transport.startListening(port: 0) // Ephemeral port for receiving
            logger.info("Client listening on port \(self.transport.localPort ?? 0)")
        } catch {
            logger.error("Failed to start client listener: \(error.localizedDescription)")
            // Continue anyway - we might still receive on the send connection
        }
        
        // Start sending heartbeats to establish connection
        await MainActor.run {
            startHeartbeat()
        }
        
        // Request keyframes multiple times to ensure host receives one
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.requestKeyFrame()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.requestKeyFrame()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.requestKeyFrame()
        }
    }
    
    func disconnect() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        transport.stopListening()
        decoder.invalidate()
        isConnected = false
        connectionStatus = "Disconnected"
        logger.info("Disconnected from LocalCast host")
    }
    
    private var inputSendCount = 0
    
    func sendInput(_ input: InputInjector.RemoteInput) {
        guard let endpoint = hostEndpoint else {
            print("❌ ClientSession: Cannot send input - no host endpoint set!")
            return
        }
        
        inputSendCount += 1
        
        // Log ALL mouse clicks and first few of other events
        let shouldLog: Bool
        switch input {
        case .mouseDown, .mouseUp, .keyDown, .keyUp:
            shouldLog = true  // Always log clicks and key presses
        default:
            shouldLog = inputSendCount <= 5 || inputSendCount % 100 == 0
        }
        
        if shouldLog {
            print("📤 ClientSession: Sending input #\(self.inputSendCount) to \(endpoint)")
            print("   Input: \(String(describing: input))")
        }
        
        let payload = input.serialize()
        let packet = LocalCastPacket(
            type: .inputEvent,
            sequenceNumber: UInt32(inputSendCount),
            timestamp: Date().timeIntervalSince1970,
            payload: payload
        )
        
        if shouldLog {
            print("   Packet type: \(packet.type), payload size: \(payload.count) bytes")
        }
        
        transport.send(packet: packet, to: endpoint)
    }
    
    func requestKeyFrame() {
        guard let endpoint = hostEndpoint else { return }
        let packet = LocalCastPacket(
            type: .keyframeRequest,
            sequenceNumber: 0,
            timestamp: Date().timeIntervalSince1970,
            payload: Data()
        )
        transport.send(packet: packet, to: endpoint)
        logger.info("Requested keyframe from host")
    }
    
    // MARK: - Remote App Streaming
    
    /// Request list of available apps from the host
    func requestAppList() {
        guard let endpoint = hostEndpoint else {
            print("❌ ClientSession: Cannot request app list - no host endpoint")
            return
        }
        
        print("📋 ClientSession: Requesting app list from host...")
        
        DispatchQueue.main.async {
            self.isLoadingApps = true
        }
        
        let packet = LocalCastPacket(
            type: .appListRequest,
            sequenceNumber: 0,
            timestamp: Date().timeIntervalSince1970,
            payload: Data()
        )
        transport.send(packet: packet, to: endpoint)
    }
    
    /// Request to stream a specific window
    func requestStreamWindow(windowID: UInt32, windowTitle: String) {
        guard let endpoint = hostEndpoint else {
            print("❌ ClientSession: Cannot request stream - no host endpoint")
            return
        }
        
        print("🎬 ClientSession: Requesting window stream: '\(windowTitle)' (ID: \(windowID))")
        
        let request = StreamRequest(
            type: .window,
            processID: nil,
            windowID: windowID,
            appName: windowTitle
        )
        
        sendStreamRequest(request, to: endpoint)
    }
    
    /// Request to stream a specific app (all its windows)
    func requestStreamApp(processID: Int32, appName: String) {
        guard let endpoint = hostEndpoint else {
            print("❌ ClientSession: Cannot request stream - no host endpoint")
            return
        }
        
        print("🎬 ClientSession: Requesting app stream: '\(appName)' (PID: \(processID))")
        
        let request = StreamRequest(
            type: .app,
            processID: processID,
            windowID: nil,
            appName: appName
        )
        
        sendStreamRequest(request, to: endpoint)
    }
    
    /// Request to stream the full display
    func requestStreamFullDisplay() {
        guard let endpoint = hostEndpoint else {
            print("❌ ClientSession: Cannot request stream - no host endpoint")
            return
        }
        
        print("🎬 ClientSession: Requesting full display stream")
        
        let request = StreamRequest(
            type: .fullDisplay,
            processID: nil,
            windowID: nil,
            appName: "Full Display"
        )
        
        sendStreamRequest(request, to: endpoint)
    }
    
    private func sendStreamRequest(_ request: StreamRequest, to endpoint: NWEndpoint) {
        do {
            let payload = try JSONEncoder().encode(request)
            print("🎬 ClientSession: Sending stream request packet")
            print("   Type: \(request.type)")
            print("   ProcessID: \(request.processID ?? -1)")
            print("   WindowID: \(request.windowID ?? 0)")
            print("   AppName: \(request.appName ?? "nil")")
            print("   Payload size: \(payload.count) bytes")
            print("   Endpoint: \(endpoint)")
            
            let packet = LocalCastPacket(
                type: .streamAppRequest,
                sequenceNumber: 0,
                timestamp: Date().timeIntervalSince1970,
                payload: payload
            )
            transport.send(packet: packet, to: endpoint)
            print("🎬 ClientSession: Stream request packet sent ✓")
        } catch {
            print("❌ ClientSession: Failed to encode stream request: \(error)")
        }
    }
    
    @MainActor
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
        // Send first heartbeat immediately
        sendHeartbeat()
    }
    
    private func sendHeartbeat() {
        guard let endpoint = hostEndpoint else { return }
        let heartbeat = LocalCastPacket(
            type: .heartbeat,
            sequenceNumber: 0,
            timestamp: Date().timeIntervalSince1970,
            payload: Data()
        )
        transport.send(packet: heartbeat, to: endpoint)
    }
    
    // MARK: - UDPTransportDelegate
    
    func udpTransport(_ transport: UDPTransport, didReceivePacket packet: LocalCastPacket, from endpoint: NWEndpoint) {
        switch packet.type {
        case .videoFrame:
            frameCount += 1
            if frameCount == 1 || frameCount % 60 == 0 {
                print("📦 ClientSession: Received video frame #\(frameCount), size: \(packet.payload.count) bytes")
            }
            decoder.decode(packet.payload)
            
            // Update connected state on first frame
            if !isConnected {
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.connectionStatus = "Connected"
                    self.logger.info("LocalCast: First video frame received - connected!")
                }
            }
            
            // Update stats every second
            let now = Date()
            if now.timeIntervalSince(lastStatsUpdate) >= 1.0 {
                let fps = frameCount
                frameCount = 0
                lastStatsUpdate = now
                
                DispatchQueue.main.async {
                    self.stats = LocalCastStats(
                        latencyMs: 0, // TODO: Calculate from heartbeat RTT
                        fps: fps,
                        bitrateMbps: 0 // TODO: Calculate from data rate
                    )
                }
            }
            
        case .heartbeat:
            // Pong received - calculate latency
            lastHeartbeatResponse = Date()
            if !isConnected {
                DispatchQueue.main.async {
                    self.connectionStatus = "Waiting for video..."
                }
            }
            
        case .stats:
            // Update UI stats from host
            break
            
        case .appListResponse:
            // Host sent us a list of available apps
            print("📋 ClientSession: Received app list response (\(packet.payload.count) bytes)")
            handleAppListResponse(packet.payload)
            
        case .streamAppResponse:
            // Host confirmed stream started (or failed)
            print("🎬 ClientSession: Received stream response")
            handleStreamResponse(packet.payload)
            
        default:
            print("❓ ClientSession: Received unknown packet type: \(packet.type)")
        }
    }
    
    private func handleAppListResponse(_ payload: Data) {
        do {
            let apps = try JSONDecoder().decode([RemoteAppInfo].self, from: payload)
            print("📋 ClientSession: Decoded \(apps.count) remote apps")
            
            DispatchQueue.main.async {
                self.remoteApps = apps
                self.isLoadingApps = false
                self.delegate?.clientSession(self, didReceiveAppList: apps)
            }
        } catch {
            print("❌ ClientSession: Failed to decode app list: \(error)")
            DispatchQueue.main.async {
                self.isLoadingApps = false
            }
        }
    }
    
    private func handleStreamResponse(_ payload: Data) {
        do {
            let response = try JSONDecoder().decode(StreamResponse.self, from: payload)
            print("🎬 ClientSession: Stream response - success: \(response.success), target: \(response.streamingTarget ?? "none")")
            
            if response.success {
                // Reset decoder state so it picks up the new SPS/PPS from the switched stream.
                // Without this, stale parameter sets can cause decode failures or green frames.
                print("🎬 ClientSession: Resetting decoder for new stream")
                decoder.invalidate()
                
                // Request a keyframe to ensure we get fresh SPS/PPS + IDR
                requestKeyFrame()
            }
            
            DispatchQueue.main.async {
                self.delegate?.clientSession(self, didReceiveStreamResponse: response)
                
                if response.success {
                    self.connectionStatus = "Streaming: \(response.streamingTarget ?? "Connected")"
                }
            }
        } catch {
            print("❌ ClientSession: Failed to decode stream response: \(error)")
        }
    }
    
    func udpTransport(_ transport: UDPTransport, clientDidConnect endpoint: NWEndpoint, connection: NWConnection) {
        // Not used on client side
    }
    
    // MARK: - VideoDecoderDelegate
    
    func videoDecoder(_ decoder: VideoDecoder, didDecode imageBuffer: CVImageBuffer) {
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let size = CGSize(width: width, height: height)
        
        if remoteResolution == nil || remoteResolution != size {
            remoteResolution = size
            DispatchQueue.main.async {
                self.delegate?.clientSession(self, didUpdateResolution: size)
            }
        }
        
        // IMPORTANT: Update renderer synchronously (or at least within the same callback scope)
        // to prevent VideoToolbox from recycling the buffer before we create the Metal texture.
        // The renderer's update method creates a Metal texture which retains the buffer contents.
        self.renderer?.update(with: imageBuffer)
    }
}

