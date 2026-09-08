// Renders Resources/icon.svg as an .iconset.
//
// The artwork is three primitives, so it is drawn directly with CoreGraphics
// rather than rasterising the SVG: that keeps every size crisp instead of
// scaling a 24px bitmap, and avoids a dependency on librsvg or similar.
//
// Tabler "wash-dry-shade", 24x24 viewBox (https://tabler.io/icons?icon=wash-dry-shade):
//   rounded rect  x3 y3 w18 h18 r3
//   line (3,11) -> (11,3)
//   line (3,17) -> (17,3)

import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

/// Draws the glyph into `box`, mapping the 24-unit viewBox onto it.
func drawGlyph(_ c: CGContext, box: CGRect, lineWidth: CGFloat) {
    let s = box.width / 24
    c.saveGState()
    c.translateBy(x: box.minX, y: box.minY + box.height)
    c.scaleBy(x: s, y: -s)          // SVG is y-down

    c.setLineWidth(lineWidth)       // in viewBox units; the CTM scales it
    c.setLineCap(.round)
    c.setLineJoin(.round)

    c.addPath(CGPath(roundedRect: CGRect(x: 3, y: 3, width: 18, height: 18),
                     cornerWidth: 3, cornerHeight: 3, transform: nil))
    c.strokePath()

    c.move(to: CGPoint(x: 3, y: 11)); c.addLine(to: CGPoint(x: 11, y: 3))
    c.move(to: CGPoint(x: 3, y: 17)); c.addLine(to: CGPoint(x: 17, y: 3))
    c.strokePath()

    c.restoreGState()
}

func render(px: Int) -> Data {
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                      bytesPerRow: 0, space: srgb,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setAllowsAntialiasing(true)
    c.interpolationQuality = .high

    let p = CGFloat(px)
    // macOS tiles do not fill their canvas; ~82% centered matches the system look.
    let side = p * 0.82
    let tile = CGRect(x: (p - side) / 2, y: (p - side) / 2, width: side, height: side)

    c.saveGState()
    c.addPath(CGPath(roundedRect: tile, cornerWidth: side * 0.225,
                     cornerHeight: side * 0.225, transform: nil))
    c.clip()
    let grad = CGGradient(colorsSpace: srgb, colors: [
        CGColor(srgbRed: 0.18, green: 0.18, blue: 0.20, alpha: 1),
        CGColor(srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(grad, start: CGPoint(x: tile.minX, y: tile.maxY),
                         end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    c.restoreGState()

    // Small sizes need a heavier stroke to survive antialiasing.
    let weight: CGFloat = px <= 32 ? 2.8 : 2.3
    c.setStrokeColor(CGColor(srgbRed: 0.98, green: 0.98, blue: 0.96, alpha: 1))
    let g = side * 0.78
    drawGlyph(c, box: CGRect(x: (p - g) / 2, y: (p - g) / 2, width: g, height: g),
              lineWidth: weight)

    return NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
}

let variants: [(String, Int)] = [
    ("icon_16x16",      16), ("icon_16x16@2x",    32),
    ("icon_32x32",      32), ("icon_32x32@2x",    64),
    ("icon_128x128",   128), ("icon_128x128@2x", 256),
    ("icon_256x256",   256), ("icon_256x256@2x", 512),
    ("icon_512x512",   512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    try! render(px: px).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("wrote \(variants.count) sizes to \(outDir)")
