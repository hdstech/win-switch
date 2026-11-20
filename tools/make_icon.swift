import AppKit
import CoreGraphics

// Renders WinSwitch.icns + a preview PNG.
// Usage: swift tools/make_icon.swift <output-dir>

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = "\(outDir)/icon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [r, g, b, a])!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawWindow(_ ctx: CGContext, _ rect: CGRect, body: CGColor, titleBar: CGColor, dots: Bool) {
    let path = rounded(rect, rect.height * 0.14)
    ctx.addPath(path)
    ctx.setFillColor(body)
    ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let barH = rect.height * 0.3
    ctx.setFillColor(titleBar)
    ctx.fill(CGRect(x: rect.minX, y: rect.maxY - barH, width: rect.width, height: barH))
    if dots {
        let d = barH * 0.32
        for i in 0..<3 {
            let cx = rect.minX + barH * (0.55 + CGFloat(i) * 0.75)
            let cy = rect.maxY - barH / 2
            ctx.setFillColor(rgba(0.9, 0.92, 0.97, 0.9))
            ctx.fillEllipse(in: CGRect(x: cx, y: cy - d / 2, width: d, height: d))
        }
    }
    ctx.restoreGState()
}

func arrowhead(_ ctx: CGContext, tip: CGPoint, tangent: CGVector, len: CGFloat, halfW: CGFloat, color: CGColor) {
    let n = 1 / hypot(tangent.dx, tangent.dy)
    let t = CGVector(dx: tangent.dx * n, dy: tangent.dy * n)
    let p = CGVector(dx: -t.dy, dy: t.dx)
    let base = CGPoint(x: tip.x - t.dx * len, y: tip.y - t.dy * len)
    ctx.setFillColor(color)
    ctx.move(to: tip)
    ctx.addLine(to: CGPoint(x: base.x + p.dx * halfW, y: base.y + p.dy * halfW))
    ctx.addLine(to: CGPoint(x: base.x - p.dx * halfW, y: base.y - p.dy * halfW))
    ctx.closePath()
    ctx.fillPath()
}

func arc(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
         startDeg: CGFloat, endDeg: CGFloat, lineWidth: CGFloat, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    let s = startDeg * .pi / 180, e = endDeg * .pi / 180
    ctx.addArc(center: center, radius: radius, startAngle: s, endAngle: e, clockwise: e < s)
    ctx.strokePath()
}

func onCircle(_ c: CGPoint, _ r: CGFloat, _ deg: CGFloat) -> CGPoint {
    let a = deg * .pi / 180
    return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
}

func drawIcon(_ ctx: CGContext, size: CGFloat) {
    // Icon art bounds (macOS template: art is ~80.5% of the canvas)
    let side = size * 0.805
    let iconRect = CGRect(x: (size - side) / 2, y: (size - side) / 2 + size * 0.018,
                          width: side, height: side)
    let squircle = rounded(iconRect, side * 0.23)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.02,
                  color: rgba(0, 0, 0, 0.3))
    ctx.addPath(squircle)
    ctx.setFillColor(rgba(1, 1, 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Background gradient
    let grad = CGGradient(colorsSpace: srgb, colors: [
        rgba(0.40, 0.66, 0.99), rgba(0.24, 0.35, 0.90)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: iconRect.minX + side * 0.2, y: iconRect.maxY),
        end: CGPoint(x: iconRect.maxX - side * 0.2, y: iconRect.minY), options: [])

    // Top sheen
    let sheen = CGGradient(colorsSpace: srgb, colors: [
        rgba(1, 1, 1, 0.14), rgba(1, 1, 1, 0)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen,
        start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.midX, y: iconRect.maxY - side * 0.45), options: [])

    // Windows
    let u = side
    drawWindow(ctx,
        CGRect(x: iconRect.minX + u * 0.13, y: iconRect.minY + u * 0.40,
               width: u * 0.54, height: u * 0.40),
        body: rgba(0.72, 0.82, 1.0, 0.50), titleBar: rgba(0.60, 0.72, 0.97, 0.60), dots: false)
    drawWindow(ctx,
        CGRect(x: iconRect.minX + u * 0.33, y: iconRect.minY + u * 0.13,
               width: u * 0.54, height: u * 0.40),
        body: rgba(1, 1, 1, 0.96), titleBar: rgba(0.80, 0.86, 0.98, 0.95), dots: true)

    // Switch arrows
    let amber = rgba(1.0, 0.78, 0.28)
    let c = CGPoint(x: iconRect.midX, y: iconRect.midY)
    let radius = u * 0.435
    let lw = u * 0.075

    arc(ctx, center: c, radius: radius, startDeg: 152, endDeg: 28, lineWidth: lw, color: amber)
    arc(ctx, center: c, radius: radius, startDeg: 332, endDeg: 208, lineWidth: lw, color: amber)

    // Arrowheads (CW traversal tangent at end angle)
    let hl = u * 0.135, hw = u * 0.050
    arrowhead(ctx, tip: onCircle(c, radius, 28), tangent: CGVector(dx: sin(28 * .pi / 180), dy: -cos(28 * .pi / 180)),
              len: hl, halfW: hw, color: amber)
    arrowhead(ctx, tip: onCircle(c, radius, 208), tangent: CGVector(dx: sin(208 * .pi / 180), dy: -cos(208 * .pi / 180)),
              len: hl, halfW: hw, color: amber)

    ctx.restoreGState()
}

func renderPNG(size: Int, path: String) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(ctx, size: CGFloat(size))
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in specs { renderPNG(size: px, path: "\(iconset)/\(name)") }
renderPNG(size: 1024, path: "\(outDir)/preview.png")
print("Iconset + preview written to \(outDir)")
