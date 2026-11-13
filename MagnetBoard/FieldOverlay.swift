//
//  FieldOverlay.swift
//  MagnetBoard
//
//  Draws what the model is actually saying: the dashed beam from the
//  magnetometer to the magnet, the 1-sigma spread ring, a pulsing puck, and
//  expanding ripples for air taps. All of it is decoration, so it never
//  swallows touches.
//

import SwiftUI

struct FieldOverlay: View {

    let frame: MagnetFrame
    /// Global origin of the board, so global points become board-local ones.
    let origin: CGPoint
    let now: TimeInterval
    let reduceMotion: Bool

    private var sensor: CGPoint {
        CGPoint(
            x: MagnetSupport.sensorPosition.x - origin.x,
            y: MagnetSupport.sensorPosition.y - origin.y
        )
    }

    var body: some View {
        Canvas { context, size in
            drawSensor(in: &context)

            // Where the magnet is, or the edge it is pointing at when the
            // locator is unsure. Clamped inside the board so a magnet held
            // beside the phone still reads as "here, at the edge".
            let global = CGRect(origin: origin, size: size)
            guard let focus = frame.attraction(in: global) else { return }
            let magnet = CGPoint(x: focus.point.x - origin.x, y: focus.point.y - origin.y)

            let alpha = min(1, max(0, frame.presence))
            guard alpha > 0.01 else { return }

            drawBeam(from: sensor, to: magnet, alpha: alpha, in: &context)
            drawSpread(at: magnet, alpha: alpha, in: &context)
            drawPuck(at: magnet, alpha: alpha, size: size, in: &context)
        }
        .allowsHitTesting(false)
    }

    // MARK: Pieces

    private func drawSensor(in context: inout GraphicsContext) {
        let point = sensor
        var cross = Path()
        cross.move(to: CGPoint(x: point.x - 9, y: point.y))
        cross.addLine(to: CGPoint(x: point.x + 9, y: point.y))
        cross.move(to: CGPoint(x: point.x, y: point.y - 9))
        cross.addLine(to: CGPoint(x: point.x, y: point.y + 9))

        context.stroke(cross, with: .color(Theme.textDim.opacity(0.5)), lineWidth: 1)
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
            with: .color(Theme.textDim.opacity(0.7))
        )
    }

    private func drawBeam(from sensor: CGPoint, to magnet: CGPoint, alpha: Double, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: sensor)
        path.addLine(to: magnet)

        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [
                Theme.accent.opacity(0.0),
                Theme.accent.opacity(0.45 * alpha)
            ]),
            startPoint: sensor,
            endPoint: magnet
        )
        context.stroke(
            path,
            with: shading,
            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 7])
        )
    }

    private func drawSpread(at magnet: CGPoint, alpha: Double, in context: inout GraphicsContext) {
        let radius = max(26, frame.spread + 18)
        let rect = CGRect(
            x: magnet.x - radius,
            y: magnet.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(Theme.accent.opacity(0.18 * alpha)),
            style: StrokeStyle(lineWidth: 1, dash: [2, 5])
        )
    }

    private func drawPuck(at magnet: CGPoint, alpha: Double, size: CGSize,
                          in context: inout GraphicsContext) {
        let pulse: CGFloat = reduceMotion ? 0 : CGFloat(sin(now * 2.6)) * 8
        let halo = 58 + pulse

        context.fill(
            Path(ellipseIn: CGRect(x: magnet.x - halo, y: magnet.y - halo,
                                   width: halo * 2, height: halo * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    Theme.accent.opacity(0.34 * alpha),
                    Theme.accent.opacity(0.0)
                ]),
                center: magnet,
                startRadius: 0,
                endRadius: halo
            )
        )

        context.fill(
            Path(ellipseIn: CGRect(x: magnet.x - 11, y: magnet.y - 11, width: 22, height: 22)),
            with: .color(Color.white.opacity(0.92 * alpha))
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: magnet.x - 21, y: magnet.y - 21, width: 42, height: 42)),
            with: .color(Theme.accent.opacity(0.85 * alpha)),
            lineWidth: 2
        )

        // Height above the glass, or the rough distance when the locator is
        // off. Kept inside the canvas so an edge puck still shows its value.
        let metric = frame.height > 0.05 ? frame.height : frame.distance
        let label = Text(String(format: "%.1f cm", metric))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(Theme.accent.opacity(alpha))
        let labelX = min(max(magnet.x, 56), max(56, size.width - 56))
        context.draw(label, at: CGPoint(x: labelX, y: max(24, magnet.y - 44)), anchor: .center)
    }
}

// MARK: - Air-tap ripples

struct RippleLayer: View {

    let ripples: [MagnetRipple]
    let origin: CGPoint

    var body: some View {
        ZStack {
            ForEach(ripples) { ripple in
                RippleView(isTap: ripple.isTap)
                    .position(
                        x: ripple.point.x - origin.x,
                        y: ripple.point.y - origin.y
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private struct RippleView: View {

    let isTap: Bool
    @State private var animate = false

    var body: some View {
        Circle()
            .strokeBorder(isTap ? Theme.accent : Theme.warm, lineWidth: 2)
            .frame(width: 44, height: 44)
            .scaleEffect(animate ? 3.2 : 0.35)
            .opacity(animate ? 0 : 0.85)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9)) {
                    animate = true
                }
            }
    }
}
