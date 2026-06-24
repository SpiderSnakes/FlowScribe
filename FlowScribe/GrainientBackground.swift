// FlowScribe/GrainientBackground.swift
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Socle commun « grainient » : dégradé profond (palette) + grain fin, mat et premium.
/// Le grain est une texture pré-rendue, tilée à faible opacité → coût quasi nul (statique).
struct GrainientBackground: View {
    @Environment(\.ambiance) private var ambiance

    var body: some View {
        let p = ambiance.palette
        LinearGradient(colors: [p.baseTop, p.base], startPoint: .top, endPoint: .bottom)
            .overlay(
                Image(nsImage: GrainTexture.shared)
                    .resizable(resizingMode: .tile)
                    .opacity(0.05)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            )
            .ignoresSafeArea()
    }
}

/// Texture de bruit monochrome générée une fois (CIRandomGenerator).
enum GrainTexture {
    static let shared: NSImage = make(side: 180)
    private static func make(side: Int) -> NSImage {
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let noise = CIFilter.randomGenerator().outputImage ?? CIImage(color: .gray)
        let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        let rep = NSCIImageRep(ciImage: mono.cropped(to: rect))
        let img = NSImage(size: NSSize(width: side, height: side))
        img.addRepresentation(rep)
        return img
    }
}
