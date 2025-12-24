import SwiftUI

struct AddDeviceSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var deviceName: String = ""
    @State private var ipAddress: String = ""
    @State private var port: String = "5900"
    @State private var isValidating = false
    @State private var validationError: String?
    
    var body: some View {
        VStack(spacing: 24) {
            header
            
            form
            
            if let error = validationError {
                errorView(error)
            }
            
            buttons
        }
        .padding(24)
        .frame(width: 400)
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            
            Text("Add Device Manually")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter the IP address of a Mac you want to connect to")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var form: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Device Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("e.g., Office iMac", text: $deviceName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("IP Address")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("e.g., 192.168.1.100", text: $ipAddress)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Port (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("5900", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
        }
    }
    
    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            Text(error)
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }
    
    private var buttons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("Test Connection") {
                testConnection()
            }
            .buttonStyle(.bordered)
            .disabled(ipAddress.isEmpty || isValidating)
            
            Button("Add Device") {
                addDevice()
            }
            .buttonStyle(.borderedProminent)
            .disabled(deviceName.isEmpty || ipAddress.isEmpty || isValidating)
        }
    }
    
    private func testConnection() {
        guard NetworkUtils.isValidIPAddress(ipAddress) else {
            validationError = "Invalid IP address format"
            return
        }
        
        isValidating = true
        validationError = nil
        
        Task {
            let portNum = Int(port) ?? 5900
            let success = await ScreenShareConnectionService.shared.testConnection(to: ipAddress, port: portNum)
            
            await MainActor.run {
                isValidating = false
                if success {
                    validationError = nil
                } else {
                    validationError = "Could not connect to device"
                }
            }
        }
    }
    
    private func addDevice() {
        guard NetworkUtils.isValidIPAddress(ipAddress) else {
            validationError = "Invalid IP address format"
            return
        }
        
        viewModel.addManualDevice(name: deviceName, ipAddress: ipAddress)
    }
}

#Preview {
    AddDeviceSheet(viewModel: DashboardViewModel())
}
