// FlowScribe/BorderGlow.swift
import SwiftUI
import FlowScribeCore

/// Contour lumineux animé (réf. Border Glow). S'éteint en statique si les animations sont coupées.
struct BorderGlow: ViewModifier {
    @Environment(\.ambiance) private var ambiance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    var active: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let animate = active && ambiance.animates(.appWindow, reduceMotion: reduceMotion,
                                                  windowActive: activeState != .inactive)
        content.overlay {
            if active {
                TimelineView(.animation(minimumInterval: nil, paused: !animate)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let deg = animate ? (t * 60).truncatingRemainder(dividingBy: 360) : 0
                    let ring = ambiance.palette.auroraColors + [ambiance.palette.auroraColors.first ?? .white]
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(AngularGradient(colors: ring, center: .center,
                                                      angle: .degrees(deg)), lineWidth: 1.5)
                        .blur(radius: 0.6)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func borderGlow(active: Bool = true, cornerRadius: CGFloat = 12) -> some View {
        modifier(BorderGlow(active: active, cornerRadius: cornerRadius))
    }
}
