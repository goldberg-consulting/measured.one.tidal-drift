import SwiftUI

// Soft red/coral color for TidalDrift peers
extension Color {
    static let tidalDriftPeer = Color(red: 0.9, green: 0.3, blue: 0.35)
    static let tidalDriftPeerLight = Color(red: 0.95, green: 0.4, blue: 0.4).opacity(0.15)
    static let tidalDriftPeerGlow = Color(red: 0.95, green: 0.35, blue: 0.4).opacity(0.3)
}

struct DeviceGridView: View {
    let devices: [DiscoveredDevice]
    let onSelect: (DiscoveredDevice) -> Void
    
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    private var tidalDriftPeers: [DiscoveredDevice] {
        devices.filter { $0.isTidalDriftPeer }
    }
    
    private var otherDevices: [DiscoveredDevice] {
        devices.filter { !$0.isTidalDriftPeer }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // TidalDrift peers section
            if !tidalDriftPeers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "wave.3.right")
                            .foregroundColor(.tidalDriftPeer)
                        Text("TidalDrift Peers")
                            .font(.headline)
                            .foregroundColor(.tidalDriftPeer)
                        Text("(\(tidalDriftPeers.count))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(tidalDriftPeers) { device in
                            DeviceCardView(device: device) {
                                onSelect(device)
                            }
                        }
                    }
                }
                
                if !otherDevices.isEmpty {
                    Divider()
                        .padding(.vertical, 8)
                }
            }
            
            // Other devices section
            if !otherDevices.isEmpty {
                if !tidalDriftPeers.isEmpty {
                    Text("Other Devices")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(otherDevices) { device in
                        DeviceCardView(device: device) {
                            onSelect(device)
                        }
                    }
                }
            }
        }
    }
}

struct DeviceListView: View {
    let devices: [DiscoveredDevice]
    let onSelect: (DiscoveredDevice) -> Void
    
    private var tidalDriftPeers: [DiscoveredDevice] {
        devices.filter { $0.isTidalDriftPeer }
    }
    
    private var otherDevices: [DiscoveredDevice] {
        devices.filter { !$0.isTidalDriftPeer }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // TidalDrift peers section
            if !tidalDriftPeers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "wave.3.right")
                            .foregroundColor(.tidalDriftPeer)
                        Text("TidalDrift Peers")
                            .font(.headline)
                            .foregroundColor(.tidalDriftPeer)
                    }
                    
                    ForEach(tidalDriftPeers) { device in
                        DeviceListRowView(device: device) {
                            onSelect(device)
                        }
                    }
                }
                
                if !otherDevices.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                }
            }
            
            // Other devices
            if !otherDevices.isEmpty {
                if !tidalDriftPeers.isEmpty {
                    Text("Other Devices")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                ForEach(otherDevices) { device in
                    DeviceListRowView(device: device) {
                        onSelect(device)
                    }
                }
            }
        }
    }
}

struct DeviceListRowView: View {
    let device: DiscoveredDevice
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Device icon with TidalDrift indicator
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: device.deviceIcon)
                    .font(.title2)
                    .foregroundColor(device.isTidalDriftPeer ? .tidalDriftPeer : .accentColor)
                    .frame(width: 40)
                
                if device.isTidalDriftPeer {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.tidalDriftPeer)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(-1))
                        .offset(x: 4, y: 4)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.headline)
                    
                    if device.isTidalDriftPeer {
                        Text("TidalDrift")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.tidalDriftPeerLight))
                            .foregroundColor(.tidalDriftPeer)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(device.ipAddress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if device.isTidalDriftPeer, let model = device.peerModelName, !model.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(model)
                            .font(.caption)
                            .foregroundColor(.tidalDriftPeer)
                    }
                    
                    if device.isTidalDriftPeer, let user = device.peerUserName, !user.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(user)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Show more info for TidalDrift peers
            if device.isTidalDriftPeer {
                VStack(alignment: .trailing, spacing: 2) {
                    if let memory = device.peerMemoryGB, memory > 0 {
                        Text("\(memory)GB RAM")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let macOS = device.peerMacOSVersion, !macOS.isEmpty {
                        Text("macOS \(macOS)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack(spacing: 8) {
                ForEach(Array(device.services), id: \.self) { service in
                    Image(systemName: service.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            StatusIndicator(isOnline: device.isOnline)
            
            Button("Connect") {
                onTap()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering 
                    ? (device.isTidalDriftPeer ? Color.tidalDriftPeer.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                    : (device.isTidalDriftPeer ? Color.tidalDriftPeer.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(device.isTidalDriftPeer ? Color.tidalDriftPeerGlow : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: device.isTidalDriftPeer ? Color.tidalDriftPeer.opacity(0.2) : .clear, radius: 4, x: 0, y: 0)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}

struct DeviceGridView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            DeviceGridView(devices: DiscoveredDevice.previewList, onSelect: { _ in })
            
            Divider()
            
            DeviceListView(devices: DiscoveredDevice.previewList, onSelect: { _ in })
        }
        .padding()
    }
}
