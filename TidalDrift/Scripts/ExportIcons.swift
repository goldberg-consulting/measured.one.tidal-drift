#!/usr/bin/env swift

// Run with: swift ExportIcons.swift
// This generates all icon sizes for the macOS app bundle

import SwiftUI
import AppKit

// MARK: - Icon Rendering

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

func renderAppIcon(size: CGFloat) -> NSImage {
    let view = NSHostingView(rootView: 
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
            
            // Waves
            VStack(spacing: size * 0.06) {
                ForEach(0..<3, id: \.self) { i in
                    StaticWaveShape(offset: CGFloat(i) * 0.7, amplitude: size * 0.035)
                        .stroke(
                            Color.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round)
                        )
                        .frame(width: size * 0.55, height: size * 0.08)
                }
            }
            
            // Neural nodes
            ForEach(0..<5, id: \.self) { i in
                let angle = Double(i) * (360.0 / 5.0) - 90
                let radius = size * 0.28
                let x = cos(angle * .pi / 180) * radius
                let y = sin(angle * .pi / 180) * radius * 0.5
                
                Circle()
                    .fill(Color.cyan)
                    .frame(width: size * 0.04, height: size * 0.04)
                    .offset(x: x, y: y)
            }
            
            // Central node
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
    )
    
    view.frame = NSRect(x: 0, y: 0, width: size, height: size)
    
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(rep)
    return image
}

func saveIcon(image: NSImage, filename: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(filename)")
        return
    }
    
    let url = URL(fileURLWithPath: filename)
    do {
        try pngData.write(to: url)
        print("✓ Saved \(filename)")
    } catch {
        print("✗ Failed to save \(filename): \(error)")
    }
}

// MARK: - Main

let iconSizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let outputDir = "../Resources/AppIcon.iconset/"

print("🌊 Generating TidalDrift App Icons...")
print("   with Neural Bridge design\n")

for (filename, size) in iconSizes {
    let image = renderAppIcon(size: size)
    saveIcon(image: image, filename: outputDir + filename)
}

print("\n✨ Done! Now run: iconutil -c icns \(outputDir) -o ../Resources/AppIcon.icns")

