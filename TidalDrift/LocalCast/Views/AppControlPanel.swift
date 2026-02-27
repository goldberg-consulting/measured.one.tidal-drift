import SwiftUI
import AppKit

// MARK: - Floating App Control Panel (NSPanel)

/// A floating utility panel that provides remote app control alongside
/// macOS Screen Sharing. Connects to the host via TidalDrift's control
/// channel to enumerate and focus remote apps.
class AppControlPanelController: NSWindowController {
    private let session: ClientSession
    private let device: DiscoveredDevice
    
    /// Called when the panel is closed.
    var onClose: ((AppControlPanelController) -> Void)?
    
    init(device: DiscoveredDevice, session: ClientSession) {
        self.device = device
        self.session = session
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 460),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.title = "\(device.name) — App Control"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let contentView = AppControlPanelView(session: session, deviceName: device.name)
        panel.contentView = NSHostingView(rootView: contentView)
        
        // Position in the top-right corner of the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelX = screenFrame.maxX - 320
            let panelY = screenFrame.maxY - 480
            panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        }
        
        super.init(window: panel)
        panel.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    deinit {
        session.disconnect()
    }
    
    override func close() {
        session.disconnect()
        onClose?(self)
        onClose = nil
        super.close()
    }
}

extension AppControlPanelController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // close() handles cleanup; this fires for user-initiated close via title bar
        if onClose != nil {
            session.disconnect()
            onClose?(self)
            onClose = nil
        }
    }
}

// MARK: - SwiftUI Content

struct AppControlPanelView: View {
    @ObservedObject var session: ClientSession
    let deviceName: String
    @State private var expandedAppID: Int32?
    @State private var isolatedAppPID: Int32?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Connection status
            if !session.isConnected && session.connectionPhase != .streaming {
                connectionStatus
            }
            
            // App list
            if session.isLoadingApps {
                loadingView
            } else if session.remoteApps.isEmpty {
                emptyView
            } else {
                appList
            }
        }
        .frame(minWidth: 280, minHeight: 200)
        .onAppear {
            // Auto-request the app list once the control channel connects
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if session.remoteApps.isEmpty {
                    session.requestAppList()
                }
            }
        }
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Control")
                        .font(.headline)
                    Text(deviceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    session.requestAppList()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(session.isLoadingApps)
                .help("Refresh app list")
            }
            
            if isolatedAppPID != nil {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                    
                    if let app = session.remoteApps.first(where: { $0.processID == isolatedAppPID }) {
                        Text("Isolated: \(app.name)")
                            .font(.caption)
                            .fontWeight(.medium)
                    } else {
                        Text("App Isolated")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    Button {
                        session.requestRestoreApps()
                        isolatedAppPID = nil
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.open.fill")
                            Text("Restore All")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
        .padding()
    }
    
    private var connectionStatus: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(session.connectionPhase.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading remote apps...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No apps found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Refresh") {
                session.requestAppList()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(session.remoteApps, id: \.processID) { app in
                    appRow(app)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private func appRow(_ app: RemoteAppInfo) -> some View {
        VStack(spacing: 0) {
            // Main row
            HStack {
                Image(systemName: "app.fill")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                    Text("\(app.windows.count) window\(app.windows.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Focus button (brings to front on host)
                Button {
                    session.requestFocusApp(processID: app.processID, appName: app.name)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Focus")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .help("Bring to front on remote Mac")
                
                // Isolate button (hide all other apps for VNC single-app view)
                Button {
                    if isolatedAppPID == app.processID {
                        session.requestRestoreApps()
                        isolatedAppPID = nil
                    } else {
                        session.requestIsolateApp(processID: app.processID, appName: app.name)
                        isolatedAppPID = app.processID
                    }
                } label: {
                    Image(systemName: isolatedAppPID == app.processID ? "lock.open.fill" : "lock.fill")
                        .foregroundStyle(isolatedAppPID == app.processID ? .orange : .secondary)
                }
                .buttonStyle(.borderless)
                .help(isolatedAppPID == app.processID ? "Restore all hidden apps" : "Isolate: hide all other apps (VNC single-app view)")
                
                // Stream button (switches LocalCast capture)
                Button {
                    session.requestStreamApp(processID: app.processID, appName: app.name)
                } label: {
                    Image(systemName: "play.circle")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                .help("Stream this app via LocalCast")
                
                // Expand for windows
                if app.windows.count > 1 {
                    Button {
                        withAnimation {
                            expandedAppID = expandedAppID == app.processID ? nil : app.processID
                        }
                    } label: {
                        Image(systemName: expandedAppID == app.processID ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            
            // Expanded windows
            if expandedAppID == app.processID {
                ForEach(app.windows, id: \.windowID) { window in
                    HStack {
                        Image(systemName: "macwindow")
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        
                        Text(window.title)
                            .font(.caption)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(window.width) x \(window.height)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        
                        Button {
                            session.requestStreamWindow(windowID: window.windowID, windowTitle: "\(app.name) - \(window.title)")
                        } label: {
                            Image(systemName: "play.circle")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Stream this window")
                    }
                    .padding(.horizontal, 12)
                    .padding(.leading, 24)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.03))
                }
            }
        }
    }
}
