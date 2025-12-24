import SwiftUI

struct CompletionStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 32) {
            successIcon
            
            VStack(spacing: 16) {
                Text("You're All Set!")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                
                Text("TidalDrift is ready to discover and connect to other Macs")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            statusSummary
            
            connectionInfo
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
                .frame(width: 100, height: 100)
                .shadow(color: .green.opacity(0.4), radius: 20, x: 0, y: 10)
            
            Image(systemName: "checkmark")
                .font(.system(size: 50, weight: .bold))
                .foregroundColor(.white)
        }
        .scaleEffect(isAnimating ? 1 : 0)
        .opacity(isAnimating ? 1 : 0)
    }
    
    private var statusSummary: some View {
        VStack(spacing: 12) {
            StatusRow(
                title: "Screen Sharing",
                isEnabled: viewModel.screenSharingEnabled
            )
            
            StatusRow(
                title: "File Sharing",
                isEnabled: viewModel.fileSharingEnabled
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

struct StatusRow: View {
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

#Preview {
    CompletionStepView(viewModel: OnboardingViewModel())
        .frame(width: 600, height: 500)
}
