import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let canvas: CGFloat = 1024
let margin: CGFloat = 100
let cornerRadius: CGFloat = 185

func drawSpeaker(centerX cx: CGFloat, centerY cy: CGFloat, height h: CGFloat) {
    NSColor.white.setFill()
    NSColor.white.setStroke()

    let bodyW = h * 0.11
    let bodyH = h * 0.20
    let bodyX = cx - h * 0.21
    let bodyY = cy - bodyH / 2
    let body = NSBezierPath(roundedRect: NSRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
                            xRadius: h * 0.02, yRadius: h * 0.02)
    body.fill()

    let cone = NSBezierPath()
    cone.move(to: NSPoint(x: bodyX + bodyW, y: cy + h * 0.10))
    cone.line(to: NSPoint(x: cx + h * 0.05, y: cy + h * 0.30))
    cone.line(to: NSPoint(x: cx + h * 0.05, y: cy - h * 0.30))
    cone.line(to: NSPoint(x: bodyX + bodyW, y: cy - h * 0.10))
    cone.close()
    cone.fill()

    for radius in [h * 0.15, h * 0.23] {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: cx + h * 0.06, y: cy),
                      radius: radius, startAngle: -55, endAngle: 55)
        arc.lineWidth = h * 0.05
        arc.lineCapStyle = .round
        arc.stroke()
    }
}

let base: NSImage = {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()

    let shape = NSRect(x: margin, y: margin, width: canvas - margin * 2, height: canvas - margin * 2)
    let bg = NSBezierPath(roundedRect: shape, xRadius: cornerRadius, yRadius: cornerRadius)
    bg.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.28, green: 0.56, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.24, blue: 0.85, alpha: 1),
    ])!.draw(in: shape, angle: -90)

    NSColor.white.setStroke()
    drawSpeaker(centerX: canvas / 2, centerY: canvas / 2, height: 520)

    image.unlockFocus()
    return image
}()

let spec: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, px) in spec {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    base.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to render \(name)\n".data(using: .utf8)!)
        continue
    }
    try? png.write(to: URL(fileURLWithPath: outDir + "/" + name))
}
print("iconset written to \(outDir)")
