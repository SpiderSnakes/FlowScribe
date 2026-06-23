import SwiftUI

/// Fond « aurora » vivant : blobs lumineux qui dérivent lentement sur le dégradé sombre.
/// Le blend additif (plusLighter) fait luire les zones où les blobs se croisent.
struct AuroraBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    Theme.backgroundGradient
                    blob(Theme.sky.opacity(0.09),
                         x: w * (0.50 + 0.30 * cos(t * 0.10)),
                         y: h * (0.28 + 0.20 * sin(t * 0.13)), r: min(w, h) * 1.1)
                    blob(Theme.accent.opacity(0.06),
                         x: w * (0.28 + 0.26 * sin(t * 0.08)),
                         y: h * (0.72 + 0.18 * cos(t * 0.11)), r: min(w, h) * 1.2)
                    blob(Color(red: 0.14, green: 0.34, blue: 0.7).opacity(0.07),
                         x: w * (0.78 + 0.20 * cos(t * 0.12)),
                         y: h * (0.62 + 0.22 * sin(t * 0.09)), r: min(w, h) * 1.0)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func blob(_ color: Color, x: CGFloat, y: CGFloat, r: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: r, height: r)
            .blur(radius: 120)
            .position(x: x, y: y)
            .blendMode(.plusLighter)
    }
}
