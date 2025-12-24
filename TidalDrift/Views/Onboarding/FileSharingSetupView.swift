import SwiftUI

struct FileSharingSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var isChecking = false
    @State private var isToggling = false
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            
            toggleSection
            
            if !viewModel.fileSharingEnabled {
                manualInstructions
            }
        }
        .onAppear {
            checkStatus()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("File Sharing")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            
            Text("Share files and folders with other Macs on your network")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var toggleSection: some View {
        VStack(spacing: 16) {
            // Main toggle card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("File Sharing")
                        .font(.headline)
                    Text(viewModel.fileSharingEnabled ? "Your shared folders are accessible" : "Enable to share files with other Macs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isToggling || isChecking {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Toggle("", isOn: Binding(
                        get: { viewModel.fileSharingEnabled },
                        set: { _ in toggleFileSharing() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.fileSharingEnabled ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
            
            // Status indicator
            if viewModel.fileSharingEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("File Sharing is enabled")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
            
            Text("Requires administrator password")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var manualInstructions: some View {
        VStack(spacing: 12) {
            Text("Or enable manually:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Open System Settings") {
                SharingConfigurationService.shared.openSharingPreferences()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button("Check Again") {
                checkStatus()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.accentColor)
        }
    }
    
    private func toggleFileSharing() {
        isToggling = true
        let newState = !viewModel.fileSharingEnabled
        
        Task {
            let success = await SharingConfigurationService.shared.toggleFileSharing(enable: newState)
            
            // Wait a moment for the service to start/stop
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            await MainActor.run {
                isToggling = false
                if success {
                    viewModel.fileSharingEnabled = newState
                    viewModel.updateCanProceed()
                }
            }
            
            // Verify the actual state
            checkStatus()
        }
    }
    
    private func checkStatus() {
        isChecking = true
        Task {
            let enabled = await SharingConfigurationService.shared.isFileSharingEnabled()
            await MainActor.run {
                viewModel.fileSharingEnabled = enabled
                viewModel.updateCanProceed()
                isChecking = false
            }
        }
    }
}

struct FileSharingSetupView_Previews: PreviewProvider {
    static var previews: some View {
        FileSharingSetupView(viewModel: OnboardingViewModel())
            .frame(width: 600, height: 500)
    }
}
