import SwiftUI

struct DeviceCardView: View {
    let device: DiscoveredDevice
    let onTap: () -> Void
    
    @State private var isHovering = false
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 10) {
            // Device icon with TidalDrift badge
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: device.isTidalDriftPeer 
                                    ? [Color.tidalDriftPeer.opacity(0.3), Color.tidalDriftPeer.opacity(0.15)]
                                    : [.accentColor.opacity(0.2), .accentColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: device.deviceIcon)
                        .font(.system(size: 26))
                        .foregroundColor(device.isTidalDriftPeer ? .tidalDriftPeer : .accentColor)
                }
                
                // TidalDrift peer badge
                if device.isTidalDriftPeer {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.tidalDriftPeer)
                        .background(Circle().fill(Color(nsColor: .controlBackgroundColor)).padding(-2))
                        .offset(x: 4, y: 4)
                }
            }
            
            VStack(spacing: 3) {
                Text(device.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Show model info for TidalDrift peers
                if device.isTidalDriftPeer, let model = device.peerModelName, !model.isEmpty {
                    Text(model)
                        .font(.caption2)
                        .foregroundColor(.tidalDriftPeer)
                        .lineLimit(1)
                }
            }
            
            // Service badges
            HStack(spacing: 4) {
                ForEach(Array(device.services), id: \.self) { service in
                    ServiceBadge(service: service)
                }
                
                if device.isTidalDriftPeer {
                    TidalDriftBadge()
                }
            }
            
            // Extra info for TidalDrift peers (on hover)
            if device.isTidalDriftPeer && isHovering {
                VStack(spacing: 2) {
                    if let processor = device.peerProcessorInfo, !processor.isEmpty {
                        Text(processor)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if let memory = device.peerMemoryGB, memory > 0,
                       let macOS = device.peerMacOSVersion, !macOS.isEmpty {
                        Text("\(memory)GB RAM • macOS \(macOS)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let user = device.peerUserName, !user.isEmpty {
                        Text("User: \(user)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            HStack(spacing: 6) {
                StatusIndicator(isOnline: device.isOnline, size: 8)
                
                if device.isOnline {
                    Text("Online")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if device.isStale {
                    Text("Seen \(device.lastSeenText)")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Seen \(device.lastSeenText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Connect") {
                onTap()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .frame(minWidth: 170, maxWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(device.isTidalDriftPeer 
                    ? Color.tidalDriftPeer.opacity(0.05)
                    : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(device.isTidalDriftPeer ? Color.tidalDriftPeerGlow : Color.clear, lineWidth: 2)
                )
                .shadow(
                    color: isHovering 
                        ? (device.isTidalDriftPeer ? Color.tidalDriftPeer.opacity(0.4) : .accentColor.opacity(0.2)) 
                        : (device.isTidalDriftPeer ? Color.tidalDriftPeer.opacity(0.2) : .black.opacity(0.1)),
                    radius: isHovering ? 12 : (device.isTidalDriftPeer ? 8 : 6),
                    x: 0,
                    y: isHovering ? 6 : 3
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
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

struct TidalDriftBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 8))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.tidalDriftPeerLight)
        )
        .foregroundColor(.tidalDriftPeer)
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

struct DeviceCardView_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            DeviceCardView(device: .preview) {}
            DeviceCardView(device: DiscoveredDevice.previewList[2]) {}
        }
        .padding()
    }
}
