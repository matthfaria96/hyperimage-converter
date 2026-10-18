// Masks the square artwork into the macOS icon shape (824pt rounded square on a 1024 canvas) with a soft shadow.
// Usage: swift scripts/make-icon.swift <source.png> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <source.png> <output.png>\n".utf8))
    exit(1)
}

let canvas = 1024, body: CGFloat = 824, radius: CGFloat = 185
let inset = (CGFloat(canvas) - body) / 2
guard let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
let rect = CGRect(x: inset, y: inset + 10, width: body, height: body)
let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(shape)
ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.addPath(shape)
ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(cg, in: rect)

guard let out = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
