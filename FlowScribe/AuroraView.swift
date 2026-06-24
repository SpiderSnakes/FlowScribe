// FlowScribe/AuroraView.swift
import SwiftUI
import FlowScribeCore

/// Rubans d'aurore : MeshGradient 3×3 aux points internes animés, fortement flouté.
struct AuroraView: View {
    @Environment(\.ambiance) private var ambiance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    var surface: AmbianceSurface = .appWindow

    var body: some View {
        let animate = ambiance.animates(surface, reduceMotion: reduceMotion,
                                        windowActive: activeState != .inactive)
        let p = ambiance.palette
        TimelineView(.animation(minimumInterval: nil, paused: !animate)) { tl in
            let t = animate ? tl.date.timeIntervalSinceReferenceDate : 0
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors(p))
                .blur(radius: 48)
        }
        .allowsHitTesting(false)
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ a: Double, _ b: Double) -> Float { Float(0.5 + a * 0.18 * sin(t * b)) }
        return [
            SIMD2(0, 0),            SIMD2(0.5, 0),          SIMD2(1, 0),
            SIMD2(0, 0.5),          SIMD2(w(1, 0.7), w(1, 0.9)), SIMD2(1, 0.5),
            SIMD2(0, 1),            SIMD2(0.5, 1),          SIMD2(1, 1),
        ]
    }
    private func colors(_ p: BrandPalette) -> [Color] {
        let a = p.auroraColors
        return [p.base, a[1].opacity(0.7), p.base,
                a[0].opacity(0.8), a[2].opacity(0.9), a[3].opacity(0.8),
                p.base, a[2].opacity(0.7), p.base]
    }
}
