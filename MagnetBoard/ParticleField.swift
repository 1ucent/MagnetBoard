//
//  ParticleField.swift
//  MagnetBoard
//
//  A field of dust that streams to the magnet and piles up where the magnet is
//  at the edge of the screen. Positions are analytic (a function of time and
//  presence), so there is no per-frame state to accumulate or reset.
//

import SwiftUI

private struct ParticleSeed {
    let x: Double
    let y: Double
    let size: Double
    let delay: Double
    let phase: Double
    let speed: Double

    static let all: [ParticleSeed] = {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 11) & 0x1F_FFFF) / Double(0x1F_FFFF)
        }
        var out: [ParticleSeed] = []
        out.reserveCapacity(count)
        for _ in 0..<count {
            out.append(ParticleSeed(
                x: next(),
                y: next(),
                size: 1.2 + next() * 2.0,
                delay: next() * 0.52,
                phase: next() * Double.pi * 2,
                speed: 0.22 + next() * 0.75
            ))
        }
        return out
    }()

    static let count = 88
}

struct ParticleField: View {

    let frame: MagnetFrame
    /// Global origin of this canvas (it ignores the safe area).
    let origin: CGPoint
    let now: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        Canvas { context, canvasSize in
            guard canvasSize.width > 1, canvasSize.height > 1 else { return }

            let globalRect = CGRect(origin: origin, size: canvasSize)
            let focus = frame.attraction(in: globalRect)
            let target = focus.map { CGPoint(x: $0.point.x - origin.x, y: $0.point.y - origin.y) }
            let piled = focus?.clamped ?? false
            let presence = frame.presence
            let motion = reduceMotion ? 0.0 : 1.0

            for seed in ParticleSeed.all {
                let home = CGPoint(
                    x: seed.x * canvasSize.width + sin(now * 0.35 + seed.phase) * 14 * motion,
                    y: seed.y * canvasSize.height + cos(now * 0.29 + seed.phase * 1.7) * 11 * motion
                )

                var point = home
                var tail: CGPoint?
                var energy = 0.0

                if let target, presence > 0.01 {
                    let u = ease(presence, delay: seed.delay)
                    let spread = (piled ? 12.0 : 30.0) + 20.0 * (1.0 - seed.delay)
                    let angle = seed.phase + now * seed.speed * motion
                    let needle = CGPoint(
                        x: target.x + CGFloat(cos(angle) * spread),
                        y: target.y + CGFloat(sin(angle) * spread * 0.82)
                    )
                    point = lerp(home, needle, CGFloat(u))
                    if u > 0.18 {
                        tail = lerp(home, needle, CGFloat(max(0, u - 0.16)))
                    }
                    energy = u
                }

                let alpha = 0.10 + 0.72 * energy
                let radius = CGFloat(seed.size * (0.85 + 0.95 * energy))
                let tint = Color(
                    red: 0.35 + 0.52 * energy,
                    green: 0.87 + 0.10 * energy,
                    blue: 0.98 + 0.02 * energy,
                    opacity: alpha
                )

                if let tail {
                    var path = Path()
                    path.move(to: tail)
                    path.addLine(to: point)
                    context.stroke(
                        path,
                        with: .color(Color(red: 0.35, green: 0.85, blue: 0.98,
                                           opacity: 0.32 * energy)),
                        style: StrokeStyle(lineWidth: radius * 1.1, lineCap: .round)
                    )
                }

                let box = CGRect(x: point.x - radius, y: point.y - radius,
                                 width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: box), with: .color(tint))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Staggered arrival: particles with a bigger delay join the stream later.
    private func ease(_ presence: Double, delay: Double) -> Double {
        let span = max(0.05, 1 - delay)
        let u = min(1, max(0, (presence - delay) / span))
        return u * u * (3 - 2 * u)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
