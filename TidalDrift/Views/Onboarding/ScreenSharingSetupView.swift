import SwiftUI

struct ScreenSharingSetupView: View {
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
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Enable Screen Sharing")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            
            Text("Allow other Macs to view and control your screen")
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
            } else if viewModel.screenSharingEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("Screen Sharing is enabled")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Screen Sharing is not enabled")
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
            if !viewModel.screenSharingEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to enable:")
                        .font(.headline)
                    
                    InstructionStep(number: 1, text: "Click the button below to open System Settings")
                    InstructionStep(number: 2, text: "Navigate to General → Sharing")
                    InstructionStep(number: 3, text: "Toggle on \"Screen Sharing\"")
                    InstructionStep(number: 4, text: "Come back here and click \"Check Again\"")
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

#Preview {
    ScreenSharingSetupView(viewModel: OnboardingViewModel())
        .frame(width: 600, height: 500)
}
