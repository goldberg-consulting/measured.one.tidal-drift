import SwiftUI
import AppKit

/// Multi-device picker for drag-and-drop file transfers.
/// Shown when files are dropped on the Dock icon.
struct DropTargetPicker: View {
    let fileURLs: [URL]
    let onSend: ([DiscoveredDevice]) -> Void
    let onCancel: () -> Void
    
    @EnvironmentObject var appState: AppState
    @State private var selectedDeviceIDs: Set<UUID> = []
    @State private var isSending = false
    
    private var otherDevices: [DiscoveredDevice] {
        appState.discoveredDevices.filter { !$0.isCurrentDevice }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            deviceList
            Divider()
            footer
        }
        .frame(width: 320, height: 420)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.up.doc")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send \(fileURLs.count) \(fileURLs.count == 1 ? "file" : "files")")
                        .font(.headline)
                    Text("Select destination devices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(fileURLs, id: \.absoluteString) { url in
                        HStack(spacing: 4) {
                            Image(systemName: fileIcon(for: url))
                                .font(.system(size: 10))
                            Text(url.lastPathComponent)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }
                }
            }
        }
        .padding(16)
    }
    
    private var deviceList: some View {
        Group {
            if otherDevices.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "network.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No devices found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Run Discover Devices from the menu bar")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(otherDevices) { device in
                            DropPickerDeviceRow(
                                device: device,
                                isSelected: selectedDeviceIDs.contains(device.id),
                                onToggle: {
                                    if selectedDeviceIDs.contains(device.id) {
                                        selectedDeviceIDs.remove(device.id)
                                    } else {
                                        selectedDeviceIDs.insert(device.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    private var footer: some View {
        HStack {
            if !otherDevices.isEmpty {
                Button(selectedDeviceIDs.count == otherDevices.count ? "Deselect All" : "Select All") {
                    if selectedDeviceIDs.count == otherDevices.count {
                        selectedDeviceIDs.removeAll()
                    } else {
                        selectedDeviceIDs = Set(otherDevices.map(\.id))
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.accentColor)
            }
            
            Spacer()
            
            Button("Cancel") { onCancel() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
            
            Button("Send") {
                let selected = otherDevices.filter { selectedDeviceIDs.contains($0.id) }
                isSending = true
                onSend(selected)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedDeviceIDs.isEmpty || isSending)
            .keyboardShortcut(.return)
        }
        .padding(16)
    }
    
    private func fileIcon(for url: URL) -> String {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue ? "folder.fill" : "doc.fill"
    }
}

struct DropPickerDeviceRow: View {
    let device: DiscoveredDevice
    let isSelected: Bool
    let onToggle: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
                
                Image(systemName: device.deviceIcon)
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(device.ipAddress)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if device.isTidalDriftPeer {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 9))
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) :
                            isHovering ? Color.secondary.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Window Manager for Drop Picker

class DropPickerWindowManager {
    static let shared = DropPickerWindowManager()
    private var window: NSWindow?
    
    func show(fileURLs: [URL]) {
        close()
        
        let picker = DropTargetPicker(
            fileURLs: fileURLs,
            onSend: { [weak self] devices in
                self?.sendFiles(fileURLs, to: devices)
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )
        .environmentObject(AppState.shared)
        
        let hostingView = NSHostingView(rootView: picker)
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Send Files"
        win.contentView = hostingView
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = win
    }
    
    func close() {
        window?.close()
        window = nil
    }
    
    private func sendFiles(_ urls: [URL], to devices: [DiscoveredDevice]) {
        for url in urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
            
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            
            if isDirectory.boolValue {
                sendFolderContents(at: url, to: devices)
            } else {
                sendSingleFile(at: url, to: devices)
            }
        }
    }
    
    private func sendSingleFile(at url: URL, to devices: [DiscoveredDevice]) {
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.lastPathComponent
        for device in devices {
            TidalDropService.shared.smartSendFileData(fileName: name, fileData: data, to: device)
        }
    }
    
    private func sendFolderContents(at folderURL: URL, to devices: [DiscoveredDevice]) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return }
        
        for fileURL in contents {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            if !isDir.boolValue {
                sendSingleFile(at: fileURL, to: devices)
            }
        }
    }
}
