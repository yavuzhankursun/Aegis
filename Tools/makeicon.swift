#!/usr/bin/env swift
// Aegis uygulama simgesini üretir: squircle gövde + gradyan + cam parlaması + kalkan.
import AppKit
import CoreGraphics

let size = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

let s = CGFloat(size)
let inset = s * 0.085
let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
let radius = rect.width * 0.2237   // Apple squircle oranı

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Gövde gradyanı
context.saveGState()
context.addPath(rounded(rect, radius))
context.clip()

let colors = [
    CGColor(red: 0.30, green: 0.34, blue: 0.96, alpha: 1),
    CGColor(red: 0.47, green: 0.31, blue: 0.93, alpha: 1),
    CGColor(red: 0.24, green: 0.62, blue: 0.96, alpha: 1),
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                          locations: [0, 0.55, 1])!
context.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])

// Üst cam parlaması
let glossColors = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.38),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray
let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glossColors, locations: [0, 1])!
context.saveGState()
context.addEllipse(in: CGRect(x: rect.minX - rect.width * 0.2, y: rect.midY,
                              width: rect.width * 1.4, height: rect.height * 0.85))
context.clip()
context.drawLinearGradient(gloss,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.midY),
                           options: [])
context.restoreGState()

// Arka plan halkaları (telemetri hissi)
context.setLineWidth(s * 0.012)
for (index, factor) in [0.62, 0.78, 0.94].enumerated() {
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10 - Double(index) * 0.025))
    let d = rect.width * factor
    context.strokeEllipse(in: CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d))
}
context.restoreGState()

// Kalkan
let shieldWidth = rect.width * 0.46
let shieldHeight = rect.height * 0.54
let cx = rect.midX
let top = rect.midY + shieldHeight * 0.5
let bottom = rect.midY - shieldHeight * 0.5

let shield = CGMutablePath()
shield.move(to: CGPoint(x: cx, y: top))
shield.addLine(to: CGPoint(x: cx + shieldWidth / 2, y: top - shieldHeight * 0.22))
shield.addCurve(to: CGPoint(x: cx, y: bottom),
                control1: CGPoint(x: cx + shieldWidth / 2, y: bottom + shieldHeight * 0.34),
                control2: CGPoint(x: cx + shieldWidth * 0.28, y: bottom + shieldHeight * 0.06))
shield.addCurve(to: CGPoint(x: cx - shieldWidth / 2, y: top - shieldHeight * 0.22),
                control1: CGPoint(x: cx - shieldWidth * 0.28, y: bottom + shieldHeight * 0.06),
                control2: CGPoint(x: cx - shieldWidth / 2, y: bottom + shieldHeight * 0.34))
shield.closeSubpath()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
context.addPath(shield)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
context.fillPath()
context.restoreGState()

// Kalkan içindeki nabız çizgisi
context.saveGState()
context.addPath(shield)
context.clip()
context.setLineWidth(s * 0.030)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setStrokeColor(CGColor(red: 0.33, green: 0.35, blue: 0.94, alpha: 1))
let baseY = rect.midY - shieldHeight * 0.02
let unit = shieldWidth * 0.16
context.move(to: CGPoint(x: cx - unit * 2.4, y: baseY))
context.addLine(to: CGPoint(x: cx - unit * 1.1, y: baseY))
context.addLine(to: CGPoint(x: cx - unit * 0.45, y: baseY + unit * 1.25))
context.addLine(to: CGPoint(x: cx + unit * 0.35, y: baseY - unit * 1.25))
context.addLine(to: CGPoint(x: cx + unit * 1.0, y: baseY))
context.addLine(to: CGPoint(x: cx + unit * 2.4, y: baseY))
context.strokePath()
context.restoreGState()

guard let image = context.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
