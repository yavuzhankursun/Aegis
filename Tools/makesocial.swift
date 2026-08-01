#!/usr/bin/env swift
// GitHub sosyal önizleme görseli (1280×640, 2x çizilir).
// Kullanım: swift Tools/makeicon.swift /tmp/icon.png && swift Tools/makesocial.swift /tmp/icon.png docs/social-preview.png
import AppKit
import CoreGraphics

let iconPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon_1024.png"
let outputPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "docs/social-preview.png"

let width = 2560, height = 1280   // 2x
guard let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

let w = CGFloat(width), h = CGFloat(height)

// Zemin — Theme.void
context.setFillColor(CGColor(red: 0.035, green: 0.045, blue: 0.062, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: w, height: h))

// Köşe ışımaları (statik, tema aksanları)
func glow(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: CGColor) {
    let colors = [color, CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: colors, locations: [0, 1]) else { return }
    context.drawRadialGradient(gradient,
                               startCenter: CGPoint(x: x, y: y), startRadius: 0,
                               endCenter: CGPoint(x: x, y: y), endRadius: radius,
                               options: [])
}
glow(w * 0.12, h * 0.88, 900, CGColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.14))   // cyan
glow(w * 0.92, h * 0.10, 800, CGColor(red: 0.51, green: 0.47, blue: 0.88, alpha: 0.12))   // plasma
glow(w * 0.55, h * 0.50, 1100, CGColor(red: 0.08, green: 0.72, blue: 0.65, alpha: 0.05))  // teal

// İnce ızgara dokusu
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.025))
context.setLineWidth(1)
var x: CGFloat = 0
while x <= w { context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: h)); x += 96 }
var y: CGFloat = 0
while y <= h { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: w, y: y)); y += 96 }
context.strokePath()

// Uygulama simgesi (makeicon çıktısı) — sol blok
if let iconData = FileManager.default.contents(atPath: iconPath),
   let iconImage = NSBitmapImageRep(data: iconData)?.cgImage {
    let size: CGFloat = 560
    let rect = CGRect(x: 220, y: (h - size) / 2, width: size, height: size)
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 60,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    context.draw(iconImage, in: rect)
    context.setShadow(offset: .zero, blur: 0, color: nil)
}

// Metinler
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight,
          color: NSColor, rounded: Bool = true, kern: CGFloat = 0) {
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let descriptor = font.fontDescriptor.withDesign(.rounded),
       let roundedFont = NSFont(descriptor: descriptor, size: size) { font = roundedFont }
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: x, y: y))
}

let textX: CGFloat = 940
draw("Aegis", x: textX, y: 720, size: 190, weight: .bold, color: .white)
draw("Mac kontrol merkezi — macOS Tahoe için",
     x: textX, y: 620, size: 58, weight: .medium,
     color: NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1))
draw("Pil gauge kaydı · Aşınma tahmini · Bellek & Enerji · Güvenli temizlik",
     x: textX, y: 520, size: 47, weight: .regular,
     color: NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1))

// Rozet çipleri
func chip(_ text: String, x: CGFloat, tint: NSColor) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 40, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: tint]
    let string = NSAttributedString(string: text, attributes: attributes)
    let textSize = string.size()
    let rect = CGRect(x: x, y: 330, width: textSize.width + 64, height: 92)
    let path = CGPath(roundedRect: rect, cornerWidth: 46, cornerHeight: 46, transform: nil)
    context.addPath(path)
    context.setFillColor(tint.withAlphaComponent(0.12).cgColor)
    context.fillPath()
    context.addPath(path)
    context.setStrokeColor(tint.withAlphaComponent(0.35).cgColor)
    context.setLineWidth(2)
    context.strokePath()
    string.draw(at: NSPoint(x: rect.minX + 32, y: rect.minY + (rect.height - textSize.height) / 2))
    return rect.maxX + 36
}
var chipX: CGFloat = textX
chipX = chip("SwiftUI + Liquid Glass", x: chipX, tint: NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1))
chipX = chip("Ağ yok · sudo yok", x: chipX, tint: NSColor(red: 0.08, green: 0.72, blue: 0.65, alpha: 1))
chipX = chip("MIT", x: chipX, tint: NSColor(red: 0.62, green: 0.67, blue: 0.73, alpha: 1))

draw("github.com/yavuzhankursun/Aegis", x: textX, y: 200, size: 42, weight: .medium,
     color: NSColor(red: 0.40, green: 0.45, blue: 0.52, alpha: 1), rounded: false, kern: 0.5)

// PNG yaz
guard let cgImage = context.makeImage() else { exit(1) }
let representation = NSBitmapImageRep(cgImage: cgImage)
representation.size = NSSize(width: 1280, height: 640)
guard let png = representation.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: outputPath))
print("yazıldı: \(outputPath)")
