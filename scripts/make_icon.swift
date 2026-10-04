// Renders the PhotoFlow app icon (1024×1024 PNG): a colourful camera aperture
// whose blades echo the colour labels, on a dark macOS-style squircle.
// Usage: swift scripts/make_icon.swift <output.png>

import CoreGraphics
import Foundation
import ImageIO

let canvas = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func point(_ center: CGPoint, _ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
    CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
}

let center = CGPoint(x: 512, y: 512)

// MARK: Squircle body (Apple icon grid: 824pt body, 100pt margin)

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x000000, 0.42))
ctx.addPath(bodyPath)
ctx.setFillColor(rgb(0x0B0E22))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([rgb(0x2B2F72), rgb(0x161A3E), rgb(0x090B1A)], [0, 0.55, 1]),
    start: CGPoint(x: 300, y: 924), end: CGPoint(x: 700, y: 100),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
ctx.drawRadialGradient(
    gradient([rgb(0x8A6CFF, 0.45), rgb(0x8A6CFF, 0)]),
    startCenter: center, startRadius: 0, endCenter: center, endRadius: 470, options: []
)
ctx.drawRadialGradient(
    gradient([rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)]),
    startCenter: CGPoint(x: 330, y: 860), startRadius: 0,
    endCenter: CGPoint(x: 330, y: 860), endRadius: 420, options: []
)
ctx.restoreGState()

// Thin inner bevel highlight.
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// MARK: Lens barrel

let barrelRadius: CGFloat = 338
let bladeRadius: CGFloat = 300

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0x000000, 0.55))
ctx.addEllipse(in: CGRect(x: center.x - barrelRadius, y: center.y - barrelRadius, width: barrelRadius * 2, height: barrelRadius * 2))
ctx.setFillColor(rgb(0x1A1D33))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - barrelRadius, y: center.y - barrelRadius, width: barrelRadius * 2, height: barrelRadius * 2))
ctx.clip()
ctx.drawLinearGradient(
    gradient([rgb(0x4A4F72), rgb(0x1B1E33), rgb(0x0C0E1A)], [0, 0.5, 1]),
    start: CGPoint(x: 512, y: 512 + barrelRadius), end: CGPoint(x: 512, y: 512 - barrelRadius), options: []
)
ctx.restoreGState()

let innerRadius: CGFloat = bladeRadius + 8
ctx.addEllipse(in: CGRect(x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2))
ctx.setFillColor(rgb(0x06070E))
ctx.fillPath()

// MARK: Aperture blades

let bladeColors: [UInt32] = [0xFF5A5F, 0xFFB340, 0x3FD98A, 0x2EA8FF, 0x8B5CF6, 0xFF4FA3]
let count = bladeColors.count
let openingRadius: CGFloat = 112
let rotation: CGFloat = .pi / 12

let vertices = (0..<count).map { point(center, openingRadius, rotation + CGFloat($0) * 2 * .pi / CGFloat(count)) }

func direction(_ edge: Int) -> CGVector {
    let a = vertices[edge % count]
    let b = vertices[(edge + 1) % count]
    let length = hypot(b.x - a.x, b.y - a.y)
    return CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
}

/// Where the ray from `origin` along `dir` meets the blade circle.
func hitCircle(_ origin: CGPoint, _ dir: CGVector) -> CGPoint {
    let px = origin.x - center.x
    let py = origin.y - center.y
    let b = px * dir.dx + py * dir.dy
    let c = px * px + py * py - bladeRadius * bladeRadius
    let t = -b + sqrt(b * b - c)
    return CGPoint(x: origin.x + t * dir.dx, y: origin.y + t * dir.dy)
}

func angle(of p: CGPoint) -> CGFloat {
    atan2(p.y - center.y, p.x - center.x)
}

func blend(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> CGColor {
    func channel(_ v: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((v >> shift) & 0xFF) / 255 }
    return CGColor(
        srgbRed: channel(a, 16) * (1 - t) + channel(b, 16) * t,
        green: channel(a, 8) * (1 - t) + channel(b, 8) * t,
        blue: channel(a, 0) * (1 - t) + channel(b, 0) * t,
        alpha: 1
    )
}

for k in 0..<count {
    // Blade k is the wedge at vertex k+1 between edge k's extension and edge k+1's line.
    let start = vertices[(k + 1) % count]
    let outerLeft = hitCircle(start, direction(k + 1))
    let outerRight = hitCircle(start, direction(k))

    var from = angle(of: outerLeft)
    let to = angle(of: outerRight)
    while from < to { from += 2 * .pi }

    let path = CGMutablePath()
    path.move(to: start)
    path.addLine(to: outerLeft)
    let steps = 48
    for step in 1...steps {
        let a = from + (to - from) * CGFloat(step) / CGFloat(steps)
        path.addLine(to: point(center, bladeRadius, a))
    }
    path.closeSubpath()

    let base = bladeColors[k]
    let mid = (from + to) / 2
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([blend(base, 0xFFFFFF, 0.35), rgb(base), blend(base, 0x000000, 0.28)], [0, 0.45, 1]),
        start: start, end: point(center, bladeRadius, mid), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(rgb(0x06070E, 0.75))
    ctx.setLineWidth(7)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: Opening (lens glass)

let opening = CGMutablePath()
opening.addLines(between: vertices)
opening.closeSubpath()
ctx.saveGState()
ctx.addPath(opening)
ctx.clip()
ctx.drawRadialGradient(
    gradient([rgb(0x2A2F63), rgb(0x0B0D1E), rgb(0x040510)], [0, 0.6, 1]),
    startCenter: CGPoint(x: 490, y: 540), startRadius: 0,
    endCenter: center, endRadius: openingRadius, options: []
)
// Soft glass reflections
let glint = CGPoint(x: 476, y: 556)
ctx.drawRadialGradient(
    gradient([rgb(0xFFFFFF, 0.9), rgb(0xFFFFFF, 0)]),
    startCenter: glint, startRadius: 0, endCenter: glint, endRadius: 26, options: []
)
let glint2 = CGPoint(x: 548, y: 472)
ctx.drawRadialGradient(
    gradient([rgb(0xB9A8FF, 0.45), rgb(0xB9A8FF, 0)]),
    startCenter: glint2, startRadius: 0, endCenter: glint2, endRadius: 40, options: []
)
ctx.restoreGState()

// Barrel rim highlight
ctx.addEllipse(in: CGRect(x: center.x - barrelRadius + 1.5, y: center.y - barrelRadius + 1.5,
                          width: barrelRadius * 2 - 3, height: barrelRadius * 2 - 3))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.16))
ctx.setLineWidth(3)
ctx.strokePath()

// MARK: Write PNG

guard CommandLine.arguments.count > 1 else { fatalError("usage: make_icon.swift <out.png>") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let image = ctx.makeImage()!
let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("write failed") }
print("Wrote \(url.path)")
