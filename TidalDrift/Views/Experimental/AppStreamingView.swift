import SwiftUI

/// Experimental view for app-specific streaming
struct AppStreamingView: View {
    @StateObject private var service = AppStreamingService.shared
    @State private var showingInfo = false
    @State private var showingPermissionAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()
            
            if !service.isExperimentalEnabled {
                experimentalDisabledView
            } else {
                content
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .alert("Screen Recording Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open System Settings") {
                openScreenRecordingSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("TidalDrift needs screen recording permission to list available apps for streaming.")
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.orange)
                    Text("App-Specific Streaming")
                        .font(.headline)
                    
                    Text("EXPERIMENTAL")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
                
                Text("Stream a single app instead of your entire desktop")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                showingInfo = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingInfo) {
                infoPopover
            }
        }
        .padding()
    }
    
    private var experimentalDisabledView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "flask")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("Experimental Feature")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("App-specific streaming allows you to share just one application window instead of your entire desktop.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            VStack(spacing: 12) {
                Toggle("Enable Experimental Features", isOn: Binding(
                    get: { service.isExperimentalEnabled },
                    set: { service.setExperimentalEnabled($0) }
                ))
                .toggleStyle(.switch)
                
                Text("This feature is still in development")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
    
    private var content: some View {
        VStack(spacing: 0) {
            // Quick summary bar
            if !service.availableApps.isEmpty {
                quickSummaryBar
                Divider()
            }
            
            HSplitView {
                appList
                    .frame(minWidth: 200)
                
                detailView
                    .frame(minWidth: 250)
            }
        }
    }
    
    private var quickSummaryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Apps count badge
                HStack(spacing: 6) {
                    Image(systemName: "app.badge.fill")
                        .foregroundColor(.blue)
                    Text("\(service.availableApps.count) Apps Available")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                
                Divider()
                    .frame(height: 20)
                
                // Quick app icons
                ForEach(service.availableApps.prefix(8)) { app in
                    Button {
                        service.selectApp(app)
                    } label: {
                        HStack(spacing: 6) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "app.dashed")
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.secondary)
                            }
                            Text(app.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            service.selectedApp?.id == app.id 
                                ? Color.accentColor.opacity(0.2) 
                                : Color.secondary.opacity(0.1)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                if service.availableApps.count > 8 {
                    Text("+\(service.availableApps.count - 8) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Running Apps")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button {
                    Task {
                        await service.refreshAvailableApps()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(service.isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            Divider()
            
            if service.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading apps...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else if service.availableApps.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("No apps found")
                        .foregroundColor(.secondary)
                    Button("Grant Permission") {
                        showingPermissionAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(service.availableApps) { app in
                            AppRow(app: app, isSelected: service.selectedApp?.id == app.id)
                                .onTapGesture {
                                    service.selectApp(app)
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if service.availableApps.isEmpty {
                Task {
                    await service.refreshAvailableApps()
                }
            }
        }
    }
    
    private var detailView: some View {
        VStack {
            if let app = service.selectedApp {
                selectedAppDetail(app)
            } else {
                emptySelection
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var emptySelection: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Select an App")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Choose an app from the list to stream")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func selectedAppDetail(_ app: StreamableApp) -> some View {
        VStack(spacing: 20) {
            // App header
            VStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                }
                
                Text(app.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let bundleId = app.bundleIdentifier {
                    Text(bundleId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 20)
            
            Divider()
                .padding(.horizontal)
            
            // Windows section
            VStack(alignment: .leading, spacing: 8) {
                Text("Windows (\(app.windows.count))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(app.windows) { window in
                    WindowRow(
                        window: window,
                        isSelected: service.selectedWindow?.id == window.id
                    )
                    .onTapGesture {
                        service.selectWindow(window)
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Actions
            VStack(spacing: 12) {
                Button {
                    service.bringAppToFront()
                } label: {
                    Label("Bring to Front", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                if let info = service.getStreamingInfo() {
                    Text(info.note)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button {
                        // Open standard screen sharing for now
                        if let url = URL(string: info.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Start Screen Sharing", systemImage: "rectangle.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }
    
    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About App-Specific Streaming")
                .font(.headline)
            
            Text("""
            This experimental feature aims to let you stream just a single application instead of your entire desktop.
            
            Current Limitations:
            • Standard VNC/ARD protocols don't support single-app streaming
            • Requires screen recording permission
            • Currently shows apps and opens standard screen sharing
            
            Future Plans:
            • Custom streaming protocol
            • WebRTC-based app streaming
            • Window-specific capture and broadcast
            """)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 300)
    }
    
    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct AppRow: View {
    let app: StreamableApp
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 24, height: 24)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text("\(app.windows.count) window\(app.windows.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }
}

struct WindowRow: View {
    let window: StreamableWindow
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow")
                .foregroundColor(isSelected ? .accentColor : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "Untitled" : window.title)
                    .font(.caption)
                    .lineLimit(1)
                
                Text("\(Int(window.bounds.width))×\(Int(window.bounds.height))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if window.isOnScreen {
                Text("visible")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}

struct AppStreamingView_Previews: PreviewProvider {
    static var previews: some View {
        AppStreamingView()
    }
}

