import SwiftUI

struct ScreenSharingSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var isChecking = false
    @State private var isToggling = false
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            
            toggleSection
            
            if !viewModel.screenSharingEnabled {
                manualInstructions
            }
        }
        .onAppear {
            checkStatus()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Screen Sharing")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            
            Text("Allow other Macs to view and control your screen")
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
                    Text("Screen Sharing")
                        .font(.headline)
                    Text(viewModel.screenSharingEnabled ? "Other Macs can connect to your screen" : "Enable to allow remote connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isToggling || isChecking {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Toggle("", isOn: Binding(
                        get: { viewModel.screenSharingEnabled },
                        set: { _ in toggleScreenSharing() }
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
                            .stroke(viewModel.screenSharingEnabled ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
            
            // Status indicator
            if viewModel.screenSharingEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Screen Sharing is enabled")
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
    
    private func toggleScreenSharing() {
        isToggling = true
        let newState = !viewModel.screenSharingEnabled
        
        Task {
            let success = await SharingConfigurationService.shared.toggleScreenSharing(enable: newState)
            
            // Wait a moment for the service to start/stop
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            await MainActor.run {
                isToggling = false
                if success {
                    viewModel.screenSharingEnabled = newState
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
            let enabled = await SharingConfigurationService.shared.isScreenSharingEnabled()
            await MainActor.run {
                viewModel.screenSharingEnabled = enabled
                viewModel.updateCanProceed()
                isChecking = false
            }
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            
            Text(text)
                .font(.body)
        }
    }
}

struct ScreenSharingSetupView_Previews: PreviewProvider {
    static var previews: some View {
        ScreenSharingSetupView(viewModel: OnboardingViewModel())
            .frame(width: 600, height: 500)
    }
}
