//
//  OmiIslandApp.swift
//  OmiIsland
//
//  Omi-Island — a macOS notch companion app.
//

import SwiftUI

@main
struct OmiIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a completely custom window, so no default scene needed
        Settings {
            EmptyView()
        }
    }
}
