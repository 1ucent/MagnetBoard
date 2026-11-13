//
//  EdgeGather.swift
//  MagnetBoard
//
//  "Bring the UI to the edge the magnet is at." Turns a MagnetFrame plus the
//  board rect into one EdgeGather: which edge, where along it, how strongly.
//
//  Two ways in:
//   • the locator gives a position — use the nearest edge, and let the strength
//     climb as the magnet gets close to / past that edge;
//   • it does not (magnet beside the phone) — use `toward`, which the kit still
//     reports, and aim at the edge that direction points to.
//

import SwiftUI

enum BoardEdge {
    case left, right, top, bottom

    var label: String {
        switch self {
        case .left: return "LEFT"
        case .right: return "RIGHT"
        case .top: return "TOP"
        case .bottom: return "BOTTOM"
        }
    }
}

struct EdgeGather {

    var edge: BoardEdge
    /// Point on the edge, in global points.
    var anchor: CGPoint
    /// 0...1 — how far the UI has moved to the edge.
    var strength: CGFloat

    var isVertical: Bool {
        edge == .left || edge == .right
    }

    /// The point the board shrinks toward, in the board's own unit space.
    func unitPoint(in board: CGRect) -> UnitPoint {
        guard board.width > 1, board.height > 1 else { return .center }
        let fx = min(max((anchor.x - board.minX) / board.width, 0.12), 0.88)
        let fy = min(max((anchor.y - board.minY) / board.height, 0.10), 0.90)
        switch edge {
        case .left: return UnitPoint(x: 0, y: fy)
        case .right: return UnitPoint(x: 1, y: fy)
        case .top: return UnitPoint(x: fx, y: 0)
        case .bottom: return UnitPoint(x: fx, y: 1)
        }
    }

    /// A small extra nudge into the edge, on top of the scaling.
    var shift: CGVector {
        switch edge {
        case .left: return CGVector(dx: -16, dy: 0)
        case .right: return CGVector(dx: 16, dy: 0)
        case .top: return CGVector(dx: 0, dy: -14)
        case .bottom: return CGVector(dx: 0, dy: 14)
        }
    }

    // MARK: Building one

    static func make(frame: MagnetFrame, in rect: CGRect) -> EdgeGather? {
        guard rect.width > 40, rect.height > 40 else { return nil }
        let inner = rect.insetBy(dx: 2, dy: 2)

        if let p = frame.position {
            return fromPosition(p, frame: frame, inner: inner)
        }
        return fromDirection(frame, inner: inner)
    }

    private static func fromPosition(_ p: CGPoint, frame: MagnetFrame, inner: CGRect) -> EdgeGather? {
        let dLeft = p.x - inner.minX
        let dRight = inner.maxX - p.x
        let dTop = p.y - inner.minY
        let dBottom = inner.maxY - p.y

        let outside = max(0, max(-min(dLeft, dRight), -min(dTop, dBottom)))
        let nearestExit = min(dLeft, dRight, dTop, dBottom)
        let near = max(0, 1 - nearestExit / 150)

        let strength = min(1, max(near * near * 0.72, outside / 70)) * frame.presence
        guard strength > 0.03 else { return nil }

        let candidates: [(BoardEdge, CGFloat)] = [
            (.left, dLeft), (.right, dRight), (.top, dTop), (.bottom, dBottom),
        ]
        let edge = candidates.min { $0.1 < $1.1 }?.0 ?? .left

        var anchor = CGPoint(
            x: clamp(p.x, inner.minX + 44, inner.maxX - 44),
            y: clamp(p.y, inner.minY + 44, inner.maxY - 44)
        )
        switch edge {
        case .left: anchor.x = inner.minX
        case .right: anchor.x = inner.maxX
        case .top: anchor.y = inner.minY
        case .bottom: anchor.y = inner.maxY
        }

        return EdgeGather(edge: edge, anchor: anchor, strength: strength)
    }

    private static func fromDirection(_ frame: MagnetFrame, inner: CGRect) -> EdgeGather? {
        let pull = CGFloat(frame.pull)
        guard pull > 0.04 else { return nil }

        let direction = frame.toward
        guard abs(direction.dx) + abs(direction.dy) > 0.01 else { return nil }

        let sensor = MagnetSupport.sensorPosition
        let far = CGPoint(x: sensor.x + direction.dx * 4000,
                          y: sensor.y + direction.dy * 4000)

        let edge: BoardEdge
        if abs(direction.dx) >= abs(direction.dy) {
            edge = direction.dx >= 0 ? .right : .left
        } else {
            edge = direction.dy >= 0 ? .bottom : .top
        }

        var anchor = CGPoint(
            x: clamp(far.x, inner.minX + 44, inner.maxX - 44),
            y: clamp(far.y, inner.minY + 44, inner.maxY - 44)
        )
        switch edge {
        case .left: anchor.x = inner.minX
        case .right: anchor.x = inner.maxX
        case .top: anchor.y = inner.minY
        case .bottom: anchor.y = inner.maxY
        }

        return EdgeGather(edge: edge, anchor: anchor, strength: min(1, pull * 1.6))
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        guard low <= high else { return (low + high) / 2 }
        return min(max(value, low), high)
    }
}

// MARK: - Applying it

struct EdgeGatherEffect: ViewModifier {

    let gather: EdgeGather?
    let board: CGRect
    let enabled: Bool

    func body(content: Content) -> some View {
        let strength: CGFloat = enabled ? (gather?.strength ?? 0) : 0
        let anchor = gather?.unitPoint(in: board) ?? .center
        let shift = gather?.shift ?? .zero

        content
            .scaleEffect(1 - 0.38 * strength, anchor: anchor)
            .offset(x: shift.dx * strength, y: shift.dy * strength)
            .opacity(1 - 0.06 * strength)
    }
}

// MARK: - Where effects should focus

extension MagnetFrame {

    /// The point particles stream to and the puck snaps to: the magnet clamped
    /// inside `rect` (so it sits on the edge when the magnet is beside the
    /// phone), or the edge that `toward` points at when there is no position.
    /// `rect` is in the same space as `position` — global points.
    func attraction(in rect: CGRect, inset: CGFloat = 14) -> (point: CGPoint, clamped: Bool)? {
        if let position {
            let x = min(max(position.x, rect.minX + inset), rect.maxX - inset)
            let y = min(max(position.y, rect.minY + inset), rect.maxY - inset)
            return (CGPoint(x: x, y: y), abs(x - position.x) > 0.5 || abs(y - position.y) > 0.5)
        }

        guard pull > 0.05 else { return nil }
        guard abs(toward.dx) + abs(toward.dy) > 0.01 else { return nil }

        let sensor = MagnetSupport.sensorPosition
        let far = CGPoint(x: sensor.x + toward.dx * 4000,
                          y: sensor.y + toward.dy * 4000)
        return (CGPoint(x: min(max(far.x, rect.minX + inset), rect.maxX - inset),
                        y: min(max(far.y, rect.minY + inset), rect.maxY - inset)),
                true)
    }
}
