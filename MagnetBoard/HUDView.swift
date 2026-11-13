//
//  HUDView.swift
//  MagnetBoard
//
//  The honest part: what the on-device model is actually reporting. Presence,
//  distance, height above the glass, the locator's spread, pull, and a warning
//  when the magnet is close enough to magnetise the phone.
//

import SwiftUI

struct HUDView: View {

    let frame: MagnetFrame
    let lastEvent: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                readout("PRESENCE", percent(frame.presence), "%")
                readout("DISTANCE", centimeters(frame.distance), "cm")
                readout("HEIGHT", centimeters(frame.height), "cm")
                readout("SPREAD", points(frame.spread), "pt")
            }

            HStack(spacing: 8) {
                Text("PULL")
                    .tileLabel()
                    .frame(width: 32, alignment: .leading)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.accentAlt, Theme.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(3, proxy.size.width * CGFloat(frame.pull)))
                    }
                }
                .frame(height: 4)

                Text(percent(frame.pull) + "%")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.text.opacity(0.8))
                    .frame(width: 34, alignment: .trailing)
            }

            HStack(spacing: 6) {
                Text("EVENT")
                    .tileLabel()
                Text(lastEvent)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)

                Spacer(minLength: 6)

                if frame.tooClose {
                    badge("TOO CLOSE", color: Theme.warm)
                } else if !MagnetSupport.isLinked || !MagnetSupport.isModelLoaded {
                    badge("MODEL MISSING", color: Theme.warm)
                } else if !frame.available {
                    badge("NO SENSOR", color: Theme.textDim)
                } else if frame.isSimulated {
                    badge("SIMULATED", color: Theme.accentAlt)
                } else if frame.presence > 0.5 {
                    badge("LOCKED", color: Theme.mint)
                }
            }
        }
        .tileSurface(padding: 14)
    }

    // MARK: Pieces

    private func readout(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.boardNumber(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(unit)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textDim)
            }
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f", max(0, min(1, value)) * 100)
    }

    private func centimeters(_ value: Double) -> String {
        value > 0.05 ? String(format: "%.1f", value) : "—"
    }

    private func points(_ value: CGFloat) -> String {
        value > 0.5 ? String(format: "%.0f", Double(value)) : "—"
    }
}
