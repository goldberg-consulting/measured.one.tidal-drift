#!/usr/bin/env swift

import SwiftUI
import AppKit

// MARK: - App Icon Wave Shape
struct AppIconWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let midY = rect.midY
        path.move(to: CGPoint(x: 0, y: midY))
        path.addCurve(
            to: CGPoint(x: width, y: midY),
            control1: CGPoint(x: width * 0.25, y: midY - height * 0.8),
            control2: CGPoint(x: width * 0.75, y: midY + height * 0.8)
        )
        return path
    }
}

// MARK: - Single Wave Element
struct SingleWaveElement: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            AppIconWaveShape()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0.85), Color.white.opacity(0.95)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 0.6, height: size * 0.15)
            
            AppIconWaveShape()
                .stroke(Color.white.opacity(0.4), 
                       style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.6, height: size * 0.15)
                .blur(radius: size * 0.02)
        }
    }
}

// MARK: - App Icon View
struct TidalDriftAppIcon: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [
                        Color(red: 0.0, green: 0.6, blue: 1.0),
                        Color(red: 0.0, green: 0.4, blue: 0.8),
                        Color(red: 0.0, green: 0.25, blue: 0.6)
                    ],
                    center: .center, startRadius: 0, endRadius: size * 0.55
                ))
                .frame(width: size, height: size)
            
            SingleWaveElement(size: size)
        }
        .clipShape(Circle())
    }
}

// MARK: - Icon Generation
@MainActor
func generateIcon() {
    let sizes: [(Int, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]
    
    let scriptPath = CommandLine.arguments[0]
    let scriptDir = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
    let outputDir = scriptDir.deletingLastPathComponent().appendingPathComponent("Resources/AppIcon.iconset")
    
    print("Generating icons to: \(outputDir.path)")
    
    for (size, filename) in sizes {
        let view = TidalDriftAppIcon(size: CGFloat(size))
        let renderer = ImageRenderer(content: view.frame(width: CGFloat(size), height: CGFloat(size)))
        renderer.scale = 1.0
        
        if let nsImage = renderer.nsImage {
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                let path = outputDir.appendingPathComponent(filename)
                do {
                    try pngData.write(to: path)
                    print("✓ Generated: \(filename) (\(size)x\(size))")
                } catch {
                    print("✗ Failed to write \(filename): \(error)")
                }
            }
        }
    }
    print("\nDone!")
}

// Run on MainActor
Task { @MainActor in
    generateIcon()
    exit(0)
}

// Keep the script running
RunLoop.main.run()
