import SwiftUI

struct StatusCardView: View {
    @EnvironmentObject var appState: AppState
    @State private var isTogglingScreen: Bool = false
    @State private var isTogglingFile: Bool = false
    @State private var isTogglingSSH: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "desktopcomputer")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.computerName)
                        .font(.headline)
                    Text("This Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            VStack(spacing: 8) {
                SharingToggleRow(
                    label: "Screen Sharing",
                    isEnabled: appState.screenSharingEnabled,
                    isToggling: isTogglingScreen
                ) {
                    toggleScreenSharing()
                }
                
                SharingToggleRow(
                    label: "File Sharing",
                    isEnabled: appState.fileSharingEnabled,
                    isToggling: isTogglingFile
                ) {
                    toggleFileSharing()
                }
                
                HStack {
                    Text("Peer Discovery")
                        .font(.caption)
                    Spacer()
                    Toggle("", isOn: $appState.settings.peerDiscoveryEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.7)
                        .frame(width: 40)
                }
                
                SharingToggleRow(
                    label: "Remote Login (SSH)",
                    isEnabled: appState.remoteLoginEnabled,
                    isToggling: isTogglingSSH
                ) {
                    toggleRemoteLogin()
                }
            }
            
            Divider()
            
            HStack {
                Text("IP Address")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(appState.localIPAddress)
                    .font(.system(.caption, design: .monospaced))
                
                Button {
                    copyIPAddress()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            
            // TidalDrift peer count
            let peerCount = appState.discoveredDevices.filter { $0.isTidalDriftPeer }.count
            if peerCount > 0 {
                HStack {
                    Image(systemName: "wave.3.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text("\(peerCount) TidalDrift peer\(peerCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            
            Divider()
            
            HStack {
                Text("Version")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("1.2.0")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .onAppear {
            appState.refreshLocalInfo()
        }
    }
    
    private func copyIPAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.localIPAddress, forType: .string)
    }
    
    private func toggleScreenSharing() {
        isTogglingScreen = true
        let newState = !appState.screenSharingEnabled
        
        Task {
            let success = await SharingConfigurationService.shared.toggleScreenSharing(enable: newState)
            await MainActor.run {
                isTogglingScreen = false
                if success {
                    appState.screenSharingEnabled = newState
                }
                // Refresh to get actual state
                Task {
                    await appState.checkSharingStatus()
                }
            }
        }
    }
    
    private func toggleFileSharing() {
        isTogglingFile = true
        let newState = !appState.fileSharingEnabled
        
        Task {
            let success = await SharingConfigurationService.shared.toggleFileSharing(enable: newState)
            await MainActor.run {
                isTogglingFile = false
                if success {
                    appState.fileSharingEnabled = newState
                }
                // Refresh to get actual state
                Task {
                    await appState.checkSharingStatus()
                }
            }
        }
    }
    
    private func toggleRemoteLogin() {
        isTogglingSSH = true
        let newState = !appState.remoteLoginEnabled
        
        Task {
            let success = await SharingConfigurationService.shared.toggleRemoteLogin(enable: newState)
            await MainActor.run {
                isTogglingSSH = false
                if success {
                    appState.remoteLoginEnabled = newState
                }
                // Refresh to get actual state
                Task {
                    await appState.checkSharingStatus()
                }
            }
        }
    }
}

struct SharingToggleRow: View {
    let label: String
    let isEnabled: Bool
    let isToggling: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            
            Spacer()
            
            if isToggling {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 40)
            } else {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.7)
                .frame(width: 40)
            }
        }
    }
}

struct StatusRow: View {
    let label: String
    let isEnabled: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(isEnabled ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                
                Text(isEnabled ? "On" : "Off")
                    .font(.caption)
                    .foregroundColor(isEnabled ? .green : .orange)
            }
        }
    }
}

struct QRCodeSheet: View {
    let ipAddress: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Connect to This Mac")
                .font(.headline)
            
            if let qrImage = generateQRCode(from: "vnc://\(ipAddress)") {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
            }
            
            Text("vnc://\(ipAddress)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(width: 300, height: 350)
    }
    
    private func generateQRCode(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let ciImage = filter.outputImage else {
            return nil
        }
        
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: transform)
        
        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        
        return nsImage
    }
}

struct StatusCardView_Previews: PreviewProvider {
    static var previews: some View {
        StatusCardView()
            .environmentObject(AppState.shared)
            .frame(width: 250)
            .padding()
    }
}
