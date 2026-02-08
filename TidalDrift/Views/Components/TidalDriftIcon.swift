import SwiftUI

// MARK: - App Icon (Single Wave - Simple & Clean)
struct TidalDriftAppIcon: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Ocean gradient background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.0, green: 0.6, blue: 1.0),
                            Color(red: 0.0, green: 0.4, blue: 0.8),
                            Color(red: 0.0, green: 0.25, blue: 0.6)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)
            
            // Single elegant wave
            SingleWaveElement(size: size)
        }
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.25), radius: size * 0.06, x: 0, y: size * 0.03)
    }
}

// MARK: - Single Wave Element
struct SingleWaveElement: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Main wave with gradient stroke
            AppIconWaveShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.95)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: size * 0.08,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: size * 0.6, height: size * 0.15)
            
            // Subtle glow effect
            AppIconWaveShape()
                .stroke(
                    Color.white.opacity(0.4),
                    style: StrokeStyle(
                        lineWidth: size * 0.12,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: size * 0.6, height: size * 0.15)
                .blur(radius: size * 0.02)
        }
    }
}

// MARK: - App Icon Wave Shape (renamed to avoid conflict)
struct AppIconWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        let midY = rect.midY
        
        // Start at left
        path.move(to: CGPoint(x: 0, y: midY))
        
        // Single smooth wave curve
        path.addCurve(
            to: CGPoint(x: width, y: midY),
            control1: CGPoint(x: width * 0.25, y: midY - height * 0.8),
            control2: CGPoint(x: width * 0.75, y: midY + height * 0.8)
        )
        
        return path
    }
}

// MARK: - Menu Bar Icon (Simple TD text - works reliably)
struct TidalDriftMenuBarIcon: View {
    let size: CGFloat
    
    var body: some View {
        Text("TD")
            .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
    }
}

// MARK: - Preview
struct TidalDriftIcon_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TidalDriftAppIcon(size: 512)
            TidalDriftAppIcon(size: 128)
            TidalDriftAppIcon(size: 64)
            TidalDriftAppIcon(size: 32)
        }
        .padding()
        .background(Color.gray.opacity(0.2))
    }
}
