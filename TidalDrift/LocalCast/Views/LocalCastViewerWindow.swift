import SwiftUI
import MetalKit

class LocalCastViewerWindowController: NSWindowController, ClientSessionDelegate {
    private let device: DiscoveredDevice
    private let clientSession: ClientSession
    private var localMonitors: [Any] = []
    private var remoteResolution: CGSize = CGSize(width: 1280, height: 720)
    
    init(device: DiscoveredDevice, session: ClientSession) {
        print("🎮 LocalCastViewerWindowController: INIT START for \(device.name)")
        NSLog("🎮 LocalCastViewerWindowController: INIT START for %@", device.name)
        
        self.device = device
        self.clientSession = session
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "\(device.name) - LocalCast"
        window.isReleasedWhenClosed = false
        window.center()
        window.acceptsMouseMovedEvents = true
        
        // Set up Metal view
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false // Need this for sampling in shader
        
        // Wrap in hosting view with overlay
        let contentView = LocalCastContentView(
            mtkView: mtkView,
            session: session
        )
        window.contentView = NSHostingView(rootView: contentView)
        
        super.init(window: window)
        
        session.renderer = MetalRenderer(mtkView: mtkView)
        session.delegate = self
        
        print("🎮 LocalCastViewerWindowController: Calling setupInputCapture()...")
        NSLog("🎮 LocalCastViewerWindowController: Calling setupInputCapture()...")
        
        // Set up input capture
        setupInputCapture()
        
        print("🎮 LocalCastViewerWindowController: INIT COMPLETE ✓")
        NSLog("🎮 LocalCastViewerWindowController: INIT COMPLETE ✓")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    // MARK: - ClientSessionDelegate
    
    func clientSession(_ session: ClientSession, didDisconnectWithReason reason: String) {
        // Handle disconnect if needed
    }
    
    func clientSession(_ session: ClientSession, didUpdateResolution size: CGSize) {
        self.remoteResolution = size
        
        DispatchQueue.main.async {
            guard let window = self.window else { return }
            
            // Adjust window aspect ratio or size if needed
            // For now, let's just update the internal resolution for coordinate mapping
            print("🌊 LocalCast: Remote resolution updated to \(size.width)x\(size.height)")
            
            // If the window is still the default size, maybe resize it to fit the remote screen (scaled down if too big)
            if window.frame.width == 1280 && window.frame.height == 720 {
                let screenFrame = NSScreen.main?.visibleFrame ?? .zero
                let maxWidth = screenFrame.width * 0.8
                let maxHeight = screenFrame.height * 0.8
                
                let scale = min(maxWidth / size.width, maxHeight / size.height, 1.0)
                let newWidth = size.width * scale
                let newHeight = size.height * scale
                
                let newFrame = NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y,
                    width: newWidth,
                    height: newHeight
                )
                window.setFrame(newFrame, display: true, animate: true)
            }
        }
    }
    
    private var inputCaptureCount = 0
    
