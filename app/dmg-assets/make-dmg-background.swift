// Renders the Symly DMG background: dark navy gradient, an accent arrow from the
// app icon toward the Applications folder, and a one-line install instruction.
// Regenerate the HiDPI background (committed as dmg-background.tiff), from the
// dmg-assets/ folder:
//   swift make-dmg-background.swift dmg-bg.png 1       # 1x, 660x420
//   swift make-dmg-background.swift dmg-bg@2x.png 2    # 2x, 1320x840
//   tiffutil -cathidpicheck dmg-bg.png dmg-bg@2x.png -out dmg-background.tiff
import AppKit
import CoreText

let scale = CommandLine.arguments.count > 2 ? (Int(CommandLine.arguments[2]) ?? 1) : 1
let W = 660, H = 420               // logical window size used by create-dmg
let ctx = CGContext(data: nil, width: W * scale, height: H * scale,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))   // CG origin is bottom-left

// Dark navy vertical gradient (matches the app's panel).
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [CGColor(red: 0.21, green: 0.25, blue: 0.42, alpha: 1),
                               CGColor(red: 0.12, green: 0.14, blue: 0.26, alpha: 1)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(H)), end: .zero, options: [])

// Accent arrow between the two icon slots (app at x=180, Applications at x=480),
// centered vertically with the icons (icon center is at y=200 from the top).
let cgY = CGFloat(H - 205)
ctx.setStrokeColor(CGColor(red: 0.62, green: 0.58, blue: 1.0, alpha: 0.95))
ctx.setLineWidth(4); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 282, y: cgY)); ctx.addLine(to: CGPoint(x: 384, y: cgY)); ctx.strokePath()
ctx.move(to: CGPoint(x: 372, y: cgY + 9)); ctx.addLine(to: CGPoint(x: 388, y: cgY))
ctx.addLine(to: CGPoint(x: 372, y: cgY - 9)); ctx.strokePath()

// One-line instruction, centered near the top.
let font = NSFont.systemFont(ofSize: 16, weight: .semibold) as CTFont
let attr = CFAttributedStringCreate(nil, "Drag Symly into Applications to install" as CFString,
    [kCTFontAttributeName: font,
     kCTForegroundColorAttributeName: CGColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1)] as CFDictionary)!
let line = CTLineCreateWithAttributedString(attr)
let tw = CTLineGetImageBounds(line, ctx).width
ctx.textPosition = CGPoint(x: (CGFloat(W) - tw) / 2, y: CGFloat(H - 56))
CTLineDraw(line, ctx)

let out = CommandLine.arguments.dropFirst().first ?? "dmg-background.png"
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
