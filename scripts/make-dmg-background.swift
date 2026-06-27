#!/usr/bin/env swift
// Génère le fond du DMG d'installation (600×400) dans le style sombre « Voix → Lumière ».
// Rendu via CGContext bitmap (sans serveur de fenêtres) → exécutable en CI/headless.
// Usage : swift scripts/make-dmg-background.swift <chemin-sortie.png>
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "dmg-background.png")

let W = 600, H = 400
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("CGContext")
}
let w = CGFloat(W), h = CGFloat(H)

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

// 1) Dégradé de fond vertical : ardoise profonde → presque noir.
let bg = CGGradient(colorsSpace: cs,
                    colors: [rgb(0.09, 0.10, 0.14), rgb(0.03, 0.04, 0.06)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])

// 2) Lueur radiale (la « Lumière ») : violet → cyan, douce, en haut-centre.
func glow(center: CGPoint, radius: CGFloat, color: CGColor) {
    let g = CGGradient(colorsSpace: cs,
                       colors: [color, CGColor(colorSpace: cs, components: [0, 0, 0, 0])!] as CFArray,
                       locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius,
                           options: [])
}
ctx.saveGState()
ctx.setBlendMode(.plusLighter)
glow(center: CGPoint(x: w * 0.30, y: h * 0.80), radius: 300, color: rgb(0.49, 0.36, 1.0, 0.28))
glow(center: CGPoint(x: w * 0.72, y: h * 0.72), radius: 280, color: rgb(0.22, 0.82, 0.85, 0.22))
ctx.restoreGState()

// Texte CoreText centré horizontalement à une position y (origine bas). Clés kCT* → sans AppKit.
func drawText(_ s: String, size: CGFloat, y: CGFloat, color: CGColor) {
    let font = CTFontCreateUIFontForLanguage(.system, size, nil)
        ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
    ]
    let astr = CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary)!
    let line = CTLineCreateWithAttributedString(astr)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: (w - bounds.width) / 2, y: y)
    CTLineDraw(line, ctx)
}

// 3) Titre + sous-titre + flèche d'aide (« glisser vers Applications »).
drawText("FlowScribe", size: 34, y: h - 70, color: rgb(0.96, 0.97, 1.0))
drawText("Glissez l'app dans le dossier Applications", size: 14, y: 46, color: rgb(0.62, 0.66, 0.74))

// Flèche → entre les deux icônes (icônes posées vers le centre vertical par Finder).
ctx.saveGState()
ctx.setStrokeColor(rgb(0.55, 0.60, 0.70, 0.9))
ctx.setLineWidth(3)
ctx.setLineCap(.round)
let midY = h * 0.46
ctx.move(to: CGPoint(x: w * 0.44, y: midY))
ctx.addLine(to: CGPoint(x: w * 0.56, y: midY))
ctx.strokePath()
ctx.move(to: CGPoint(x: w * 0.56, y: midY))
ctx.addLine(to: CGPoint(x: w * 0.535, y: midY + 9))
ctx.addLine(to: CGPoint(x: w * 0.535, y: midY - 9))
ctx.closePath()
ctx.setFillColor(rgb(0.55, 0.60, 0.70, 0.9))
ctx.fillPath()
ctx.restoreGState()

// 4) Export PNG.
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("export")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("finalize") }
print("✅ fond DMG écrit : \(out.path)")
