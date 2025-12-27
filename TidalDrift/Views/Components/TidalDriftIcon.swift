import SwiftUI

// MARK: - App Icon (Static, with Neural Bridge)
struct TidalDriftAppIcon: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Ocean gradient background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.0, green: 0.55, blue: 0.95),
                            Color(red: 0.0, green: 0.35, blue: 0.75),
                            Color(red: 0.0, green: 0.2, blue: 0.55)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size, height: size)
            
            // Outer glow
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.6),
                            Color.blue.opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: size * 0.02
                )
                .frame(width: size * 0.96, height: size * 0.96)
                .blur(radius: size * 0.01)
            
            // Wave container
            ZStack {
                // The three waves with foam
                WaveWithFoam(waveIndex: 0, size: size)
                    .offset(y: -size * 0.12)
                WaveWithFoam(waveIndex: 1, size: size)
                WaveWithFoam(waveIndex: 2, size: size)
                    .offset(y: size * 0.12)
                
                // Neural bridge - connecting nodes at wave peaks
                NeuralBridgeOverlay(size: size)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: size * 0.08, x: 0, y: size * 0.04)
    }
}

// MARK: - Wave with Foam Detail
struct WaveWithFoam: View {
    let waveIndex: Int
    let size: CGFloat
    
    private var waveOffset: CGFloat {
        CGFloat(waveIndex) * 0.7
    }
    
    var body: some View {
        ZStack {
            // Main wave stroke - thicker for visibility
            StaticWaveShape(offset: waveOffset, amplitude: size * 0.035)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.7),
                            Color.white.opacity(0.95)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: size * 0.045,
                        lineCap: .round
                    )
                )
                .frame(width: size * 0.55, height: size * 0.08)
            
            // Foam spray at peaks
            FoamSpray(waveOffset: waveOffset, size: size)
        }
    }
}

// MARK: - Foam Spray Particles
struct FoamSpray: View {
    let waveOffset: CGFloat
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Small foam dots at wave crests
            ForEach(0..<3, id: \.self) { i in
                let xOffset = CGFloat(i) * (size * 0.18) - (size * 0.18)
                let peakPhase = sin(CGFloat(i) * 2.1 + waveOffset)
                
                Circle()
                    .fill(Color.white.opacity(0.6 + peakPhase * 0.2))
                    .frame(width: size * 0.02, height: size * 0.02)
                    .offset(
                        x: xOffset,
                        y: -size * 0.04 + peakPhase * size * 0.015
                    )
                    .blur(radius: size * 0.003)
                
                // Smaller secondary foam
                Circle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: size * 0.012, height: size * 0.012)
                    .offset(
                        x: xOffset + size * 0.025,
                        y: -size * 0.055 + peakPhase * size * 0.01
                    )
            }
        }
    }
}

// MARK: - Neural Bridge Overlay
struct NeuralBridgeOverlay: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Neural nodes - small glowing dots at connection points
            ForEach(0..<5, id: \.self) { i in
                let angle = Double(i) * (360.0 / 5.0) - 90
                let radius = size * 0.28
                let x = cos(angle * .pi / 180) * radius
                let y = sin(angle * .pi / 180) * radius * 0.5 // Elliptical for depth
                
                // Neural node
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cyan,
                                Color.cyan.opacity(0.5),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.03
                        )
                    )
                    .frame(width: size * 0.06, height: size * 0.06)
                    .offset(x: x, y: y)
                
                // Connection line to adjacent node
                if i < 4 {
                    let nextAngle = Double(i + 1) * (360.0 / 5.0) - 90
                    let nextX = cos(nextAngle * .pi / 180) * radius
                    let nextY = sin(nextAngle * .pi / 180) * radius * 0.5
                    
                    Path { path in
                        path.move(to: CGPoint(x: x + size/2, y: y + size/2))
                        path.addLine(to: CGPoint(x: nextX + size/2, y: nextY + size/2))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.6),
                                Color.white.opacity(0.3),
                                Color.cyan.opacity(0.6)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: size * 0.008, lineCap: .round)
                    )
                    .offset(x: -size/2, y: -size/2)
                }
            }
            
            // Central neural hub - the "bridge" core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color.cyan.opacity(0.8),
                            Color.cyan.opacity(0.2),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.06
                    )
                )
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(y: -size * 0.02)
        }
        .opacity(0.85)
    }
}

// MARK: - Static Wave Shape (frozen at aesthetic position)
struct StaticWaveShape: Shape {
    var offset: CGFloat
    var amplitude: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let wavelength = rect.width / 2.5
        
        path.move(to: CGPoint(x: 0, y: midY))
        
        for x in stride(from: 0, through: rect.width, by: 1) {
            let relativeX = x / wavelength
            let y = midY + sin(relativeX * .pi * 2 + offset) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}

// MARK: - Menu Bar Icon (Monochrome, simplified)
struct TidalDriftMenuBarIcon: View {
    let size: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var body: some View {
        ZStack {
            // Simplified waves
            VStack(spacing: size * 0.08) {
                ForEach(0..<3, id: \.self) { i in
                    StaticWaveShape(offset: CGFloat(i) * 0.6, amplitude: size * 0.06)
                        .stroke(iconColor.opacity(0.9), style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                        .frame(width: size * 0.7, height: size * 0.12)
                }
            }
            
            // Neural bridge hint - just the central node
            Circle()
                .fill(iconColor)
                .frame(width: size * 0.15, height: size * 0.15)
                .offset(y: -size * 0.02)
            
            // Small connection dots
            ForEach([(-0.25, -0.15), (0.25, -0.15), (-0.18, 0.18), (0.18, 0.18)], id: \.0) { offset in
                Circle()
                    .fill(iconColor.opacity(0.6))
                    .frame(width: size * 0.06, height: size * 0.06)
                    .offset(x: size * offset.0, y: size * offset.1)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview
struct TidalDriftIcon_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            // App Icon previews
            Text("App Icon").font(.headline)
            HStack(spacing: 20) {
                TidalDriftAppIcon(size: 128)
                TidalDriftAppIcon(size: 64)
                TidalDriftAppIcon(size: 32)
                TidalDriftAppIcon(size: 16)
            }
            
            Divider()
            
            // Menu bar previews
            Text("Menu Bar Icon").font(.headline)
            HStack(spacing: 20) {
                TidalDriftMenuBarIcon(size: 22)
                    .padding(8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                
                TidalDriftMenuBarIcon(size: 22)
                    .padding(8)
                    .background(Color.black)
                    .cornerRadius(4)
                    .environment(\.colorScheme, .dark)
                
                TidalDriftMenuBarIcon(size: 18)
                    .padding(6)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            
            Divider()
            
            // Large preview
            Text("Large Preview").font(.headline)
            TidalDriftAppIcon(size: 256)
        }
        .padding(40)
        .frame(width: 500, height: 700)
    }
}