    private func setupInputCapture() {
        print("🎮 LocalCastViewer: Setting up input capture...")
        print("🎮 LocalCastViewer: Window = \(String(describing: window))")
        print("🎮 LocalCastViewer: Window accepts mouse: \(window?.acceptsMouseMovedEvents ?? false)")
        
        // Make window accept first responder for keyboard events
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
        
        print("🎮 LocalCastViewer: Window is key: \(window?.isKeyWindow ?? false)")
        print("🎮 LocalCastViewer: First responder: \(String(describing: window?.firstResponder))")
        
        // Monitor local events when our window is key
        // Use a broader matching to ensure we capture events
        let mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]) { [weak self] event in
            guard let self = self else { return event }
            guard let window = self.window else { return event }
            
            // Log ALL mouse events for debugging (first 10)
            self.inputCaptureCount += 1
            if self.inputCaptureCount <= 10 {
                print("🖱️ LOCAL MONITOR: Event type=\(event.type.rawValue), window=\(event.window == window ? "OURS" : "OTHER")")
            }
            
            // Check if event is for our window
            guard event.window == window else { return event }
            
            // Get location relative to the content view (where the video is)
            if let contentView = window.contentView {
                let point = contentView.convert(event.locationInWindow, from: nil)
                self.handleMouseEvent(event, at: point)
            }
            
            return event
        }
        
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            guard let window = self.window else { return event }
            guard event.window == window else { return event }
            
            self.handleKeyEvent(event)
            
            // Consume keyboard events to prevent system beeps
            return nil 
        }
        
        // Also add global monitor for when window might not be getting events properly
        // This catches events that go to child views/SwiftUI layers
        let globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]) { [weak self] event in
            guard let self = self else { return }
            guard let window = self.window else { return }
            
            // Get mouse location in screen coordinates
            let mouseLocation = NSEvent.mouseLocation
            let windowFrame = window.frame
            
            // Check if click is inside our window
            if NSPointInRect(mouseLocation, windowFrame) {
                if let contentView = window.contentView {
                    let windowPoint = window.convertPoint(fromScreen: mouseLocation)
                    let point = contentView.convert(windowPoint, from: nil)
                    
                    // Calculate normalized coordinates
                    let contentRect = contentView.frame
                    guard point.x >= 0 && point.x <= contentRect.width &&
                          point.y >= 0 && point.y <= contentRect.height else { return }
                    
                    let relativeX = point.x / contentRect.width
                    let relativeY = 1.0 - (point.y / contentRect.height)
                    
                    // Send the input via global monitor (backup path)
                    switch event.type {
                    case .leftMouseDown:
                        print("🎮 GLOBAL: LEFT MOUSE DOWN at (\(String(format: "%.2f", relativeX)), \(String(format: "%.2f", relativeY)))")
                        self.clientSession.sendInput(.mouseDown(button: 0, x: relativeX, y: relativeY))
                    case .leftMouseUp:
                        print("🎮 GLOBAL: LEFT MOUSE UP at (\(String(format: "%.2f", relativeX)), \(String(format: "%.2f", relativeY)))")
                        self.clientSession.sendInput(.mouseUp(button: 0, x: relativeX, y: relativeY))
                    case .rightMouseDown:
                        print("🎮 GLOBAL: RIGHT MOUSE DOWN")
                        self.clientSession.sendInput(.mouseDown(button: 1, x: relativeX, y: relativeY))
                    case .rightMouseUp:
                        print("🎮 GLOBAL: RIGHT MOUSE UP")
                        self.clientSession.sendInput(.mouseUp(button: 1, x: relativeX, y: relativeY))
                    default:
                        break
                    }
                }
            }
        }
        
        localMonitors.append(mouseMonitor as Any)
        localMonitors.append(keyMonitor as Any)
        localMonitors.append(globalMouseMonitor as Any)
        print("🎮 LocalCastViewer: Input capture set up ✓ (local + global monitors)")
    }
    
    private func handleMouseEvent(_ event: NSEvent, at point: NSPoint) {
        guard let window = self.window, let contentView = window.contentView else { return }
        
        let contentRect = contentView.frame
        
        // Ensure point is within bounds
        guard point.x >= 0 && point.x <= contentRect.width &&
              point.y >= 0 && point.y <= contentRect.height else {
            return
        }
        
        // Translate point to 0...1 relative (normalized) coordinates
        let relativeX = point.x / contentRect.width
        let relativeY = 1.0 - (point.y / contentRect.height) // Flip Y (0 is top)
        
        inputCaptureCount += 1
        
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            clientSession.sendInput(.mouseMove(x: relativeX, y: relativeY))
            
        case .leftMouseDown:
            print("🖱️ LocalCastViewer: LEFT MOUSE DOWN at (\(String(format: "%.2f", relativeX)), \(String(format: "%.2f", relativeY)))")
            clientSession.sendInput(.mouseDown(button: 0, x: relativeX, y: relativeY))
            
        case .leftMouseUp:
            print("🖱️ LocalCastViewer: LEFT MOUSE UP at (\(String(format: "%.2f", relativeX)), \(String(format: "%.2f", relativeY)))")
            clientSession.sendInput(.mouseUp(button: 0, x: relativeX, y: relativeY))
            
        case .rightMouseDown:
            print("🖱️ LocalCastViewer: RIGHT MOUSE DOWN")
            clientSession.sendInput(.mouseDown(button: 1, x: relativeX, y: relativeY))
            
        case .rightMouseUp:
            print("🖱️ LocalCastViewer: RIGHT MOUSE UP")
            clientSession.sendInput(.mouseUp(button: 1, x: relativeX, y: relativeY))
            
        case .scrollWheel:
            // Scroll delta doesn't need normalization
            clientSession.sendInput(.scroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY))
            
        default:
            break
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.rawValue
        
        switch event.type {
        case .keyDown:
            print("⌨️ LocalCastViewer: KEY DOWN keyCode=\(keyCode)")
            clientSession.sendInput(.keyDown(keyCode: keyCode, modifiers: UInt64(modifiers)))
        case .keyUp:
            print("⌨️ LocalCastViewer: KEY UP keyCode=\(keyCode)")
            clientSession.sendInput(.keyUp(keyCode: keyCode, modifiers: UInt64(modifiers)))
        case .flagsChanged:
            // This is tricky as we don't know if it's down or up easily without tracking state
            // For now, let's just send as a keyDown if any flags are set, but this needs improvement
            break
        default:
            break
        }
    }
    
    override func close() {
        for monitor in localMonitors {
            NSEvent.removeMonitor(monitor)
        }
        localMonitors.removeAll()
        clientSession.disconnect()
        super.close()
    }
}

