//
//  MagnetEngine.swift
//  MagnetBoard
//
//  The only file that talks to MagnetKit. It turns the library's on-device
//  magnet model into a plain `MagnetFrame` per display refresh plus discrete
//  events (air taps, pushes, pull-aways), so every view stays dumb and cheap.
//
//  MagnetKit is added as a Swift Package (Libraries.dev › product MagnetKit) and
//  needs `Magnet.mfxl` in the app target. The #if canImport guards keep the app
//  buildable, with a visible warning, if the package has not been added yet.
//

import SwiftUI
import UIKit
import Combine

#if canImport(MagnetKit)
import MagnetKit
#endif

// MARK: - Support

/// Values that do not depend on the engine instance.
enum MagnetSupport {
    /// The magnetometer spot for an iPhone 15 Pro, in window points.
    /// (iPhone 16 Pro is close; other models shift by a few points.)
    static let sensorPosition = CGPoint(x: 70, y: 86)

    /// False when the Swift package has not been added yet.
    static var isLinked: Bool {
        #if canImport(MagnetKit)
        return true
        #else
        return false
        #endif
    }

    /// False when `Magnet.mfxl` is not in the app bundle. The kit still reports
    /// pull/direction, but the presence and air-tap networks are off.
    static var isModelLoaded: Bool {
        #if canImport(MagnetKit)
        return MagnetModel.bundled != nil
        #else
        return false
        #endif
    }
}

/// An air tap (or a non-tap event) to ripple at, in global points.
struct MagnetRipple: Identifiable {
    let id = UUID()
    let point: CGPoint
    let isTap: Bool
}

/// Short-lived banner describing the last gesture.
struct MagnetFlash: Equatable {
    let id = UUID()
    let label: String
    let symbol: String
    let detail: String
}

// MARK: - Frame

/// One frame of magnet input, in the same units as MagnetKit's `MagnetReading`.
struct MagnetFrame {
    /// False while the magnetometer has not reported yet (no sensor, or a
    /// Simulator without a simulated field).
    var available: Bool
    /// Where the magnet is, global points. Nil while the locator is off or unsure.
    var position: CGPoint?
    /// The locator's 1-sigma uncertainty, points.
    var spread: CGFloat
    /// Height above the glass, cm.
    var height: CGFloat
    /// 0...1: is a magnet really there.
    var presence: Double
    /// 0...1: closeness, already faded by presence.
    var pull: Double
    /// Unit vector from the sensor toward the magnet.
    var toward: CGVector
    /// Rough distance, cm.
    var distance: Double
    /// Closing speed, cm/s (positive toward the phone).
    var approachSpeed: Double
    /// Close enough to magnetise the phone.
    var tooClose: Bool
    /// A new zero is being taken.
    var calibrating: Bool
    /// Synthesised by the demo puck instead of the magnetometer.
    var isSimulated: Bool

    static let idle = MagnetFrame(
        available: false,
        position: nil,
        spread: 0,
        height: 0,
        presence: 0,
        pull: 0,
        toward: CGVector(dx: 0, dy: -1),
        distance: 0,
        approachSpeed: 0,
        tooClose: false,
        calibrating: false,
        isSimulated: false
    )

    /// 0...1 pull felt by something centred at `center`. Falls off with distance
    /// and is scaled by presence, so effects fade out when the magnet leaves.
    func influence(at center: CGPoint, reach: CGFloat) -> CGFloat {
        // While the locator is unsure (magnet beside the phone) there is no
        // position, but `pull`/`toward` still work: give every tile a small,
        // uniform drift in the magnet's direction.
        guard let position else { return CGFloat(pull) * 0.35 }

        let dx = position.x - center.x
        let dy = position.y - center.y
        let distance = max(1, sqrt(dx * dx + dy * dy))
        let near = max(0, 1 - distance / reach)
        return CGFloat(presence) * near * near
    }

    /// Unit vector from a view at `center` toward the magnet.
    func direction(from center: CGPoint) -> CGVector {
        guard let position else {
            return CGVector(dx: toward.dx, dy: toward.dy)
        }
        let dx = position.x - center.x
        let dy = position.y - center.y
        let length = max(0.001, sqrt(dx * dx + dy * dy))
        return CGVector(dx: dx / length, dy: dy / length)
    }
}

