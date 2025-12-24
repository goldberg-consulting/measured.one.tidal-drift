import SwiftUI

struct FileSharingSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var isChecking = false
    
    var body: some View {
        VStack(spacing: 32) {
            headerSection
            
            statusSection
            
            instructionsSection
        }
        .onAppear {
            checkStatus()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Enable File Sharing")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            
            Text("Share files and folders with other Macs on your network")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var statusSection: some View {
        HStack(spacing: 12) {
            if isChecking {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Checking status...")
                    .foregroundColor(.secondary)
            } else if viewModel.fileSharingEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("File Sharing is enabled")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("File Sharing is not enabled")
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var instructionsSection: some View {
        VStack(spacing: 20) {
            if !viewModel.fileSharingEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to enable:")
                        .font(.headline)
                    
                    InstructionStep(number: 1, text: "Click the button below to open System Settings")
                    InstructionStep(number: 2, text: "Navigate to General → Sharing")
                    InstructionStep(number: 3, text: "Toggle on \"File Sharing\"")
                    InstructionStep(number: 4, text: "Optionally add folders you want to share")
                    InstructionStep(number: 5, text: "Come back here and click \"Check Again\"")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                
                HStack(spacing: 16) {
                    Button("Open System Settings") {
                        SharingConfigurationService.shared.openSharingPreferences()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Check Again") {
                        checkStatus()
                    }
                    .buttonStyle(.bordered)
                }
            }
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

#Preview {
    FileSharingSetupView(viewModel: OnboardingViewModel())
        .frame(width: 600, height: 500)
}
