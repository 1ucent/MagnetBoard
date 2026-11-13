//
//  ContentView.swift
//  MagnetBoard
//
//  The board. One TimelineView samples the magnet model per display refresh,
//  then hands the same plain `MagnetFrame` to the controls, the field overlay
//  and the HUD, so everything agrees on where the magnet is.
//

import SwiftUI

@MainActor
struct ContentView: View {

    @EnvironmentObject private var engine: MagnetEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("gather") private var gatherEnabled = true
    @AppStorage("particles") private var particlesEnabled = true

    @State private var isPowerOn = true
    @State private var brightness: Double = 0.64
    @State private var mode: BoardMode = .calm
    @State private var level = 3
    @State private var showingSettings = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let frame = engine.snapshot(now: now)

            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                let board = CGRect(origin: origin, size: proxy.size)
                let gather = EdgeGather.make(frame: frame, in: board)

                ZStack {
                    background(frame: frame)

                    VStack(spacing: 12) {
                        header(frame: frame, gather: gather)
                            .padding(.horizontal, 18)
                        presenceMeter(frame: frame)
                            .padding(.horizontal, 18)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 14) {
                                LazyVGrid(columns: columns, spacing: 14) {
                                    MagneticTile(frame: frame) {
                                        PowerTile(isOn: $isPowerOn)
                                    }

                                    MagneticTile(frame: frame) {
                                        LevelTile(level: $level)
                                    }

                                    MagneticTile(frame: frame) {
                                        BrightnessTile(value: $brightness)
                                    }
                                    .gridCellColumns(2)

                                    MagneticTile(frame: frame) {
                                        ModeTile(mode: $mode)
                                    }
                                    .gridCellColumns(2)
                                }

                                MagneticTile(frame: frame, travel: 14) {
                                    TapCounterCard(
                                        taps: engine.tapCount,
                                        presence: frame.presence
                                    )
                                }

                                HUDView(frame: frame, lastEvent: engine.lastEvent)
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 28)
                        }
                    }
                    .padding(.top, 4)
                    .modifier(EdgeGatherEffect(gather: gather, board: board, enabled: gatherEnabled))

                    if particlesEnabled {
                        GeometryReader { canvas in
                            ParticleField(
                                frame: frame,
                                origin: canvas.frame(in: .global).origin,
                                now: now,
                                reduceMotion: reduceMotion
                            )
                        }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    }

                    FieldOverlay(
                        frame: frame,
                        origin: origin,
                        now: now,
                        reduceMotion: reduceMotion
                    )

                    RippleLayer(ripples: engine.ripples, origin: origin)

                    if engine.isDemoMode {
                        DemoPuck(origin: origin)
                    }

                    ZStack {
                        if let flash = engine.flash {
                            EventFlashOverlay(flash: flash)
                                .id(flash.id)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: engine.flash?.id)
                    .allowsHitTesting(false)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .background(Theme.inkDeep.ignoresSafeArea())
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
                .environmentObject(engine)
        }
    }

    // MARK: Background

    private func background(frame: MagnetFrame) -> some View {
        ZStack {
            Theme.inkDeep

            RadialGradient(
                colors: [Theme.accent.opacity(0.10 + 0.16 * frame.pull), .clear],
                center: UnitPoint(x: 0.18, y: 0.10),
                startRadius: 8,
                endRadius: 520
            )

            RadialGradient(
                colors: [Theme.accentAlt.opacity(0.10 + 0.10 * frame.pull), .clear],
                center: UnitPoint(x: 0.92, y: 0.82),
                startRadius: 8,
                endRadius: 480
            )

            LinearGradient(
                colors: [Theme.ink.opacity(0.0), Theme.inkDeep.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private func header(frame: MagnetFrame, gather: EdgeGather?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MAGNET BOARD")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Theme.text)

                Text(statusLine(frame: frame, gather: gather))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            StatusPill(frame: frame, isDemo: engine.isDemoMode)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func statusLine(frame: MagnetFrame, gather: EdgeGather?) -> String {
        if engine.isDemoMode { return "DEMO · DRAG THE ORANGE PUCK" }
        if !MagnetSupport.isLinked { return "ADD THE MAGNETKIT PACKAGE" }
        if !MagnetSupport.isModelLoaded { return "ADD MAGNET.MFXL TO THE APP TARGET" }
        if !frame.available { return "WAITING FOR THE MAGNETOMETER" }
        if frame.calibrating { return "TAKING A NEW ZERO · MAGNETS AWAY" }
        if frame.tooClose { return "MAGNET TOO CLOSE · HOLD 2 CM AWAY" }
        if let gather, gather.strength > 0.3 {
            return "GATHERING TO THE \(gather.edge.label) EDGE"
        }
        if frame.presence > 0.05 { return "MAGNET DETECTED · MOVE IT AROUND" }
        return "HOLD A MAGNET NEAR THE TOP-LEFT OF THE PHONE"
    }

    private func presenceMeter(frame: MagnetFrame) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accentAlt, Theme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, proxy.size.width * CGFloat(frame.presence)))
                    .opacity(0.9)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Status pill

struct StatusPill: View {

    let frame: MagnetFrame
    let isDemo: Bool

    var body: some View {
        let status = current
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.text)
                .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(status.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Capsule().fill(status.color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(status.color.opacity(0.28), lineWidth: 1))
    }

    private var current: (text: String, color: Color) {
        if isDemo {
            return frame.presence > 0.3 ? ("DEMO · LOCKED", Theme.accent) : ("DEMO", Theme.textDim)
        }
        if !MagnetSupport.isLinked { return ("KIT MISSING", Theme.warm) }
        if !MagnetSupport.isModelLoaded { return ("NO MODEL FILE", Theme.warm) }
        if frame.calibrating { return ("CALIBRATING", Theme.warm) }
        if !frame.available { return ("NO SENSOR", Theme.textDim) }
        if frame.tooClose { return ("TOO CLOSE", Theme.warm) }
        if frame.presence > 0.55 { return ("MAGNET LOCKED", Theme.mint) }
        if frame.presence > 0.05 { return ("TRACKING", Theme.accent) }
        return ("SEARCHING", Theme.textDim)
    }
}

// MARK: - Demo puck

/// The stand-in magnet for the Simulator: drag it and the board reacts, tap it
/// for an air tap. Values are synthesised by `MagnetEngine.demoSnapshot`.
@MainActor
struct DemoPuck: View {

    @EnvironmentObject private var engine: MagnetEngine
    let origin: CGPoint

    @State var dragging = false

    var body: some View {
        let point = CGPoint(
            x: engine.demoPoint.x - origin.x,
            y: engine.demoPoint.y - origin.y
        )

        ZStack {
            Circle()
                .fill(Theme.warm.opacity(0.14))
                .frame(width: 92, height: 92)

            Circle()
                .strokeBorder(
                    Theme.warm.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                )
                .frame(width: 64, height: 64)

            Circle()
                .fill(Theme.warm)
                .frame(width: 26, height: 26)
                .shadow(color: Theme.warm.opacity(0.85), radius: 16)

            Image(systemName: "hand.draw.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.ink)
        }
        .position(point)
        .gesture(dragGesture)
        .accessibilityLabel("Demo magnet")
        .accessibilityHint("Drag to move the magnet, tap for an air tap")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    engine.demoTouchBegan(at: value.location)
                }
                engine.demoTouchMoved(to: value.location)
            }
            .onEnded { value in
                dragging = false
                let travel = hypot(value.translation.width, value.translation.height)
                engine.demoTouchEnded()
                if travel < 10 {
                    engine.demoAirTap(at: value.location)
                }
            }
    }
}

// MARK: - Event banner

struct EventFlashOverlay: View {

    let flash: MagnetFlash
    @State var shown = false

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: flash.symbol)
                    .font(.system(size: 13, weight: .bold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(flash.label)
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                    Text(flash.detail)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.ink.opacity(0.92)))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
            .shadow(color: Theme.accent.opacity(0.35), radius: 18)
            .scaleEffect(shown ? 1 : 0.9)
            .opacity(shown ? 1 : 0)

            Spacer()
        }
        .padding(.top, 116)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                shown = true
            }
        }
    }
}

#Preview("Board") {
    ContentView()
        .environmentObject(MagnetEngine())
}