// MARK: - Events

enum MagnetEvent {
    case tap(CGPoint)
    case push(Double)
    case pullAway(Double)
    case swipe(String, Double)

    var label: String {
        switch self {
        case .tap: return "AIR TAP"
        case .push: return "PUSH"
        case .pullAway: return "PULLED AWAY"
        case .swipe(let direction, _): return "SWIPE \(direction.uppercased())"
        }
    }

    var symbol: String {
        switch self {
        case .tap: return "hand.tap.fill"
        case .push: return "arrow.down.forward"
        case .pullAway: return "arrow.up.backward"
        case .swipe: return "arrow.left.and.right"
        }
    }
}

// MARK: - Engine

@MainActor
final class MagnetEngine: ObservableObject {

    // MARK: Published state (discrete, not per-frame)

    @Published private(set) var ripples: [MagnetRipple] = []
    @Published private(set) var flash: MagnetFlash?
    @Published private(set) var tapCount = 0
    @Published private(set) var eventCount = 0
    @Published private(set) var lastEvent = "—"
    @Published private(set) var attached = false
    @Published private(set) var calibrating = false
    @Published private(set) var demoPoint = CGPoint(x: 250, y: 470)

    @Published var isDemoMode = false {
        didSet {
            guard isDemoMode != oldValue else { return }
            resetDemo()
            // Leaving demo mode picks the real magnetometer back up.
            if !isDemoMode && !attached { start() }
        }
    }

    /// North pole of the magnet faces the user (+1) instead of away (-1).
    @Published var northFaceUp = true {
        didSet { applyConfig() }
    }

    // MARK: Private state

    private var installedGestureHandler = false
    private var demoHeld = false
    private var demoPresence: Double = 0
    private var demoPreviousDistance: Double?
    private var demoLastTime: TimeInterval = 0
    private lazy var haptics = UIImpactFeedbackGenerator(style: .light)

    // MARK: Lifecycle

    func start() {
        installGestureHandler()
        applyConfig()

        #if canImport(MagnetKit)
        guard !isDemoMode else { return }
        MagnetSource.shared.attach()
        attached = true
        #endif
    }

    func stop() {
        #if canImport(MagnetKit)
        MagnetSource.shared.detach()
        #endif
        attached = false
    }

