//
//  MagneticTile.swift
//  MagnetBoard
//
//  Wraps any control so it leans toward the magnet: the closer the magnet
//  (and the more present it is), the further the tile is pulled, the more it
//  tilts, and the hotter its glow. Values come straight from MagnetKit's
//  smoothed reading, so no extra animation is needed.
//

import SwiftUI

/// Reports a tile's global frame so the tile can measure itself against the
/// magnet position, which MagnetKit reports in global points.
private struct TileFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct MagneticTile<Content: View>: View {

    let frame: MagnetFrame
    let reach: CGFloat
    let travel: CGFloat
    let tilt: Double
    let glow: Color
    let content: () -> Content

    @State private var rect: CGRect = .zero

    init(
        frame: MagnetFrame,
        reach: CGFloat = Theme.reach,
        travel: CGFloat = 22,
        tilt: Double = 3.5,
        glow: Color = Theme.accent,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.frame = frame
        self.reach = reach
        self.travel = travel
        self.tilt = tilt
        self.glow = glow
        self.content = content
    }

    var body: some View {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let influence = frame.influence(at: center, reach: reach)
        let direction = frame.direction(from: center)
        let lean = Double(direction.dx) * tilt * Double(influence)

        content()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TileFrameKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            )
            .onPreferenceChange(TileFrameKey.self) { newValue in
                rect = newValue
            }
            .offset(
                x: direction.dx * influence * travel,
                y: direction.dy * influence * travel
            )
            .rotationEffect(.degrees(lean))
            .scaleEffect(1 + influence * 0.035)
            .shadow(
                color: glow.opacity(0.06 + 0.45 * Double(influence)),
                radius: 8 + 26 * influence,
                x: 0,
                y: 6 + 10 * influence
            )
    }
}
