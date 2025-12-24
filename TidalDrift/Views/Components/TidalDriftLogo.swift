import SwiftUI

struct TidalDriftLogo: View {
    @State private var waveOffset: CGFloat = 0
    @State private var isAnimating = false
    let size: LogoSize
    
    enum LogoSize {
        case small   // Menu bar, sidebar
        case medium  // Dashboard header
        case large   // Welcome/About screens
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 18
            case .medium: return 28
            case .large: return 42
            }
        }
        
        var waveHeight: CGFloat {
            switch self {
            case .small: return 2
            case .medium: return 3
            case .large: return 4
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 24
            case .medium: return 50
            case .large: return 80
            }
        }
    }
    
    var body: some View {
        VStack(spacing: size == .large ? 16 : 8) {
            // Animated wave icon
            waveIcon
            
            // Text with wave underline
            VStack(spacing: 4) {
                Text("TidalDrift")
                    .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.4, blue: 0.8),
                                Color(red: 0.0, green: 0.6, blue: 0.9),
                                Color(red: 0.2, green: 0.7, blue: 0.9)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                // Animated wave underline
                WaveShape(offset: waveOffset, amplitude: size.waveHeight)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.6),
                                Color.blue.opacity(0.8),
                                Color.cyan.opacity(0.6)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: size == .large ? 3 : 2
                    )
                    .frame(height: size.waveHeight * 4)
            }
        }
        .onAppear {
            isAnimating = true
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                waveOffset = .pi * 2
            }
        }
    }
    
    private var waveIcon: some View {
        ZStack {
            // Ocean background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.0, green: 0.3, blue: 0.6),
                            Color(red: 0.0, green: 0.5, blue: 0.8),
                            Color(red: 0.1, green: 0.6, blue: 0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size.iconSize, height: size.iconSize)
                .shadow(color: .blue.opacity(0.4), radius: size.iconSize / 5, x: 0, y: size.iconSize / 10)
            
            // Animated waves inside circle
            ZStack {
                // Wave 1 - computers floating
                ForEach(0..<5, id: \.self) { i in
                    computerIcon(index: i)
                }
                
                // Wave overlay
                WaveShape(offset: waveOffset, amplitude: size.iconSize / 20)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: size.iconSize * 0.7, height: size.iconSize / 4)
                    .offset(y: size.iconSize / 6)
            }
            .clipShape(Circle())
        }
        .scaleEffect(isAnimating ? 1 : 0.9)
        .opacity(isAnimating ? 1 : 0.5)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isAnimating)
    }
    
    private func computerIcon(index: Int) -> some View {
        let positions: [(x: CGFloat, y: CGFloat)] = [
            (-0.2, -0.15), (0.2, -0.1), (0, 0.05), (-0.25, 0.1), (0.25, 0.15)
        ]
        let pos = positions[index]
        let floatOffset = sin(waveOffset + CGFloat(index) * 0.8) * (size.iconSize / 30)
        
        return Image(systemName: "desktopcomputer")
            .font(.system(size: size.iconSize / 6))
            .foregroundColor(.white.opacity(0.9))
            .offset(
                x: pos.x * size.iconSize,
                y: pos.y * size.iconSize + floatOffset
            )
    }
}

// Custom wave shape
struct WaveShape: Shape {
    var offset: CGFloat
    var amplitude: CGFloat
    
    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let wavelength = rect.width / 3
        
        path.move(to: CGPoint(x: 0, y: midY))
        
        for x in stride(from: 0, through: rect.width, by: 1) {
            let relativeX = x / wavelength
            let y = midY + sin(relativeX * .pi * 2 + offset) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}

// Full logo with tagline for welcome screens
struct TidalDriftLogoFull: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 16) {
            TidalDriftLogo(size: .large)
            
            VStack(spacing: 8) {
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
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 10)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                isAnimating = true
            }
        }
    }
}

struct TidalDriftLogo_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            TidalDriftLogo(size: .small)
            TidalDriftLogo(size: .medium)
            TidalDriftLogo(size: .large)
            
            Divider()
            
            TidalDriftLogoFull()
        }
        .padding(40)
        .frame(width: 400, height: 700)
    }
}

