import SwiftUI

struct WelcomeStepView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 32) {
            appIcon
            
            VStack(spacing: 16) {
                Text("Welcome to TidalDrift")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                
                Text("Your gateway to seamless Mac-to-Mac connectivity")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            featuresList
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }
        }
    }
    
    private var appIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .cyan, .teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: .blue.opacity(0.4), radius: 20, x: 0, y: 10)
            
            Image(systemName: "water.waves")
                .font(.system(size: 50, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.degrees(isAnimating ? 0 : -10))
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
        }
        .scaleEffect(isAnimating ? 1 : 0.8)
        .opacity(isAnimating ? 1 : 0)
    }
    
    private var featuresList: some View {
        VStack(alignment: .leading, spacing: 16) {
            FeatureRow(
                icon: "rectangle.on.rectangle",
                title: "Screen Sharing",
                description: "View and control other Macs on your network"
            )
            
            FeatureRow(
                icon: "folder",
                title: "File Sharing",
                description: "Share files seamlessly between your devices"
            )
            
            FeatureRow(
                icon: "wifi",
                title: "Auto Discovery",
                description: "Automatically find Macs on your local network"
            )
            
            FeatureRow(
                icon: "lock.shield",
                title: "Secure & Private",
                description: "All connections stay on your local network"
            )
        }
        .padding(.top, 24)
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 20)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    WelcomeStepView()
        .frame(width: 600, height: 500)
}
