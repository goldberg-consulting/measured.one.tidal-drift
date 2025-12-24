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
            
            // SPICY wave with dramatic curl! 🌊
            SwirlWaveShape(animationOffset: waveOffset)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.95),
                            Color.cyan.opacity(0.9)
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(
                        lineWidth: size.iconSize / 12,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: size.iconSize * 0.75, height: size.iconSize * 0.7)
                .shadow(color: .white.opacity(0.5), radius: size.iconSize / 15, x: 0, y: 0)
        }
        .scaleEffect(isAnimating ? 1 : 0.9)
        .opacity(isAnimating ? 1 : 0.5)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isAnimating)
    }
}

// Custom wave shape for underline
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

// SPICY wave with dramatic curl - like a cresting surf wave! 🌊🌶️
struct SwirlWaveShape: Shape {
    var animationOffset: CGFloat
    
    var animatableData: CGFloat {
        get { animationOffset }
        set { animationOffset = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        // Animation pulse
        let pulse = sin(animationOffset) * 0.08
        
        // Start from bottom left - the base of the wave
        let startX: CGFloat = width * 0.05
        let startY = height * 0.85 + pulse * height
        
        path.move(to: CGPoint(x: startX, y: startY))
        
        // Rising wave face - sweeps up dramatically
        path.addCurve(
            to: CGPoint(x: width * 0.5, y: height * 0.15),
            control1: CGPoint(x: width * 0.15, y: height * 0.7),
            control2: CGPoint(x: width * 0.35, y: height * 0.1)
        )
        
        // The crest - peaks and starts to curl over
        path.addCurve(
            to: CGPoint(x: width * 0.75, y: height * 0.25 + pulse * height),
            control1: CGPoint(x: width * 0.6, y: height * 0.05 - pulse * height * 0.5),
            control2: CGPoint(x: width * 0.7, y: height * 0.08)
        )
        
        // THE CURL - dramatic spiral inward! 🌀
        // First part curves down and forward
        path.addCurve(
            to: CGPoint(x: width * 0.88, y: height * 0.5),
            control1: CGPoint(x: width * 0.82, y: height * 0.28),
            control2: CGPoint(x: width * 0.9, y: height * 0.38)
        )
        
        // Spiral tightens - curling back under itself
        path.addCurve(
            to: CGPoint(x: width * 0.72, y: height * 0.55 + pulse * height),
            control1: CGPoint(x: width * 0.88, y: height * 0.58),
            control2: CGPoint(x: width * 0.8, y: height * 0.6)
        )
        
        // Inner spiral - the tight curl center
        path.addCurve(
            to: CGPoint(x: width * 0.68, y: height * 0.42),
            control1: CGPoint(x: width * 0.68, y: height * 0.52),
            control2: CGPoint(x: width * 0.65, y: height * 0.48)
        )
        
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

