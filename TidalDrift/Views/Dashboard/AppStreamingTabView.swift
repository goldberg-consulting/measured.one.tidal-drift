import SwiftUI

struct AppStreamingTabView: View {
    @ObservedObject private var streamingService = AppStreamingService.shared
    @ObservedObject private var networkService = StreamingNetworkService.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                
                statusSection
                
                if streamingService.isExperimentalEnabled {
                    enabledContent
                } else {
                    disabledContent
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if streamingService.isExperimentalEnabled {
                Task {
                    await streamingService.refreshAvailableApps()
                }
            }
        }
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "app.connected.to.app.below.fill")
                        .font(.largeTitle)
                        .foregroundColor(.purple)
                    
                    Text("App Streaming")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("β")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                        .foregroundColor(.white)
                }
                
                Text("Stream individual app windows instead of the full desktop")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var statusSection: some View {
        HStack(spacing: 16) {
            Toggle("Enable Experimental Feature", isOn: Binding(
                get: { streamingService.isExperimentalEnabled },
                set: { streamingService.setExperimentalEnabled($0) }
            ))
            .toggleStyle(.switch)
            
            Spacer()
            
            if streamingService.isExperimentalEnabled {
                Button {
                    Task {
                        await streamingService.refreshAvailableApps()
                    }
                } label: {
                    Label("Refresh Apps", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
    
    private var disabledContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("This is an experimental feature")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("App Streaming aims to let you stream just one application window instead of the whole desktop. This could be useful for remote pair programming or sharing a specific tool.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Status:")
                    .font(.headline)
                
                BulletPoint(text: "Can list running applications and windows", done: true)
                BulletPoint(text: "Can capture window screenshots", done: true)
                BulletPoint(text: "Network discovery via Bonjour", done: false)
                BulletPoint(text: "Live streaming protocol", done: false)
                BulletPoint(text: "Remote app activation", done: false)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.1)))
            
            Text("Enable the toggle above to explore what's working so far.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
    
    private var enabledContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // My Apps section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("My Running Apps")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text("\(streamingService.availableApps.count) apps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if streamingService.availableApps.isEmpty {
                    Text("No apps detected. Make sure Screen Recording permission is granted.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)
                    ], spacing: 12) {
                        ForEach(streamingService.availableApps) { app in
                            AppCard(app: app, isSelected: streamingService.selectedApp?.id == app.id) {
                                streamingService.selectApp(app)
                            }
                        }
                    }
                }
            }
            
            // Selected app detail
            if let selectedApp = streamingService.selectedApp {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected: \(selectedApp.name)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Windows: \(selectedApp.windows.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Bring to Front") {
                            streamingService.bringAppToFront()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if selectedApp.windows.isEmpty {
                        Text("No visible windows")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(selectedApp.windows) { window in
                                    WindowCard(window: window)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.1)))
            }
            
            // Limitations note
            VStack(alignment: .leading, spacing: 8) {
                Label("Limitations", systemImage: "info.circle")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Text("This feature can detect running apps and windows, but actual streaming to another computer isn't implemented yet. It would require building a custom protocol similar to VNC but for individual windows.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.1)))
        }
    }
}

struct BulletPoint: View {
    let text: String
    let done: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundColor(done ? .green : .secondary)
            Text(text)
                .font(.subheadline)
                .foregroundColor(done ? .primary : .secondary)
        }
    }
}

struct AppCard: View {
    let app: StreamableApp
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app.fill")
                        .font(.title)
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text("\(app.windows.count) window\(app.windows.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct WindowCard: View {
    let window: StreamableWindow
    
    var body: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 160, height: 100)
                .cornerRadius(6)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: window.isOnScreen ? "macwindow" : "macwindow.badge.plus")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text(window.isOnScreen ? "On Screen" : "Hidden")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                )
            
            Text(window.title.isEmpty ? "Untitled" : window.title)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 160)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct AppStreamingTabView_Previews: PreviewProvider {
    static var previews: some View {
        AppStreamingTabView()
    }
}

