// Draws Tavra's app icon: a dark tile, a trackpad in a hairline, one edge lit.
// swift scripts/icon.swift <out.png> [size]
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon_1024.png"
let size = args.count > 2 ? CGFloat(Double(args[2]) ?? 1024) : 1024
let px = Int(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: size / 1024, y: size / 1024)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(color(0x101114)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let wash = CGGradient(colorsSpace: space, colors: [color(0x1D1E24), color(0x0C0D10)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(wash, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
ctx.restoreGState()

// The trackpad.
let pad = CGRect(x: 232, y: 322, width: 560, height: 380)
let padPath = CGPath(roundedRect: pad, cornerWidth: 56, cornerHeight: 56, transform: nil)
ctx.addPath(padPath); ctx.setFillColor(color(0xFFFFFF, 0.07)); ctx.fillPath()
ctx.addPath(padPath); ctx.setStrokeColor(color(0xF1F1EF, 0.72)); ctx.setLineWidth(16); ctx.strokePath()

// The lit edge, with its glow.
let lilac: UInt32 = 0xC4A9E8, ice: UInt32 = 0x7FC8E8
ctx.saveGState()
ctx.addPath(padPath); ctx.clip()
let glow = CGGradient(colorsSpace: space, colors: [color(lilac, 0.62), color(lilac, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(glow, start: CGPoint(x: pad.maxX, y: 0), end: CGPoint(x: pad.maxX - 280, y: 0), options: [])
ctx.restoreGState()
let edge = CGPath(roundedRect: CGRect(x: pad.maxX - 66, y: pad.minY + 52, width: 30, height: pad.height - 104), cornerWidth: 15, cornerHeight: 15, transform: nil)
ctx.saveGState()
ctx.addPath(edge); ctx.clip()
let line = CGGradient(colorsSpace: space, colors: [color(ice), color(lilac)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(line, start: CGPoint(x: 0, y: pad.minY), end: CGPoint(x: 0, y: pad.maxY), options: [])
ctx.restoreGState()

// A fingertip on it.
ctx.setShadow(offset: .zero, blur: 46, color: color(lilac, 0.9))
ctx.addEllipse(in: CGRect(x: pad.maxX - 51 - 48, y: pad.midY + 4, width: 96, height: 96))
ctx.setFillColor(color(0xF6F4FA)); ctx.fillPath()

let image = ctx.makeImage()!
try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
