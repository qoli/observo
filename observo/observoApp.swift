//
//  observoApp.swift
//  observo
//
//  Created by 黃佁媛 on 2/3/26.
//

import SwiftUI

@main
struct observoApp: App {
    var body: some Scene {
        #if os(macOS)
            WindowGroup {
                ContentView()
            }
            .commands {
                TerminalCommands()
            }

            Settings {
                AppSettingsView()
            }
        #else
            WindowGroup {
                ContentView()
            }
        #endif
    }
}