struct LocalCastContentView: View {
    let mtkView: MTKView
    @ObservedObject var session: ClientSession
    @AppStorage("showLatencyOverlay") var showOverlay = false
    @State private var showAppPicker = false
    @State private var selectedRemoteApp: RemoteAppInfo?
    
    var body: some View {
        ZStack {
            MetalViewRepresentable(mtkView: mtkView)
            
            // Top bar with controls
            VStack {
                HStack {
                    // App picker button
                    Button {
                        if session.remoteApps.isEmpty {
                            session.requestAppList()
                        }
                        showAppPicker.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.stack.3d.up")
                            Text("Apps")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .help("Browse remote apps to stream")
                    
                    Spacer()
                    
                    if showOverlay {
                        LocalCastStatsOverlay(stats: session.stats)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                
                Spacer()
            }
            
            // App picker overlay
            if showAppPicker {
                RemoteAppPickerView(
                    session: session,
                    isPresented: $showAppPicker,
                    selectedApp: $selectedRemoteApp
                )
            }
        }
    }
}

/// View for picking which remote app to stream
struct RemoteAppPickerView: View {
    @ObservedObject var session: ClientSession
    @Binding var isPresented: Bool
    @Binding var selectedApp: RemoteAppInfo?
    @State private var expandedAppID: Int32?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Remote Apps")
                    .font(.headline)
                Spacer()
                
                Button {
                    session.requestAppList()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(session.isLoadingApps)
                
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            if session.isLoadingApps {
                VStack {
                    ProgressView()
                    Text("Loading apps...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.remoteApps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No apps available")
                        .foregroundStyle(.secondary)
                    Button("Refresh") {
                        session.requestAppList()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Full display option
                        Button {
                            session.requestStreamFullDisplay()
                            isPresented = false
                        } label: {
                            HStack {
                                Image(systemName: "display")
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(.blue)
                                Text("Full Display")
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.blue.opacity(0.1))
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // App list
                        ForEach(session.remoteApps, id: \.processID) { app in
                            RemoteAppRowView(
                                app: app,
                                isExpanded: expandedAppID == app.processID,
                                onTap: {
                                    withAnimation {
                                        if expandedAppID == app.processID {
                                            expandedAppID = nil
                                        } else {
                                            expandedAppID = app.processID
                                        }
                                    }
                                },
                                onStreamApp: {
                                    session.requestStreamApp(processID: app.processID, appName: app.name)
                                    isPresented = false
                                },
                                onStreamWindow: { window in
                                    session.requestStreamWindow(windowID: window.windowID, windowTitle: "\(app.name) - \(window.title)")
                                    isPresented = false
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 320, height: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .padding(40)
    }
}

struct RemoteAppRowView: View {
    let app: RemoteAppInfo
    let isExpanded: Bool
    let onTap: () -> Void
    let onStreamApp: () -> Void
    let onStreamWindow: (RemoteWindowInfo) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // App row
            Button(action: onTap) {
                HStack {
                    // App icon placeholder
                    Image(systemName: "app.fill")
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .fontWeight(.medium)
                        Text("\(app.windows.count) window\(app.windows.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Stream whole app button
                    Button {
                        onStreamApp()
                    } label: {
                        Image(systemName: "play.circle")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.borderless)
                    .help("Stream entire app")
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded window list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(app.windows, id: \.windowID) { window in
                        Button {
                            onStreamWindow(window)
                        } label: {
                            HStack {
                                Image(systemName: window.isOnScreen ? "macwindow" : "macwindow.badge.plus")
                                    .frame(width: 24)
                                    .foregroundStyle(window.isOnScreen ? .primary : .secondary)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(window.title)
                                        .lineLimit(1)
                                    Text("\(window.width) × \(window.height)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal)
                            .padding(.leading, 24)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.primary.opacity(0.05))
                    }
                }
            }
        }
    }
}

struct MetalViewRepresentable: NSViewRepresentable {
    let mtkView: MTKView
    
    func makeNSView(context: Context) -> MTKView {
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {}
}

struct LocalCastStatsOverlay: View {
    let stats: LocalCastStats?
    
    var body: some View {
        if let stats = stats {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(stats.latencyMs))ms")
                    .font(.system(.caption, design: .monospaced))
                Text("\(stats.fps) fps")
                    .font(.system(.caption, design: .monospaced))
                Text("\(String(format: "%.1f", stats.bitrateMbps)) Mbps")
                    .font(.system(.caption, design: .monospaced))
            }
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

