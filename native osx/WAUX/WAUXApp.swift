//
//  WAUXApp.swift
//  WAUX
//
//  Created by Baptiste Bohelay on 16/08/2025.
//

import SwiftUI

// Shared state for menu actions
class MenuActionState: ObservableObject {
    @Published var shouldOpenFolder = false
    @Published var shouldImportAudio = false
    @Published var shouldClearSavedFolder = false
    @Published var shouldRegenerateWaveforms = false
}

@main
struct WAUXApp: App {
    @StateObject private var menuActionState = MenuActionState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(menuActionState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Folder...") {
                    menuActionState.shouldOpenFolder = true
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("Import Audio...") {
                    menuActionState.shouldImportAudio = true
                }
                .keyboardShortcut("i", modifiers: .command)
                
                Divider()
                
                Button("Clear Saved Folder") {
                    menuActionState.shouldClearSavedFolder = true
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Regenerate Waveforms (Time-based)") {
                    menuActionState.shouldRegenerateWaveforms = true
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
    }
}
