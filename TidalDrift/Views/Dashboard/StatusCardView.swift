import SwiftUI

struct StatusCardView: View {
    @EnvironmentObject var appState: AppState
    @State private var showQRCode: Bool = false
    
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
                StatusRow(
                    label: "Screen Sharing",
                    isEnabled: appState.screenSharingEnabled
                )
                
                StatusRow(
                    label: "File Sharing",
                    isEnabled: appState.fileSharingEnabled
                )
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
            
            HStack(spacing: 8) {
                Button("Configure") {
                    SharingConfigurationService.shared.openSharingPreferences()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("QR Code") {
                    showQRCode = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .sheet(isPresented: $showQRCode) {
            QRCodeSheet(ipAddress: appState.localIPAddress)
        }
        .onAppear {
            appState.refreshLocalInfo()
        }
    }
    
    private func copyIPAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.localIPAddress, forType: .string)
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

#Preview {
    StatusCardView()
        .environmentObject(AppState.shared)
        .frame(width: 250)
        .padding()
}
