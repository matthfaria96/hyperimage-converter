// Masks the square artwork into the macOS icon shape with a soft shadow, on Apple's icon grid:
// an 824 px continuous-corner squircle (superellipse n = 5) centred on the 1024 px canvas, like the
// other witchmymac apps, plus a thin glass highlight on the rim.
// Usage: swift scripts/make-icon.swift <source.png> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <source.png> <output.png>\n".utf8))
    exit(1)
}

/// Continuous-corner squircle (superellipse n = 5), the corner profile of Apple's icons.
func squircle(in rect: CGRect, exponent n: CGFloat = 5, steps: Int = 1440) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = CGPoint(x: rect.midX + pow(abs(c), 2 / n) * a * (c < 0 ? -1 : 1),
                            y: rect.midY + pow(abs(s), 2 / n) * b * (s < 0 ? -1 : 1))
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

let canvas = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(in: body)
guard let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(shape)
ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(cg, in: body)
ctx.restoreGState()

// Thin glass reflection on the rim, strongest at the top.
ctx.saveGState()
ctx.addPath(squircle(in: body.insetBy(dx: 4, dy: 4)))
ctx.setLineWidth(3)
ctx.replacePathWithStrokedPath()
ctx.clip()
let rim = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
    CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0.04), CGColor(gray: 1, alpha: 0.10),
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(rim, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.minY), options: [])
ctx.restoreGState()

guard let out = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
