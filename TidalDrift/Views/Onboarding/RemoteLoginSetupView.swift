import SwiftUI

struct RemoteLoginSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var isChecking = false
    @State private var isToggling = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                
                toggleSection
                
                if !viewModel.remoteLoginEnabled {
                    manualInstructions
                } else {
                    successIndicator
                }
                
                Spacer()
            }
            .padding(32)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Remote Login (SSH)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            
            Text("Allow terminal access from other computers on your network")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var toggleSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remote Login")
                        .font(.headline)
                    Text(viewModel.remoteLoginEnabled ? "SSH access is currently enabled" : "Enable to allow secure terminal access")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isToggling || isChecking {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Toggle("", isOn: Binding(
                        get: { viewModel.remoteLoginEnabled },
                        set: { _ in toggleRemoteLogin() }
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
                            .stroke(viewModel.remoteLoginEnabled ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
            
            Text("Requires administrator password")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var successIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Remote Login is active")
                .font(.subheadline)
                .foregroundColor(.green)
        }
        .padding(.top, 8)
    }
    
    private var manualInstructions: some View {
        VStack(spacing: 12) {
            Text("Or enable manually:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Open Sharing Settings") {
                SharingConfigurationService.shared.openSharingPreferences()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button("Check Status Again") {
                checkStatus()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.accentColor)
        }
    }
    
    private func toggleRemoteLogin() {
        isToggling = true
        let newState = !viewModel.remoteLoginEnabled
        
        Task {
            let success = await SharingConfigurationService.shared.toggleRemoteLogin(enable: newState)
            
            // Wait a moment for the system to process the command
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                isToggling = false
                if success {
                    viewModel.remoteLoginEnabled = newState
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
            let enabled = await SharingConfigurationService.shared.isRemoteLoginEnabled()
            await MainActor.run {
                viewModel.remoteLoginEnabled = enabled
                viewModel.updateCanProceed()
                isChecking = false
            }
        }
    }
}

struct RemoteLoginSetupView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteLoginSetupView(viewModel: OnboardingViewModel())
            .frame(width: 600, height: 500)
    }
}

