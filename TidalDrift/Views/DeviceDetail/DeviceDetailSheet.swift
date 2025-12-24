import SwiftUI

struct DeviceDetailSheet: View {
    let device: DiscoveredDevice
    @StateObject private var viewModel: DeviceDetailViewModel
    @Environment(\.dismiss) var dismiss
    
    init(device: DiscoveredDevice) {
        self.device = device
        _viewModel = StateObject(wrappedValue: DeviceDetailViewModel(device: device))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    connectionSection
                    
                    servicesSection
                    
                    credentialsSection
                    
                    if !viewModel.connectionHistory.isEmpty {
                        historySection
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            footer
        }
        .frame(width: 450, height: 550)
        .alert("Connection Error", isPresented: .constant(viewModel.connectionError != nil)) {
            Button("OK") {
                viewModel.connectionError = nil
            }
        } message: {
            Text(viewModel.connectionError ?? "")
        }
    }
    
    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                
                Image(systemName: device.deviceIcon)
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(device.ipAddress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    StatusIndicator(isOnline: device.isOnline, size: 8)
                    Text(device.statusText)
                        .font(.caption)
                        .foregroundColor(device.isOnline ? .green : .secondary)
                }
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }
    
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Connect")
                .font(.headline)
            
            HStack(spacing: 12) {
                if device.services.contains(.screenSharing) {
                    ConnectButton(
                        title: "Screen Share",
                        icon: "rectangle.on.rectangle",
                        isLoading: viewModel.isConnecting
                    ) {
                        Task {
                            await viewModel.connect(to: .screenSharing)
                        }
                    }
                }
                
                if device.services.contains(.fileSharing) {
                    ConnectButton(
                        title: "File Share",
                        icon: "folder",
                        isLoading: viewModel.isConnecting
                    ) {
                        Task {
                            await viewModel.connect(to: .fileSharing)
                        }
                    }
                }
            }
            
            HStack {
                Toggle("Trust this device", isOn: Binding(
                    get: { viewModel.isTrusted },
                    set: { _ in viewModel.toggleTrust() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                
                Spacer()
                
                Button {
                    Task {
                        await viewModel.testConnection()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else if let result = viewModel.connectionTestResult {
                            Image(systemName: result ? "checkmark.circle" : "xmark.circle")
                                .foregroundColor(result ? .green : .red)
                        }
                        Text("Test")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Services")
                .font(.headline)
            
            if device.services.isEmpty {
                Text("No services discovered")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(device.services), id: \.self) { service in
                    HStack {
                        Image(systemName: service.icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        
                        Text(service.displayName)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved Credentials")
                    .font(.headline)
                
                Spacer()
                
                if viewModel.hasCredentials {
                    Button("Delete") {
                        viewModel.deleteCredentials()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .font(.caption)
                }
            }
            
            TextField("Username", text: $viewModel.username)
                .textFieldStyle(.roundedBorder)
            
            SecureField("Password", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)
            
            Toggle("Save credentials in Keychain", isOn: $viewModel.saveCredentials)
                .toggleStyle(.checkbox)
                .controlSize(.small)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection History")
                .font(.headline)
            
            ForEach(viewModel.connectionHistory.prefix(5)) { record in
                HStack {
                    Image(systemName: record.connectionType.icon)
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Text(record.relativeTimestamp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: record.wasSuccessful ? "checkmark.circle" : "xmark.circle")
                        .foregroundColor(record.wasSuccessful ? .green : .red)
                        .font(.caption)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var footer: some View {
        HStack {
            Text("Last seen: \(device.lastSeen.formatted())")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}

struct ConnectButton: View {
    let title: String
    let icon: String
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
    }
}

#Preview {
    DeviceDetailSheet(device: .preview)
}
