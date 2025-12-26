import SwiftUI

struct WelcomeStepView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            TidalDriftLogoFull()
            
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
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                isAnimating = true
            }
        }
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
    
    private var permissionsNote: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.horizontal, 40)
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Next, we'll guide you through enabling Screen Sharing, File Sharing, SSH, and firewall settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
        }
        .opacity(isAnimating ? 1 : 0)
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
