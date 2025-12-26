import SwiftUI

struct CompletionStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 24) {
            successIcon
            
            VStack(spacing: 12) {
                Text("You're Ready!")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("TidalDrift is configured and ready to connect")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            statusSummary
            
            connectionInfo
            
            Spacer()
            
            // Branding footer
            VStack(spacing: 4) {
                Text("Thank you for using TidalDrift")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "building.2")
                        .font(.caption2)
                    Text("Goldberg Consulting, LLC")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
            }
            .opacity(isAnimating ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                isAnimating = true
            }
        }
    }
    
    private var successIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 90, height: 90)
                .shadow(color: .green.opacity(0.4), radius: 20, x: 0, y: 10)
            
            Image(systemName: "checkmark")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
        }
        .scaleEffect(isAnimating ? 1 : 0)
        .opacity(isAnimating ? 1 : 0)
    }
    
    private var statusSummary: some View {
        VStack(spacing: 12) {
            OnboardingStatusRow(
                title: "Screen Sharing",
                isEnabled: viewModel.screenSharingEnabled
            )
            
            OnboardingStatusRow(
                title: "File Sharing",
                isEnabled: viewModel.fileSharingEnabled
            )
            
            OnboardingStatusRow(
                title: "Remote Login (SSH)",
                isEnabled: viewModel.remoteLoginEnabled
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 20)
    }
    
    private var connectionInfo: some View {
        VStack(spacing: 8) {
            Text("Your Mac is accessible at:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text(NetworkUtils.getLocalIPAddress() ?? "Unknown")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                
                Button {
                    if let ip = NetworkUtils.getLocalIPAddress() {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ip, forType: .string)
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.1))
        )
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 20)
    }
}

struct OnboardingStatusRow: View {
    let title: String
    let isEnabled: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(isEnabled ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(isEnabled ? "Enabled" : "Not Configured")
                    .font(.caption)
                    .foregroundColor(isEnabled ? .green : .orange)
            }
        }
    }
}

struct CompletionStepView_Previews: PreviewProvider {
    static var previews: some View {
        CompletionStepView(viewModel: OnboardingViewModel())
            .frame(width: 600, height: 500)
    }
}
