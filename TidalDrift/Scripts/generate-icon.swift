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
    
    // Ocean gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.0, green: 0.3, blue: 0.65, alpha: 1.0),
        CGColor(red: 0.0, green: 0.5, blue: 0.85, alpha: 1.0)
    ]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
    
    context.saveGState()
    context.addEllipse(in: circleRect)
    context.clip()
    context.drawLinearGradient(gradient, 
                                start: CGPoint(x: padding, y: iconSize - padding),
                                end: CGPoint(x: iconSize - padding, y: padding),
                                options: [])
    context.restoreGState()
    
    // Draw simple ≈ wave symbol
    let centerX = iconSize / 2
    let centerY = iconSize / 2
    let fontSize = drawSize * 0.55
    
    // Create attributed string with ≈
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let string = "≈" as NSString
    let stringSize = string.size(withAttributes: attributes)
    
    // Draw centered
    let x = centerX - stringSize.width / 2
    let y = centerY - stringSize.height / 2
    
    context.saveGState()
    context.addEllipse(in: circleRect)
    context.clip()
    
    // Flip for text drawing
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    
    let textRect = CGRect(x: x, y: y + stringSize.height, width: stringSize.width, height: stringSize.height)
    string.draw(in: textRect, withAttributes: attributes)
    
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

