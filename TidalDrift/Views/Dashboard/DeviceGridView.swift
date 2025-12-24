import SwiftUI

struct DeviceGridView: View {
    let devices: [DiscoveredDevice]
    let onSelect: (DiscoveredDevice) -> Void
    
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(devices) { device in
                DeviceCardView(device: device) {
                    onSelect(device)
                }
            }
        }
    }
}

struct DeviceListView: View {
    let devices: [DiscoveredDevice]
    let onSelect: (DiscoveredDevice) -> Void
    
    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(devices) { device in
                DeviceListRowView(device: device) {
                    onSelect(device)
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
            Image(systemName: device.deviceIcon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                ForEach(Array(device.services), id: \.self) { service in
                    Image(systemName: service.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Last seen indicator
            if !device.isOnline {
                Text(device.lastSeenText)
                    .font(.caption2)
                    .foregroundColor(device.isStale ? .orange : .secondary)
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
                .fill(isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
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
