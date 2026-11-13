//
//  Theme.swift
//  MagnetBoard
//
//  Palette, metrics and the small shared surfaces every tile uses. The board is
//  near-black so the magnet glow and the tile highlights do all the talking.
//

import SwiftUI

enum Theme {

    // MARK: Colors

    static let ink = Color(red: 0.020, green: 0.031, blue: 0.055)
    static let inkDeep = Color(red: 0.006, green: 0.012, blue: 0.024)
    static let surface = Color(red: 0.055, green: 0.078, blue: 0.114)
    static let stroke = Color.white.opacity(0.08)

    static let accent = Color(red: 0.35, green: 0.87, blue: 0.98)
    static let accentAlt = Color(red: 0.55, green: 0.45, blue: 1.00)
    static let mint = Color(red: 0.42, green: 0.96, blue: 0.69)
    static let warm = Color(red: 1.00, green: 0.51, blue: 0.38)

    static let text = Color.white.opacity(0.92)
    static let textDim = Color.white.opacity(0.45)

    // MARK: Metrics

    static let tileRadius: CGFloat = 26
    /// How far a tile feels the magnet, in points.
    static let reach: CGFloat = 380
}

// MARK: - Shared surfaces

extension View {

    /// The frosted card every control sits on.
    func tileSurface(active: Bool = false, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(Theme.surface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .strokeBorder(active ? Theme.accent.opacity(0.35) : Theme.stroke, lineWidth: 1)
            )
    }

    /// Tiny all-caps label used above every control.
    func tileLabel() -> some View {
        self
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(Theme.textDim)
    }
}

/// Digits that do not jitter while they tick.
extension Font {
    static func boardNumber(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
