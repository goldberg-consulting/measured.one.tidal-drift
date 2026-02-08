import Foundation
import Combine
import Network
import AppKit
import CoreGraphics
import OSLog

@MainActor
protocol LocalCastServiceDelegate: AnyObject {
    func localCastDidStartHosting()
    func localCastDidStopHosting()
    func localCastDidConnect(to device: DiscoveredDevice)
    func localCastDidDisconnect(from device: DiscoveredDevice, reason: LocalCastDisconnectReason)
    func localCastDidReceiveStats(_ stats: LocalCastStats)
}

enum LocalCastDisconnectReason {
    case userInitiated
    case connectionLost
    case remoteEnded
    case error(String)
}

struct LocalCastStats {
    let latencyMs: Double
    let fps: Int
    let bitrateMbps: Double
}

struct LocalCastConnection: Identifiable {
    let id: UUID
    let device: DiscoveredDevice
    let startTime: Date
    var clientName: String { device.name }
}

@MainActor
class LocalCastService: ObservableObject {
    static let shared = LocalCastService()
    private let logger = Logger(subsystem: "com.tidaldrift", category: "LocalCastService")

    @Published var isHosting = false
    @Published var activeConnections: [LocalCastConnection] = []
    @Published var currentStats: LocalCastStats?

    weak var delegate: LocalCastServiceDelegate?
    var configuration: LocalCastConfiguration = .default

    private var hostSession: HostSession?
    private var advertisementProcess: Process?
    private let serviceType = "_tidaldrift-cast._udp"

    private init() {}

    // MARK: - Host Mode

    func startHosting(display: CGDirectDisplayID? = nil) async throws {
        try await startHosting(target: .fullDisplay)
    }

    func startHostingWindow(windowID: CGWindowID, windowTitle: String) async throws {
        try await startHosting(target: .window(windowID, title: windowTitle))
    }

    func startHostingApp(processID: pid_t, appName: String) async throws {
        try await startHosting(target: .app(processID, name: appName))
    }

    private func startHosting(target: HostCaptureTarget) async throws {
        let permissions = LocalCastPermissions()

        // Request screen capture (prompts the user once; passive after that).
        // If still not granted, throw so the UI can show "Open System Settings".
        if !permissions.requestScreenCaptureIfNeeded() {
            throw LocalCastError.permissionDenied(.screenCapture)
        }

        // Accessibility is optional -- streaming works without it, just no input control.
        await permissions.checkPermissions()  // refresh accessibility status
        if !permissions.accessibilityGranted {
            logger.warning("Accessibility permission not granted -- input forwarding disabled")
        }

        let session = HostSession(configuration: configuration)
        try await session.start(target: target)

        advertiseLocalCast(port: LocalCastConfiguration.hostPort)

        self.hostSession = session
        self.isHosting = true
        delegate?.localCastDidStartHosting()
        logger.info("Hosting started")
    }

    func stopHosting() {
        self.isHosting = false
        stopAdvertisement()

        Task {
            await hostSession?.stop()
            await MainActor.run { self.hostSession = nil }
        }

        delegate?.localCastDidStopHosting()
        logger.info("Hosting stopped")
    }

    private func advertiseLocalCast(port: UInt16) {
        let displayName = NetworkUtils.sanitizedComputerName
        stopAdvertisement()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        let codec = configuration.codec == .hevc ? "hevc" : "h264"
        process.arguments = ["-R", displayName, serviceType, "local.", "\(port)", "version=1", "codec=\(codec)", "fps=\(configuration.targetFrameRate)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            self.advertisementProcess = process
            logger.debug("Bonjour advertisement started (PID: \(process.processIdentifier))")
        } catch {
            logger.error("Failed to start Bonjour advertisement: \(error.localizedDescription)")
        }
    }

    private func stopAdvertisement() {
        if let process = advertisementProcess, process.isRunning {
            process.terminate()
        }
        advertisementProcess = nil
    }

    // MARK: - Client Mode

    func connect(to device: DiscoveredDevice) async throws -> LocalCastViewerWindowController {
        logger.info("Connecting to \(device.name)")
        let session = ClientSession(device: device)
        try await session.connect()
        return LocalCastViewerWindowController(device: device, session: session)
    }

    func disconnect(from device: DiscoveredDevice) {
        activeConnections.removeAll { $0.device.id == device.id }
    }

    // MARK: - Discovery

    func supportsLocalCast(_ device: DiscoveredDevice) -> Bool {
        device.supportsLocalCast
    }

    func localCastEndpoint(for device: DiscoveredDevice) -> NWEndpoint? {
        device.localCastEndpoint
    }
}

enum LocalCastError: LocalizedError {
    case permissionDenied(Permission)
    case connectionFailed(String)
    case encoderInitializationFailed
    case decoderInitializationFailed
    case noDisplayAvailable
    case hostNotReady

    enum Permission {
        case screenCapture
        case accessibility
    }

    var errorDescription: String? {
        switch self {
        case .permissionDenied(.screenCapture):
            return "Screen recording permission required. Open System Settings > Privacy & Security > Screen Recording and enable TidalDrift."
        case .permissionDenied(.accessibility):
            return "Accessibility permission required for input control. Open System Settings > Privacy & Security > Accessibility and enable TidalDrift."
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .encoderInitializationFailed:
            return "Failed to initialize video encoder"
        case .decoderInitializationFailed:
            return "Failed to initialize video decoder"
        case .noDisplayAvailable:
            return "No display available to share"
        case .hostNotReady:
            return "Remote Mac is not ready to share"
        }
    }
}
