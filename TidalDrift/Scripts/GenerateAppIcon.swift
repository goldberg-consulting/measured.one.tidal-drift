#!/usr/bin/env swift

// TidalDrift App Icon Generator - Neural Bridge Design
import AppKit
import Foundation

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let center = CGPoint(x: size / 2, y: size / 2)
    
    // Ocean gradient background
    let circlePath = CGPath(ellipseIn: rect.insetBy(dx: size * 0.02, dy: size * 0.02), transform: nil)
    context.addPath(circlePath)
    context.clip()
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors: [CGColor] = [
        CGColor(red: 0.0, green: 0.55, blue: 0.95, alpha: 1.0),
        CGColor(red: 0.0, green: 0.35, blue: 0.75, alpha: 1.0),
        CGColor(red: 0.0, green: 0.2, blue: 0.55, alpha: 1.0)
    ]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 0.5, 1.0]) {
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size * 0.5, options: [.drawsAfterEndLocation])
    }
    context.resetClip()
    
    // Outer glow ring
    context.setStrokeColor(CGColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.5))
    context.setLineWidth(size * 0.02)
    context.addPath(CGPath(ellipseIn: rect.insetBy(dx: size * 0.04, dy: size * 0.04), transform: nil))
    context.strokePath()
    
    // Three waves
    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
    context.setLineWidth(size * 0.045)
    context.setLineCap(.round)
    
    for waveIndex in 0..<3 {
        let yOffset = CGFloat(waveIndex - 1) * (size * 0.12)
        let wavePhase = CGFloat(waveIndex) * 0.7
        let waveWidth = size * 0.55
        let startX = center.x - waveWidth / 2
        let startY = center.y + yOffset
        
        let wavePath = CGMutablePath()
        wavePath.move(to: CGPoint(x: startX, y: startY))
        
        for x in stride(from: 0, through: waveWidth, by: 1) {
            let y = startY + sin((x / (waveWidth / 2.5)) * .pi * 2 + wavePhase) * (size * 0.035)
            wavePath.addLine(to: CGPoint(x: startX + x, y: y))
        }
        context.addPath(wavePath)
        context.strokePath()
        
        // Foam dots
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.6))
        for i in 0..<3 {
            let foamX = startX + CGFloat(i) * (waveWidth / 3) + (waveWidth / 6)
            let foamY = startY - (size * 0.035) + sin(CGFloat(i) * 2.1 + wavePhase) * (size * 0.015)
            context.fillEllipse(in: CGRect(x: foamX - size * 0.01, y: foamY - size * 0.01, width: size * 0.02, height: size * 0.02))
        }
    }
    
    // Neural nodes (5 in ellipse)
    var nodePositions: [CGPoint] = []
    for i in 0..<5 {
        let angle = Double(i) * (360.0 / 5.0) - 90
        let x = center.x + cos(angle * .pi / 180) * (size * 0.28)
        let y = center.y + sin(angle * .pi / 180) * (size * 0.28) * 0.5
        nodePositions.append(CGPoint(x: x, y: y))
        
        // Glow
        context.setFillColor(CGColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.3))
        context.fillEllipse(in: CGRect(x: x - size * 0.04, y: y - size * 0.04, width: size * 0.08, height: size * 0.08))
        // Node
        context.setFillColor(CGColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: x - size * 0.02, y: y - size * 0.02, width: size * 0.04, height: size * 0.04))
    }
    
    // Connection lines
    context.setStrokeColor(CGColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.4))
    context.setLineWidth(size * 0.008)
    for i in 0..<5 {
        context.move(to: nodePositions[i])
        context.addLine(to: nodePositions[(i + 1) % 5])
        context.strokePath()
    }
    
    // Central hub
    let hubCenter = CGPoint(x: center.x, y: center.y - size * 0.02)
    context.setFillColor(CGColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.5))
    context.fillEllipse(in: CGRect(x: hubCenter.x - size * 0.08, y: hubCenter.y - size * 0.08, width: size * 0.16, height: size * 0.16))
    context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
    context.fillEllipse(in: CGRect(x: hubCenter.x - size * 0.04, y: hubCenter.y - size * 0.04, width: size * 0.08, height: size * 0.08))
    
    image.unlockFocus()
    return image
}

func saveIcon(_ image: NSImage, _ path: String) {
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
    print("✓ \(path.components(separatedBy: "/").last ?? path)")
}

// Main
let base = "/Users/elisgoldberg/Documents/TidalDrift-rep/TidalDrift/Resources/AppIcon.iconset"
print("🌊 Generating Neural Bridge icons...\n")

[(16,"icon_16x16.png"),(32,"icon_16x16@2x.png"),(32,"icon_32x32.png"),(64,"icon_32x32@2x.png"),
 (128,"icon_128x128.png"),(256,"icon_128x128@2x.png"),(256,"icon_256x256.png"),(512,"icon_256x256@2x.png"),
 (512,"icon_512x512.png"),(1024,"icon_512x512@2x.png")].forEach { saveIcon(renderIcon(size: CGFloat($0.0)), "\(base)/\($0.1)") }

print("\n✨ Done! Now run: iconutil -c icns \(base) -o \(base.replacingOccurrences(of: ".iconset", with: ".icns"))")
