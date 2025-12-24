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
            
            // Single wave with swirl
            SwirlWaveShape(animationOffset: waveOffset)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.9),
                            Color.cyan.opacity(0.8),
                            Color.white.opacity(0.7)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: size.iconSize / 20,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: size.iconSize * 0.65, height: size.iconSize * 0.35)
                .offset(y: size.iconSize * 0.05)
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

// Single wave with swirl at the end - the main logo icon
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
        let midY = rect.midY
        
        // Start on the left
        let startX: CGFloat = 0
        let startY = midY + sin(animationOffset) * (height * 0.15)
        
        path.move(to: CGPoint(x: startX, y: startY))
        
        // Wave body - gentle S-curve
        let waveEndX = width * 0.65
        let waveControlY1 = midY - height * 0.35 + sin(animationOffset + 0.5) * (height * 0.1)
        let waveControlY2 = midY + height * 0.35 + sin(animationOffset + 1.0) * (height * 0.1)
        
        path.addCurve(
            to: CGPoint(x: waveEndX, y: midY + sin(animationOffset + 1.5) * (height * 0.1)),
            control1: CGPoint(x: width * 0.25, y: waveControlY1),
            control2: CGPoint(x: width * 0.45, y: waveControlY2)
        )
        
        // The swirl/curl at the end - curls upward and inward
        let swirlStartX = waveEndX
        let swirlStartY = midY + sin(animationOffset + 1.5) * (height * 0.1)
        
        // Swirl curves up and back on itself
        let swirlMidX = width * 0.85
        let swirlTopY = midY - height * 0.4 + sin(animationOffset + 2.0) * (height * 0.08)
        let swirlEndX = width * 0.72
        let swirlEndY = midY - height * 0.15 + sin(animationOffset + 2.5) * (height * 0.05)
        
        // First part of swirl - curves up
        path.addCurve(
            to: CGPoint(x: swirlMidX, y: swirlTopY),
            control1: CGPoint(x: swirlStartX + width * 0.1, y: swirlStartY - height * 0.1),
            control2: CGPoint(x: swirlMidX, y: swirlStartY - height * 0.25)
        )
        
        // Second part of swirl - curls inward (the spiral end)
        path.addCurve(
            to: CGPoint(x: swirlEndX, y: swirlEndY),
            control1: CGPoint(x: width * 0.88, y: swirlTopY + height * 0.05),
            control2: CGPoint(x: width * 0.78, y: swirlEndY - height * 0.08)
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

