import Foundation
import Network
import CryptoKit
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
    
    // MARK: - Auth
    
    /// Password for authentication. Nil = no auth required.
    private var password: String?
    
    /// Our 32-byte nonce used during the auth handshake.
    private var clientNonce: Data?
    
    /// Whether we're currently waiting for auth to complete.
    @Published var isAuthenticating = false
    
    /// Auth error message, if any.
    @Published var authError: String?
    
    init(device: DiscoveredDevice) {
        self.device = device
        transport.delegate = self
        decoder.delegate = self
    }
    
    func connect(password: String? = nil) async throws {
        self.password = password
        
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
        
        if let password = password, !password.isEmpty {
            // Auth required — start the handshake instead of heartbeat
            await MainActor.run {
                self.isAuthenticating = true
                self.connectionStatus = "Authenticating..."
            }
            sendAuthRequest()
        } else {
            // No auth — go straight to heartbeat + keyframes
            startPostAuthFlow()
        }
    }
    
    /// Begin the normal post-auth flow: heartbeat + keyframe requests.
    private func startPostAuthFlow() {
        DispatchQueue.main.async { [weak self] in
            self?.startHeartbeat()
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
    
    // MARK: - Auth Handshake (Client Side)
    
    /// Step 1: generate clientNonce and send authRequest.
    private func sendAuthRequest() {
        guard let endpoint = hostEndpoint else { return }
        
        let nonce = SessionCrypto.generateNonce()
        self.clientNonce = nonce
        
        let packet = LocalCastPacket(
            type: .authRequest,
            sequenceNumber: 0,
            timestamp: Date().timeIntervalSince1970,
            payload: nonce
        )
        transport.send(packet: packet, to: endpoint)
        logger.info("🔐 Sent authRequest with 32-byte nonce")
    }
    
    /// Step 2: handle authChallenge from host.
    private func handleAuthChallenge(payload: Data) {
        guard payload.count > 32 else {
            logger.warning("🔐 authChallenge too short (\(payload.count) bytes)")
            return
        }
        guard let password = password, let clientNonce = clientNonce else {
            logger.warning("🔐 authChallenge received but no password or nonce stored")
            return
        }
        
        // Extract hostNonce (first 32 bytes) and encrypted session key (rest)
        let hostNonce = payload.prefix(32)
        let encryptedSessionKey = Data(payload.dropFirst(32))
        
        // Derive pairingKey from password + nonces
        let pairingKey = SessionCrypto.derivePairingKey(password: password, clientNonce: clientNonce, hostNonce: Data(hostNonce))
        
        // Decrypt the session key
        guard let sessionKeyData = SessionCrypto.decrypt(encryptedSessionKey, using: pairingKey) else {
            logger.warning("🔐 Failed to decrypt session key — wrong password?")
            DispatchQueue.main.async {
                self.authError = "Authentication failed — wrong password"
                self.isAuthenticating = false
                self.connectionStatus = "Auth failed"
            }
            return
        }
        
        let sessionKey = SessionCrypto.importKey(sessionKeyData)
        
        // Send proof: encrypt "AUTH-OK" with the session key
        guard let proof = SessionCrypto.encrypt(Data("AUTH-OK".utf8), using: sessionKey) else {
            logger.error("🔐 Failed to create auth proof")
            return
        }
        
        // Store the session key temporarily (we'll set it on transport after authSuccess)
        self.pendingSessionKey = sessionKey
        
        guard let endpoint = hostEndpoint else { return }
        let packet = LocalCastPacket(
            type: .authComplete,
            sequenceNumber: 0,
            timestamp: Date().timeIntervalSince1970,
            payload: proof
        )
        transport.send(packet: packet, to: endpoint)
        logger.info("🔐 Sent authComplete proof")
    }
    
    /// Temporary storage for session key between authChallenge and authSuccess.
    private var pendingSessionKey: SymmetricKey?
    
    /// Step 3: handle authSuccess from host — enable encryption and start streaming.
    private func handleAuthSuccess(payload: Data) {
        guard let sessionKey = pendingSessionKey else {
            logger.warning("🔐 authSuccess received but no pending session key")
            return
        }
        
        // Enable encryption on the transport
        transport.sessionKey = sessionKey
        pendingSessionKey = nil
        
        logger.info("🔐 ✅ Authenticated — encryption enabled")
        
        DispatchQueue.main.async {
            self.isAuthenticating = false
            self.authError = nil
            self.connectionStatus = "Authenticated"
        }
        
        // Start the normal post-auth flow
        startPostAuthFlow()
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
    
    /// Ask the host to resize the streamed window to match the viewer dimensions.
    func sendWindowResize(width: Double, height: Double) {
        guard let endpoint = hostEndpoint else { return }
        
        var data = Data()
        var w = width.bitPattern.bigEndian
        var h = height.bitPattern.bigEndian
        withUnsafeBytes(of: &w) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &h) { data.append(contentsOf: $0) }
        
        let packet = LocalCastPacket(
            type: .windowResize,
            sequenceNumber: 0,
            timestamp: Date().timeIntervalSince1970,
            payload: data
        )
        transport.send(packet: packet, to: endpoint)
        logger.info("📐 Sent window resize request: \(width)x\(height)")
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
            
        case .authChallenge:
            handleAuthChallenge(payload: packet.payload)
            
        case .authSuccess:
            handleAuthSuccess(payload: packet.payload)
            
        default:
            print("❓ ClientSession: Received unknown packet type: \(packet.type)")
        }
    }
    
    private func handleAppListResponse(_ payload: Data) {
        guard payload.count < 512_000 else {
            print("❌ ClientSession: App list payload too large (\(payload.count) bytes), ignoring")
            return
        }
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

