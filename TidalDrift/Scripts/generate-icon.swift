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
    let padding = iconSize * 0.08
    let drawSize = iconSize - (padding * 2)
    
    // Background circle with gradient
    let circleRect = CGRect(x: padding, y: padding, width: drawSize, height: drawSize)
    
    // Ocean gradient - deeper blue
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.0, green: 0.25, blue: 0.6, alpha: 1.0),
        CGColor(red: 0.0, green: 0.45, blue: 0.8, alpha: 1.0),
        CGColor(red: 0.05, green: 0.55, blue: 0.9, alpha: 1.0)
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
    
    // Draw SPICY wave with dramatic curl! 🌊🌶️
    let wavePath = CGMutablePath()
    let centerX = iconSize / 2
    let centerY = iconSize / 2
    let waveSize = drawSize * 0.75
    
    // Wave area bounds
    let waveLeft = centerX - waveSize / 2
    let waveTop = centerY - waveSize / 2
    let waveWidth = waveSize
    let waveHeight = waveSize
    
    // Start from bottom left - the base of the wave
    let startX = waveLeft + waveWidth * 0.05
    let startY = waveTop + waveHeight * 0.85
    
    wavePath.move(to: CGPoint(x: startX, y: startY))
    
    // Rising wave face - sweeps up dramatically
    wavePath.addCurve(
        to: CGPoint(x: waveLeft + waveWidth * 0.5, y: waveTop + waveHeight * 0.15),
        control1: CGPoint(x: waveLeft + waveWidth * 0.15, y: waveTop + waveHeight * 0.7),
        control2: CGPoint(x: waveLeft + waveWidth * 0.35, y: waveTop + waveHeight * 0.1)
    )
    
    // The crest - peaks and starts to curl over
    wavePath.addCurve(
        to: CGPoint(x: waveLeft + waveWidth * 0.75, y: waveTop + waveHeight * 0.25),
        control1: CGPoint(x: waveLeft + waveWidth * 0.6, y: waveTop + waveHeight * 0.05),
        control2: CGPoint(x: waveLeft + waveWidth * 0.7, y: waveTop + waveHeight * 0.08)
    )
    
    // THE CURL - dramatic spiral inward! 🌀
    wavePath.addCurve(
        to: CGPoint(x: waveLeft + waveWidth * 0.88, y: waveTop + waveHeight * 0.5),
        control1: CGPoint(x: waveLeft + waveWidth * 0.82, y: waveTop + waveHeight * 0.28),
        control2: CGPoint(x: waveLeft + waveWidth * 0.9, y: waveTop + waveHeight * 0.38)
    )
    
    // Spiral tightens
    wavePath.addCurve(
        to: CGPoint(x: waveLeft + waveWidth * 0.72, y: waveTop + waveHeight * 0.55),
        control1: CGPoint(x: waveLeft + waveWidth * 0.88, y: waveTop + waveHeight * 0.58),
        control2: CGPoint(x: waveLeft + waveWidth * 0.8, y: waveTop + waveHeight * 0.6)
    )
    
    // Inner spiral - tight curl center
    wavePath.addCurve(
        to: CGPoint(x: waveLeft + waveWidth * 0.68, y: waveTop + waveHeight * 0.42),
        control1: CGPoint(x: waveLeft + waveWidth * 0.68, y: waveTop + waveHeight * 0.52),
        control2: CGPoint(x: waveLeft + waveWidth * 0.65, y: waveTop + waveHeight * 0.48)
    )
    
    // Draw wave with white stroke and glow
    context.saveGState()
    context.addEllipse(in: circleRect)
    context.clip()
    
    // Strong glow effect
    context.setShadow(offset: .zero, blur: drawSize * 0.08, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.6))
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
    context.setLineWidth(drawSize * 0.08)  // Thicker line
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

