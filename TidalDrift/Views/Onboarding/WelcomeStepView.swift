import SwiftUI

struct WelcomeStepView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            appIcon
            
            VStack(spacing: 10) {
                Text("TidalDrift")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("VPN & VNET Screen Sharing Made Simple")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Finally, a tool that makes internal network screen sharing not stink.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            featuresList
            
            // Branding footer
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "building.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Designed by")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("Goldberg Consulting, LLC")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding(.top, 8)
            .opacity(isAnimating ? 1 : 0)
        }
        .padding(.vertical, 16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }
        }
    }
    
    private var appIcon: some View {
        ZStack {
            // Main circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.0, green: 0.5, blue: 0.9),
                            Color(red: 0.0, green: 0.3, blue: 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .shadow(color: .blue.opacity(0.4), radius: 15, x: 0, y: 8)
            
            // Icon
            Image(systemName: "display.2")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.white)
        }
        .scaleEffect(isAnimating ? 1 : 0.8)
        .opacity(isAnimating ? 1 : 0)
    }
    
    private var featuresList: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureRow(
                icon: "network",
                title: "VPN & VNET Ready",
                description: "Designed for internal corporate networks"
            )
            
            FeatureRow(
                icon: "rectangle.on.rectangle",
                title: "One-Click Screen Sharing",
                description: "Connect to any Mac on your network instantly"
            )
            
            FeatureRow(
                icon: "bolt.fill",
                title: "Auto Discovery",
                description: "No manual IP addresses needed"
            )
            
            FeatureRow(
                icon: "lock.shield.fill",
                title: "Secure & Local",
                description: "All traffic stays on your network"
            )
        }
        .padding(.top, 12)
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 20)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct WelcomeStepView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeStepView()
            .frame(width: 600, height: 500)
    }
}
