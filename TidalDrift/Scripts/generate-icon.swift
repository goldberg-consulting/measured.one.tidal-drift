#!/usr/bin/env swift
// Generates TidalDrift app icon with wave + swirl design

import Cocoa
import Foundation

// Icon sizes needed for macOS app icon
let sizes: [(size: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16"),
    (16, 2, "icon_16x16@2x"),
    (32, 1, "icon_32x32"),
    (32, 2, "icon_32x32@2x"),
    (128, 1, "icon_128x128"),
    (128, 2, "icon_128x128@2x"),
    (256, 1, "icon_256x256"),
    (256, 2, "icon_256x256@2x"),
    (512, 1, "icon_512x512"),
    (512, 2, "icon_512x512@2x")
]

func drawWaveIcon(in context: CGContext, size: CGFloat) {
    let iconSize = size
    let padding = iconSize * 0.1
    let drawSize = iconSize - (padding * 2)
    
    // Background circle with gradient
    let circleRect = CGRect(x: padding, y: padding, width: drawSize, height: drawSize)
    
    // Ocean gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.0, green: 0.3, blue: 0.7, alpha: 1.0),
        CGColor(red: 0.0, green: 0.5, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.1, green: 0.6, blue: 0.95, alpha: 1.0)
    ]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 0.5, 1])!
    
    context.saveGState()
    context.addEllipse(in: circleRect)
    context.clip()
    context.drawLinearGradient(gradient, 
                                start: CGPoint(x: padding, y: iconSize - padding),
                                end: CGPoint(x: iconSize - padding, y: padding),
                                options: [])
    context.restoreGState()
    
    // Draw wave with swirl
    let wavePath = CGMutablePath()
    let centerX = iconSize / 2
    let centerY = iconSize / 2
    let waveWidth = drawSize * 0.65
    let waveHeight = drawSize * 0.25
    
    // Start point
    let startX = centerX - waveWidth / 2
    let startY = centerY + waveHeight * 0.1
    
    wavePath.move(to: CGPoint(x: startX, y: startY))
    
    // Wave body - S curve
    let waveEndX = centerX + waveWidth * 0.15
    wavePath.addCurve(
        to: CGPoint(x: waveEndX, y: centerY),
        control1: CGPoint(x: centerX - waveWidth * 0.25, y: centerY - waveHeight * 0.8),
        control2: CGPoint(x: centerX - waveWidth * 0.05, y: centerY + waveHeight * 0.8)
    )
    
    // Swirl - curves up and back
    let swirlTopX = centerX + waveWidth * 0.35
    let swirlTopY = centerY - waveHeight * 0.6
    wavePath.addCurve(
        to: CGPoint(x: swirlTopX, y: swirlTopY),
        control1: CGPoint(x: waveEndX + waveWidth * 0.1, y: centerY - waveHeight * 0.2),
        control2: CGPoint(x: swirlTopX, y: centerY - waveHeight * 0.1)
    )
    
    // Curl inward
    let swirlEndX = centerX + waveWidth * 0.22
    let swirlEndY = centerY - waveHeight * 0.25
    wavePath.addCurve(
        to: CGPoint(x: swirlEndX, y: swirlEndY),
        control1: CGPoint(x: swirlTopX + waveWidth * 0.05, y: swirlTopY + waveHeight * 0.1),
        control2: CGPoint(x: swirlEndX + waveWidth * 0.08, y: swirlEndY - waveHeight * 0.15)
    )
    
    // Draw wave with white stroke and glow
    context.saveGState()
    context.addEllipse(in: circleRect)
    context.clip()
    
    // Glow effect
    context.setShadow(offset: .zero, blur: drawSize * 0.05, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    context.setLineWidth(drawSize * 0.06)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(wavePath)
    context.strokePath()
    
    context.restoreGState()
}

func generateIcon(size: Int, scale: Int) -> NSImage {
    let pixelSize = size * scale
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    
    image.lockFocus()
    if let context = NSGraphicsContext.current?.cgContext {
        // Flip coordinate system
        context.translateBy(x: 0, y: CGFloat(pixelSize))
        context.scaleBy(x: 1, y: -1)
        
        drawWaveIcon(in: context, size: CGFloat(pixelSize))
    }
    image.unlockFocus()
    
    return image
}

func main() {
    let outputDir = "Resources/AppIcon.iconset"
    let fileManager = FileManager.default
    
    // Create iconset directory
    try? fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    
    // Generate each size
    for (size, scale, name) in sizes {
        let image = generateIcon(size: size, scale: scale)
        let filename = "\(outputDir)/\(name).png"
        
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: URL(fileURLWithPath: filename))
            print("Generated: \(filename)")
        }
    }
    
    print("\nNow run: iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns")
}

main()

