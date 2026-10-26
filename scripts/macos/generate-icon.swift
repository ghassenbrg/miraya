import AppKit

// Repository-native artwork. All sizes are rendered from the same vector geometry.
guard CommandLine.arguments.count == 2 else { fatalError("Pass iconset directory") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let s = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: s)
        transform.concat()
        let midnight = NSColor(calibratedRed: 11/255, green: 16/255, blue: 32/255, alpha: 1)
        let blue = NSColor(calibratedRed: 59/255, green: 130/255, blue: 246/255, alpha: 1)
        let cyan = NSColor(calibratedRed: 0, green: 229/255, blue: 1, alpha: 1)
        let white = NSColor(calibratedRed: 244/255, green: 248/255, blue: 1, alpha: 1)
        let outline = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 206, yRadius: 206)
        midnight.setFill(); outline.fill()
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSGradient(starting: blue.withAlphaComponent(0.32), ending: midnight)!
            .draw(fromCenter: NSPoint(x: 790, y: 240), radius: 0, toCenter: NSPoint(x: 790, y: 240), radius: 800, options: .drawsAfterEndingLocation)
        NSGraphicsContext.restoreGraphicsState()
        cyan.withAlphaComponent(0.15).setStroke(); outline.lineWidth = 3; outline.stroke()
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.move(to: CGPoint(x: 282, y: 305))
        context.addLine(to: CGPoint(x: 282, y: 703))
        context.addLine(to: CGPoint(x: 512, y: 491))
        context.addLine(to: CGPoint(x: 742, y: 703))
        context.addLine(to: CGPoint(x: 742, y: 305))
        context.setLineWidth(102); context.setLineJoin(.round); context.setLineCap(.round)
        context.replacePathWithStrokedPath(); context.clip()
        NSGradient(colors: [blue, cyan, white, white])!.draw(in: NSRect(x: 220, y: 250, width: 585, height: 530), angle: 90)
        context.restoreGState()
        cyan.setFill()
        NSBezierPath(ovalIn: NSRect(x: 777, y: 750, width: 42, height: 42)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
