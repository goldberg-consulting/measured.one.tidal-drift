import Foundation
import CoreGraphics
import ApplicationServices
import OSLog

class InputInjector {
    private let logger = Logger(subsystem: "com.tidaldrift", category: "InputInjector")
    private var inputCount = 0
    private var lastPermissionCheck: Date?
    private var hasLoggedPermissionWarning = false
    
    /// The capture bounds for input mapping (defaults to full screen)
    /// When capturing a window/app, this should be set to the window's frame
    var captureBounds: CGRect?
    
    enum RemoteInput {
        case mouseMove(x: Double, y: Double)
        case mouseDown(button: Int, x: Double, y: Double)
        case mouseUp(button: Int, x: Double, y: Double)
        case keyDown(keyCode: UInt16, modifiers: UInt64)
        case keyUp(keyCode: UInt16, modifiers: UInt64)
        case scroll(deltaX: Double, deltaY: Double)
    }
    
    /// Check if we have Accessibility permission (required for input injection)
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
    
    /// Request accessibility permission (opens System Settings)
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    /// Convert normalized coordinates (0...1) to screen coordinates
    private func normalizedToScreenCoordinates(x: Double, y: Double) -> CGPoint {
        if let bounds = captureBounds {
            // When capturing a window, map to the window's bounds
            let screenX = bounds.origin.x + (x * bounds.width)
            let screenY = bounds.origin.y + (y * bounds.height)
            return CGPoint(x: screenX, y: screenY)
        } else {
            // Full display mode - map to the main display
            let displayID = CGMainDisplayID()
            let logicalWidth = CGFloat(CGDisplayPixelsWide(displayID))
            let logicalHeight = CGFloat(CGDisplayPixelsHigh(displayID))
            return CGPoint(x: x * logicalWidth, y: y * logicalHeight)
        }
    }
    
    func inject(_ input: RemoteInput) {
        inputCount += 1
        
        // Check and log permission status periodically
        if inputCount == 1 || inputCount % 100 == 0 {
            let hasPermission = hasAccessibilityPermission
            if !hasPermission && !hasLoggedPermissionWarning {
                print("🚨 InputInjector: Accessibility permission DENIED - input will not work!")
                print("🚨 InputInjector: Go to System Settings > Privacy & Security > Accessibility and enable TidalDrift")
                logger.error("🚨 InputInjector: Accessibility permission DENIED - input will not work!")
                hasLoggedPermissionWarning = true
            } else if hasPermission && inputCount == 1 {
                print("✅ InputInjector: Accessibility permission granted")
                logger.info("✅ InputInjector: Accessibility permission granted")
            }
        }
        
        // Log first few inputs and then periodically to verify receipt
        if inputCount <= 5 || inputCount % 100 == 0 {
            print("🎮 InputInjector: Injecting input #\(self.inputCount): \(String(describing: input))")
            if let bounds = captureBounds {
                print("🎮 InputInjector: Using capture bounds: \(bounds)")
            }
        }
        
        switch input {
        case .mouseMove(let x, let y):
            let point = normalizedToScreenCoordinates(x: x, y: y)
            guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
                if inputCount <= 5 { logger.error("❌ Failed to create mouseMove event") }
                return
            }
            event.post(tap: .cghidEventTap)
            
        case .mouseDown(let button, let x, let y):
            let point = normalizedToScreenCoordinates(x: x, y: y)
            let type: CGEventType = button == 0 ? .leftMouseDown : (button == 1 ? .rightMouseDown : .otherMouseDown)
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: CGMouseButton(rawValue: UInt32(button))!) else {
                logger.error("❌ Failed to create mouseDown event at (\(x), \(y))")
                return
            }
            logger.info("🖱️ InputInjector: mouseDown at screen position (\(Int(point.x)), \(Int(point.y)))")
            event.post(tap: .cghidEventTap)
            
