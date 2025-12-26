import SwiftUI

struct ClipboardSyncView: View {
    @StateObject private var service = ClipboardSyncService.shared
    @State private var selectedItem: ClipboardItem?
    @State private var showingCopiedAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()
            
            if !service.isEnabled {
                disabledView
            } else {
                enabledContent
            }
        }
        .frame(minWidth: 450, minHeight: 500)
        .alert("Copied!", isPresented: $showingCopiedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Item copied to your clipboard")
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(.purple)
                    Text("Clipboard Sync")
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
                
                Text("Share clipboard between Macs running TidalDrift")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $service.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding()
    }
    
    private var disabledView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("Clipboard Sync")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enable clipboard sync to share copied text, images, and files between Macs on your network.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Button("Enable Clipboard Sync") {
                service.isEnabled = true
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
    }
    
    private var enabledContent: some View {
        HSplitView {
            // Left side: Connected peers and quick actions
            VStack(spacing: 0) {
                peersSection
                
                Divider()
                
                quickActions
            }
            .frame(minWidth: 180, maxWidth: 220)
            
            // Right side: Clipboard history
            clipboardHistoryView
        }
    }
    
    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Connected Macs")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Circle()
                    .fill(service.isEnabled ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            if service.connectedPeers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No peers found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Run TidalDrift on other Macs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        // This Mac
                        PeerRow(
                            name: NetworkUtils.computerName,
                            isLocal: true,
                            itemCount: service.clipboardHistory.filter { service.isLocalItem($0) }.count
                        )
                        
                        // Other Macs
                        ForEach(service.connectedPeers, id: \.self) { peer in
                            PeerRow(
                                name: peer,
                                isLocal: false,
                                itemCount: service.items(from: peer).count
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            
            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var quickActions: some View {
        VStack(spacing: 8) {
            if let lastSync = service.lastSyncTime {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Last sync: \(lastSync, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                service.clearHistory()
            } label: {
                Label("Clear History", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(service.clipboardHistory.isEmpty)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var clipboardHistoryView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clipboard History")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(service.clipboardHistory.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            if service.clipboardHistory.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clipboard")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No clipboard items yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Copy something to see it here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(service.clipboardHistory) { item in
                            ClipboardItemRow(
                                item: item,
                                isLocal: service.isLocalItem(item),
                                isSelected: selectedItem?.id == item.id
                            )
                            .onTapGesture {
                                selectedItem = item
                            }
                            .onTapGesture(count: 2) {
                                service.copyToClipboard(item)
                                showingCopiedAlert = true
                            }
                            .contextMenu {
                                Button {
                                    service.copyToClipboard(item)
                                    showingCopiedAlert = true
                                } label: {
                                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PeerRow: View {
    let name: String
    let isLocal: Bool
    let itemCount: Int
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isLocal ? "laptopcomputer" : "desktopcomputer")
                .foregroundColor(isLocal ? .blue : .green)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.caption)
                        .lineLimit(1)
                    
                    if isLocal {
                        Text("(you)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("\(itemCount) items")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isLocal ? Color.blue.opacity(0.1) : Color.clear)
        )
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isLocal: Bool
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Content type icon
            contentTypeIcon
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconBackgroundColor.opacity(0.2))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                // Preview
                if item.contentType == .image, let imageData = item.imageData,
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 60)
                        .cornerRadius(4)
                } else {
                    Text(item.preview)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                }
                
                // Source info
                HStack(spacing: 4) {
                    if isLocal {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    
                    Text(item.sourceDevice)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(item.relativeTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Quick copy button
            Button {
                ClipboardSyncService.shared.copyToClipboard(item)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Copy to clipboard")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }
    
    private var contentTypeIcon: some View {
        Group {
            switch item.contentType {
            case .text:
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
            case .image:
                Image(systemName: "photo")
                    .foregroundColor(.purple)
            case .file:
                Image(systemName: "doc")
                    .foregroundColor(.orange)
            case .rtf:
                Image(systemName: "doc.richtext")
                    .foregroundColor(.cyan)
            }
        }
        .font(.subheadline)
    }
    
    private var iconBackgroundColor: Color {
        switch item.contentType {
        case .text: return .blue
        case .image: return .purple
        case .file: return .orange
        case .rtf: return .cyan
        }
    }
}

struct ClipboardSyncView_Previews: PreviewProvider {
    static var previews: some View {
        ClipboardSyncView()
    }
}

