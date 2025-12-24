import SwiftUI

struct FirewallSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(spacing: 32) {
            headerSection
            
            infoSection
            
            actionSection
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.red, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Firewall Configuration")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            
            Text("Ensure your firewall allows incoming connections")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("If you have the macOS firewall enabled, you may need to allow incoming connections for Screen Sharing and File Sharing.")
                .font(.body)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("To configure your firewall:")
                    .font(.headline)
                
                InstructionStep(number: 1, text: "Open System Settings → Network → Firewall")
                InstructionStep(number: 2, text: "Click \"Options\" or \"Firewall Options\"")
                InstructionStep(number: 3, text: "Ensure \"Block all incoming connections\" is OFF")
                InstructionStep(number: 4, text: "Add Screen Sharing and File Sharing to allowed apps if needed")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }
    
    private var actionSection: some View {
        VStack(spacing: 16) {
            Button("Open Firewall Settings") {
                SharingConfigurationService.shared.openFirewallSettings()
            }
            .buttonStyle(.borderedProminent)
            
            Text("You can skip this step if your firewall is disabled or already configured correctly.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    FirewallSetupView(viewModel: OnboardingViewModel())
        .frame(width: 600, height: 500)
}