        case .mouseUp(let button, let x, let y):
            let point = normalizedToScreenCoordinates(x: x, y: y)
            let type: CGEventType = button == 0 ? .leftMouseUp : (button == 1 ? .rightMouseUp : .otherMouseUp)
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: CGMouseButton(rawValue: UInt32(button))!) else {
                logger.error("❌ Failed to create mouseUp event at (\(x), \(y))")
                return
            }
            logger.info("🖱️ InputInjector: mouseUp at screen position (\(Int(point.x)), \(Int(point.y)))")
            event.post(tap: .cghidEventTap)
            
        case .keyDown(let keyCode, let modifiers):
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
                logger.error("❌ Failed to create keyDown event for keyCode \(keyCode)")
                return
            }
            event.flags = CGEventFlags(rawValue: modifiers)
            logger.info("⌨️ InputInjector: keyDown keyCode=\(keyCode), modifiers=\(modifiers)")
            event.post(tap: .cghidEventTap)
            
        case .keyUp(let keyCode, let modifiers):
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
                logger.error("❌ Failed to create keyUp event for keyCode \(keyCode)")
                return
            }
            event.flags = CGEventFlags(rawValue: modifiers)
            logger.info("⌨️ InputInjector: keyUp keyCode=\(keyCode)")
            event.post(tap: .cghidEventTap)
            
        case .scroll(let deltaX, let deltaY):
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(deltaY), wheel2: Int32(deltaX), wheel3: 0) else {
                logger.error("❌ Failed to create scroll event")
                return
            }
            if inputCount <= 5 || inputCount % 100 == 0 {
                logger.info("🔄 InputInjector: scroll deltaX=\(deltaX), deltaY=\(deltaY)")
            }
            event.post(tap: .cghidEventTap)
        }
    }
}

extension InputInjector.RemoteInput {
    func serialize() -> Data {
        var data = Data()
        switch self {
        case .mouseMove(let x, let y):
            data.append(1)
            var xb = x.bitPattern.bigEndian
            var yb = y.bitPattern.bigEndian
            withUnsafeBytes(of: &xb) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &yb) { data.append(contentsOf: $0) }
        case .mouseDown(let button, let x, let y):
            data.append(2)
            data.append(UInt8(button))
            var xb = x.bitPattern.bigEndian
            var yb = y.bitPattern.bigEndian
            withUnsafeBytes(of: &xb) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &yb) { data.append(contentsOf: $0) }
        case .mouseUp(let button, let x, let y):
            data.append(3)
            data.append(UInt8(button))
            var xb = x.bitPattern.bigEndian
            var yb = y.bitPattern.bigEndian
            withUnsafeBytes(of: &xb) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &yb) { data.append(contentsOf: $0) }
        case .keyDown(let keyCode, let modifiers):
            data.append(4)
            var k = keyCode.bigEndian
            var m = modifiers.bigEndian
            withUnsafeBytes(of: &k) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &m) { data.append(contentsOf: $0) }
        case .keyUp(let keyCode, let modifiers):
            data.append(5)
            var k = keyCode.bigEndian
            var m = modifiers.bigEndian
            withUnsafeBytes(of: &k) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &m) { data.append(contentsOf: $0) }
        case .scroll(let deltaX, let deltaY):
            data.append(6)
            var dx = deltaX.bitPattern.bigEndian
            var dy = deltaY.bitPattern.bigEndian
            withUnsafeBytes(of: &dx) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &dy) { data.append(contentsOf: $0) }
        }
        return data
    }
    
    static func deserialize(_ data: Data) -> InputInjector.RemoteInput? {
        guard !data.isEmpty else { return nil }
        let type = data[0]
        switch type {
        case 1: // mouseMove
            guard data.count >= 17 else { return nil }
            let x = Double(bitPattern: data.subdata(in: 1..<9).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            let y = Double(bitPattern: data.subdata(in: 9..<17).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            return .mouseMove(x: x, y: y)
        case 2: // mouseDown
            guard data.count >= 18 else { return nil }
            let button = Int(data[1])
            let x = Double(bitPattern: data.subdata(in: 2..<10).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            let y = Double(bitPattern: data.subdata(in: 10..<18).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            return .mouseDown(button: button, x: x, y: y)
        case 3: // mouseUp
            guard data.count >= 18 else { return nil }
            let button = Int(data[1])
            let x = Double(bitPattern: data.subdata(in: 2..<10).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            let y = Double(bitPattern: data.subdata(in: 10..<18).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            return .mouseUp(button: button, x: x, y: y)
        case 4: // keyDown
            guard data.count >= 11 else { return nil }
            let keyCode = data.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let modifiers = data.subdata(in: 3..<11).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            return .keyDown(keyCode: keyCode, modifiers: modifiers)
        case 5: // keyUp
            guard data.count >= 11 else { return nil }
            let keyCode = data.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let modifiers = data.subdata(in: 3..<11).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            return .keyUp(keyCode: keyCode, modifiers: modifiers)
        case 6: // scroll
            guard data.count >= 17 else { return nil }
            let dx = Double(bitPattern: data.subdata(in: 1..<9).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            let dy = Double(bitPattern: data.subdata(in: 9..<17).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            return .scroll(deltaX: dx, deltaY: dy)
        default:
            return nil
        }
    }
}
