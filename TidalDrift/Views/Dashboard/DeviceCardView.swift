import SwiftUI

struct DeviceCardView: View {
    let device: DiscoveredDevice
    let onTap: () -> Void
    
    @State private var isHovering = false
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.2), .accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                
                Image(systemName: device.deviceIcon)
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 4) {
                Text(device.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            HStack(spacing: 6) {
                ForEach(Array(device.services), id: \.self) { service in
                    ServiceBadge(service: service)
                }
            }
            
            HStack(spacing: 6) {
                StatusIndicator(isOnline: device.isOnline, size: 8)
                
                Text(device.isOnline ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundColor(device.isOnline ? .green : .secondary)
            }
            
            Button("Connect") {
                onTap()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
        .frame(minWidth: 160, maxWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(
                    color: isHovering ? .accentColor.opacity(0.2) : .black.opacity(0.1),
                    radius: isHovering ? 12 : 6,
                    x: 0,
                    y: isHovering ? 6 : 3
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            withAnimation {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    isPressed = false
                }
                onTap()
            }
        }
    }
}

struct ServiceBadge: View {
    let service: DiscoveredDevice.ServiceType
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: service.icon)
                .font(.system(size: 9))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.15))
        )
        .foregroundColor(.secondary)
    }
}

#Preview {
    HStack {
        DeviceCardView(device: .preview) {}
        DeviceCardView(device: DiscoveredDevice.previewList[2]) {}
    }
    .padding()
}
