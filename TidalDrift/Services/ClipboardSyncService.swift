import Foundation
import AppKit
import Network
import Combine

/// Represents a clipboard item that can be synced
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let sourceDevice: String
    let sourceDeviceId: String
    let contentType: ContentType
    let textContent: String?
    let imageData: Data?
    let fileName: String?
    
    enum ContentType: String, Codable {
        case text
        case image
        case file
        case rtf
    }
    
    var preview: String {
        switch contentType {
        case .text:
            let text = textContent ?? ""
            if text.count > 50 {
                return String(text.prefix(50)) + "..."
            }
            return text
        case .image:
            return "[Image]"
        case .file:
            return fileName ?? "[File]"
        case .rtf:
            return "[Rich Text]"
        }
    }
    
    var relativeTime: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 5 {
            return "just now"
        } else if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else {
            return "\(Int(interval / 3600))h ago"
        }
    }
}

/// Service for syncing clipboard between TidalDrift instances
@MainActor
class ClipboardSyncService: ObservableObject {
    static let shared = ClipboardSyncService()
    
    @Published var isEnabled = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "clipboardSyncEnabled")
            if isEnabled {
                startMonitoring()
                startNetworkService()
            } else {
                stopMonitoring()
                stopNetworkService()
            }
        }
    }
    
    @Published var clipboardHistory: [ClipboardItem] = []
    @Published var connectedPeers: [String] = []
    @Published var lastSyncTime: Date?
    
    private var clipboardMonitorTimer: Timer?
    private var lastChangeCount: Int = 0
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var browser: NWBrowser?
    
    private let serviceType = "_tidalclip._tcp"
    private let deviceId = UUID().uuidString
    private let deviceName = Host.current().localizedName ?? "Unknown Mac"
    private let maxHistoryItems = 50
    private let clipboardPort: UInt16 = 51234
    
    private init() {
        // Default to enabled if not set
        if UserDefaults.standard.object(forKey: "clipboardSyncEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "clipboardSyncEnabled")
        }
        isEnabled = UserDefaults.standard.bool(forKey: "clipboardSyncEnabled")
        
        // Defer network operations to avoid blocking main thread during launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.isEnabled else { return }
            self.startMonitoring()
            self.startNetworkService()
        }
    }
    
    // MARK: - Clipboard Monitoring
    
    private func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        
        clipboardMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
    }
    
    private func stopMonitoring() {
        clipboardMonitorTimer?.invalidate()
        clipboardMonitorTimer = nil
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        
        // Get clipboard content
        if let item = extractClipboardItem() {
            // Add to local history
            addToHistory(item)
            
            // Broadcast to peers
            broadcastClipboardItem(item)
        }
    }
    
    private func extractClipboardItem() -> ClipboardItem? {
        let pasteboard = NSPasteboard.general
        
        // Check for text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return ClipboardItem(
                id: UUID(),
                timestamp: Date(),
                sourceDevice: deviceName,
                sourceDeviceId: deviceId,
                contentType: .text,
                textContent: text,
                imageData: nil,
                fileName: nil
            )
        }
        
        // Check for image
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            return ClipboardItem(
                id: UUID(),
                timestamp: Date(),
                sourceDevice: deviceName,
                sourceDeviceId: deviceId,
                contentType: .image,
                textContent: nil,
                imageData: imageData,
                fileName: nil
            )
        }
        
        // Check for file URL
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
            return ClipboardItem(
                id: UUID(),
                timestamp: Date(),
                sourceDevice: deviceName,
                sourceDeviceId: deviceId,
                contentType: .file,
                textContent: firstURL.absoluteString,
                imageData: nil,
                fileName: firstURL.lastPathComponent
            )
        }
        
        return nil
    }
    
    private func addToHistory(_ item: ClipboardItem) {
        // Avoid duplicates
        if let existing = clipboardHistory.first, 
           existing.textContent == item.textContent && 
           existing.contentType == item.contentType {
            return
        }
        
        clipboardHistory.insert(item, at: 0)
        
        // Limit history size
        if clipboardHistory.count > maxHistoryItems {
            clipboardHistory = Array(clipboardHistory.prefix(maxHistoryItems))
        }
    }
    
    // MARK: - Network Service
    
    private func startNetworkService() {
        startListener()
        startBrowser()
    }
    
    private func stopNetworkService() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        connectedPeers.removeAll()
    }
    
    private func startListener() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: clipboardPort)!)
            
            listener?.service = NWListener.Service(name: deviceName, type: serviceType)
            
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleIncomingConnection(connection)
                }
            }
            
            listener?.stateUpdateHandler = { state in
                #if DEBUG
                if case .failed(let error) = state {
                    print("Clipboard listener failed: \(error)")
                }
                #endif
            }
            
            listener?.start(queue: .main)
        } catch {
            #if DEBUG
            print("Failed to start clipboard listener: \(error)")
            #endif
        }
    }
    
    private func startBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = true
        
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results)
            }
        }
        
        browser?.start(queue: .main)
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var peers: [String] = []
        
        for result in results {
            if case .service(let name, _, _, _) = result.endpoint {
                // Don't connect to ourselves
                if name != deviceName {
                    peers.append(name)
                    connectToPeer(result.endpoint)
                }
            }
        }
        
        connectedPeers = peers
    }
    
    private func connectToPeer(_ endpoint: NWEndpoint) {
        // Check if already connected
        let existingConnection = connections.first { conn in
            if case .service(let name, _, _, _) = endpoint,
               case .service(let connName, _, _, _) = conn.endpoint {
                return name == connName
            }
            return false
        }
        
        guard existingConnection == nil else { return }
        
        let connection = NWConnection(to: endpoint, using: .tcp)
        connections.append(connection)
        
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.receiveFromConnection(connection)
                case .failed, .cancelled:
                    if let connection = connection {
                        self?.connections.removeAll { $0 === connection }
                    }
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.receiveFromConnection(connection)
                case .failed, .cancelled:
                    if let connection = connection {
                        self?.connections.removeAll { $0 === connection }
                    }
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func receiveFromConnection(_ connection: NWConnection?) {
        guard let connection = connection else { return }
        
        // First read the length (4 bytes)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let data = data, data.count == 4 else {
                    if !isComplete {
                        self?.receiveFromConnection(connection)
                    }
                    return
                }
                
                let length = data.withUnsafeBytes { $0.load(as: UInt32.self) }
                self?.receiveData(connection: connection, length: Int(length))
            }
        }
    }
    
    private func receiveData(connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                if let data = data {
                    self?.handleReceivedData(data)
                }
                
                if !isComplete {
                    self?.receiveFromConnection(connection)
                }
            }
        }
    }
    
    private func handleReceivedData(_ data: Data) {
        do {
            let item = try JSONDecoder().decode(ClipboardItem.self, from: data)
            
            // Don't add our own items
            guard item.sourceDeviceId != deviceId else { return }
            
            addToHistory(item)
            lastSyncTime = Date()
        } catch {
            #if DEBUG
            print("Failed to decode clipboard item: \(error)")
            #endif
        }
    }
    
    private func broadcastClipboardItem(_ item: ClipboardItem) {
        guard isEnabled else { return }
        
        do {
            let data = try JSONEncoder().encode(item)
            
            // Prepend length
            var length = UInt32(data.count)
            var packet = Data(bytes: &length, count: 4)
            packet.append(data)
            
            for connection in connections where connection.state == .ready {
                connection.send(content: packet, completion: .contentProcessed { error in
                    #if DEBUG
                    if let error = error {
                        print("Failed to send clipboard: \(error)")
                    }
                    #endif
                })
            }
        } catch {
            #if DEBUG
            print("Failed to encode clipboard item: \(error)")
            #endif
        }
    }
    
    // MARK: - Public Methods
    
    /// Copy a history item to the local clipboard
    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.contentType {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let imageData = item.imageData {
                pasteboard.setData(imageData, forType: .tiff)
            }
        case .file:
            if let urlString = item.textContent, let url = URL(string: urlString) {
                pasteboard.writeObjects([url as NSURL])
            }
        case .rtf:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        }
        
        // Update change count to avoid re-broadcasting
        lastChangeCount = pasteboard.changeCount
    }
    
    /// Clear clipboard history
    func clearHistory() {
        clipboardHistory.removeAll()
    }
    
    /// Get items from a specific device
    func items(from deviceName: String) -> [ClipboardItem] {
        clipboardHistory.filter { $0.sourceDevice == deviceName }
    }
    
    /// Check if this item is from the local device
    func isLocalItem(_ item: ClipboardItem) -> Bool {
        item.sourceDeviceId == deviceId
    }
}

