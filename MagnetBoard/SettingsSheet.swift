//
//  SettingsSheet.swift
//  MagnetBoard
//
//  Demo mode, magnet orientation, calibration, and where to put the model file.
//

import SwiftUI

@MainActor
struct SettingsSheet: View {

    @EnvironmentObject private var engine: MagnetEngine
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    demoCard
                    faceCard
                    calibrationCard
                    modelCard
                    footer
                }
                .padding(20)
            }
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle("Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Cards

    private var demoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $engine.isDemoMode) {
                Text("Demo magnet")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .tint(Theme.accent)

            Text("Drag the orange puck and the board reacts without a real magnet. The Simulator has no magnetometer, so this is the way to try the app there.")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tileSurface()
    }

    private var faceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $engine.northFaceUp) {
                Text("North pole faces the screen")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .tint(Theme.accent)

            Text("Used to resolve which side of the magnet you are holding. Flip it if the puck mirrors your hand.")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tileSurface()
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CALIBRATION")
                .tileLabel()

            Text("Keep magnets away, then re-zero the phone's own field. MagSafe accessories, steel tables and laptops all shift it.")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                engine.calibrate()
            } label: {
                Label("Recalibrate", systemImage: "scope")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.accent.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .tileSurface()
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: MagnetSupport.isLinked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(MagnetSupport.isLinked ? Theme.mint : Theme.warm)
                Text(MagnetSupport.isLinked ? "MagnetKit linked" : "MagnetKit not linked")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }

            Text("Add the package `https://github.com/Jakubantalik/Libraries.dev` (product `MagnetKit`), then drag `Magnet.mfxl` from libraries.dev/magnetic into the MagnetBoard target. The model is 2 MB and is not part of the package: its license allows development and non-commercial apps; shipping commercially needs a Libraries.dev plan.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tileSurface()
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Magnet Board")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text.opacity(0.7))
            Text("UI reacts to a real magnet through Magnetic UI (MagnetKit) by Libraries.dev · code MIT")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textDim)
        }
        .padding(.top, 4)
    }
}
