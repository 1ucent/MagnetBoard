//
//  MagnetBoardApp.swift
//  MagnetBoard
//
//  Application entry point. Owns the single MagnetEngine instance (the only
//  object that talks to MagnetKit) and injects it into the view hierarchy.
//

import SwiftUI
import UIKit

@main
@MainActor
struct MagnetBoardApp: App {

    @StateObject private var engine = MagnetEngine()

    init() {
        // Keep the sheet's navigation bar as dark as the board.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.012, green: 0.020, blue: 0.035, alpha: 1.0)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
