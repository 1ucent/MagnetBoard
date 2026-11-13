//
//  BoardControls.swift
//  MagnetBoard
//
//  The little UI kit that lives on the board: a power switch, a brightness
//  slider, a stepper, segmented "field mode" chips and the air-tap counter.
//  Each one is a normal, usable control — the magnet only moves them.
//

import SwiftUI

enum BoardMode: String, CaseIterable, Identifiable {
    case calm = "CALM"
    case focus = "FOCUS"
    case flux = "FLUX"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .calm: return "moon.stars.fill"
        case .focus: return "scope"
        case .flux: return "waveform.path.ecg"
        }
    }

    var accent: Color {
        switch self {
        case .calm: return Theme.accent
        case .focus: return Theme.mint
        case .flux: return Theme.accentAlt
        }
    }
}

// MARK: - Buttons

struct TileButtonStyle: ButtonStyle {
    var active: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tileSurface(active: active)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Power

struct PowerTile: View {

    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                isOn.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "power")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isOn ? Theme.mint : Theme.textDim)
                    Spacer()
                    Capsule()
                        .fill(isOn ? Theme.mint : Color.white.opacity(0.18))
                        .frame(width: 30, height: 6)
                }

                Text(isOn ? "ON" : "OFF")
                    .font(.boardNumber(26))
                    .foregroundStyle(Theme.text)

                Text("board power")
                    .tileLabel()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(TileButtonStyle(active: isOn))
    }
}

// MARK: - Level stepper

struct LevelTile: View {

    @Binding var level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LEVEL")
                .tileLabel()

            HStack(spacing: 6) {
                stepButton("minus") {
                    withAnimation(.snappy) { level = max(0, level - 1) }
                }

                Text("\(level)")
                    .font(.boardNumber(30))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())

                stepButton("plus") {
                    withAnimation(.snappy) { level = min(9, level + 1) }
                }
            }
        }
        .tileSurface()
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Brightness

struct BrightnessTile: View {

    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BRIGHTNESS")
                    .tileLabel()
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent.opacity(0.55), Theme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, width * CGFloat(value)))

                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: Theme.accent.opacity(0.9), radius: 8)
                        .offset(x: max(0, width * CGFloat(value) - 9))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let fraction = drag.location.x / width
                            value = Double(min(1, max(0, fraction)))
                        }
                )
            }
            .frame(height: 22)
        }
        .tileSurface()
    }
}

// MARK: - Field mode

struct ModeTile: View {

    @Binding var mode: BoardMode
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FIELD MODE")
                .tileLabel()

            HStack(spacing: 8) {
                ForEach(BoardMode.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            mode = item
                        }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(mode == item ? Theme.ink : Theme.text.opacity(0.65))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background {
                                if mode == item {
                                    Capsule()
                                        .fill(item.accent)
                                        .matchedGeometryEffect(id: "mode", in: selection)
                                } else {
                                    Capsule()
                                        .fill(Color.white.opacity(0.06))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .tileSurface()
    }
}

// MARK: - Air-tap counter

struct TapCounterCard: View {

    let taps: Int
    let presence: Double

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.10 + 0.28 * presence))
                Circle()
                    .strokeBorder(Theme.stroke, lineWidth: 1)
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(taps)")
                    .font(.boardNumber(32))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Text("air taps — dip the magnet toward the glass")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textDim)
            }

            Spacer(minLength: 0)
        }
        .tileSurface()
    }
}