    func calibrate() {
        #if canImport(MagnetKit)
        MagnetSource.shared.calibrate()
        #endif
        calibrating = true
        setFlash("CALIBRATING", symbol: "scope", detail: "keep magnets away")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            self.calibrating = false
        }
    }

    // MARK: Sampling (called once per display refresh)

    func snapshot(now: TimeInterval) -> MagnetFrame {
        if isDemoMode { return demoSnapshot(now: now) }

        #if canImport(MagnetKit)
        let reading = MagnetSource.shared.reading(now: now)
        let ready = reading.available
        let span = reading.distance.isFinite ? reading.distance : 0

        return MagnetFrame(
            available: ready,
            position: reading.screenPosition,
            spread: CGFloat(reading.screenSpread),
            height: CGFloat(reading.height ?? 0),
            presence: ready ? Double(reading.presence) : 0,
            pull: ready ? Double(reading.pull) : 0,
            toward: CGVector(dx: CGFloat(reading.toward.dx), dy: CGFloat(reading.toward.dy)),
            distance: span,
            approachSpeed: Double(reading.approachSpeed),
            tooClose: reading.tooClose,
            calibrating: reading.calibrating,
            isSimulated: false
        )
        #else
        return .idle
        #endif
    }

    // MARK: Configuration

    private func applyConfig() {
        #if canImport(MagnetKit)
        let source = MagnetSource.shared
        source.config.locatorEnabled = true
        source.config.sensorPosition = MagnetSupport.sensorPosition
        source.config.magnetFace = northFaceUp ? 1 : -1
        #endif
    }

    private func installGestureHandler() {
        guard !installedGestureHandler else { return }
        installedGestureHandler = true

        #if canImport(MagnetKit)
        _ = MagnetSource.shared.addGestureHandler { [weak self] gesture in
            Task { @MainActor in
                guard let self else { return }
                switch gesture {
                case .tap(let at):
                    self.emit(.tap(at ?? MagnetSupport.sensorPosition))
                case .push(let speed):
                    self.emit(.push(Double(speed)))
                case .pullAway(let speed):
                    self.emit(.pullAway(Double(speed)))
                case .swipe(let direction, let speed):
                    self.emit(.swipe(Self.axis(of: direction), Double(speed)))
                }
            }
        }
        #endif
    }

    // MARK: Events

    private static func axis(of direction: CGVector) -> String {
        if abs(direction.dx) >= abs(direction.dy) {
            return direction.dx >= 0 ? "right" : "left"
        }
        return direction.dy >= 0 ? "down" : "up"
    }

    private func emit(_ event: MagnetEvent) {
        switch event {
        case .tap(let at):
            tapCount += 1
            pushRipple(at, isTap: true)
            haptics.impactOccurred()
        case .push, .pullAway, .swipe:
            haptics.impactOccurred(intensity: 0.6)
        }

        eventCount += 1
        lastEvent = event.label

        let detail: String
        switch event {
        case .tap:
            detail = "\(tapCount) total"
        case .push(let speed), .pullAway(let speed):
            detail = String(format: "%.0f cm/s", speed)
        case .swipe(let direction, let speed):
            detail = "\(direction) · \(Int(speed)) pt/s"
        }

        setFlash(event.label, symbol: event.symbol, detail: detail)
    }

    private func pushRipple(_ point: CGPoint, isTap: Bool) {
        ripples.append(MagnetRipple(point: point, isTap: isTap))
        if ripples.count > 5 {
            ripples.removeFirst(ripples.count - 5)
        }
    }

    private func setFlash(_ label: String, symbol: String, detail: String) {
        let new = MagnetFlash(label: label, symbol: symbol, detail: detail)
        flash = new
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            if self.flash?.id == new.id {
                self.flash = nil
            }
        }
    }

    // MARK: Demo magnet (Simulator, or a quick look without a magnet)

    func demoTouchBegan(at point: CGPoint) {
        demoPoint = point
        demoHeld = true
        demoPreviousDistance = nil
    }

    func demoTouchMoved(to point: CGPoint) {
        demoPoint = point
        demoHeld = true
    }

    func demoTouchEnded() {
        demoHeld = false
        demoPreviousDistance = nil
        if !isDemoMode { resetDemo() }
    }

    /// A tap on the puck stands in for an air tap.
    func demoAirTap(at point: CGPoint) {
        emit(.tap(point))
    }

    private func resetDemo() {
        demoHeld = false
        demoPresence = 0
        demoPreviousDistance = nil
        demoLastTime = 0
    }

    /// A magnet that follows the finger: distance falloff, presence fade in/out
    /// and closing speed are approximated so the UI behaves like the real thing.
    private func demoSnapshot(now: TimeInterval) -> MagnetFrame {
        let elapsed = demoLastTime == 0 ? 0 : now - demoLastTime
        let dt = max(0, min(0.05, elapsed))
        demoLastTime = now

        let target: Double = demoHeld ? 1 : 0
        let smoothing = dt > 0 ? 1 - exp(-dt / 0.18) : 1
        demoPresence += (target - demoPresence) * smoothing
        if demoPresence < 0.002 { demoPresence = 0 }
        if demoPresence > 0.998 { demoPresence = 1 }

        let sensor = MagnetSupport.sensorPosition
        let dx = demoPoint.x - sensor.x
        let dy = demoPoint.y - sensor.y
        let points = max(1, sqrt(dx * dx + dy * dy))
        let centimeters = Double(points) * 0.019

        var speed = 0.0
        if dt > 0, let previous = demoPreviousDistance {
            speed = (previous - centimeters) / dt
        }
        demoPreviousDistance = centimeters

        let closeness = max(0, min(1, 1 - (centimeters - 2) / 18))

        return MagnetFrame(
            available: true,
            position: demoPoint,
            spread: 9,
            height: CGFloat(max(0.4, 3.0 - centimeters * 0.12)),
            presence: demoPresence,
            pull: closeness * demoPresence,
            toward: CGVector(dx: dx / points, dy: dy / points),
            distance: centimeters,
            approachSpeed: speed,
            tooClose: centimeters < 2,
            calibrating: false,
            isSimulated: true
        )
    }
}
