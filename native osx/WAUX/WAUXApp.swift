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
    @Published var shouldShowAbout = false
    @Published var shouldGoToCurrentTrack = false
    @Published var shouldOpenCueFileHelper = false
}

@main
struct WAUXApp: App {
    @StateObject private var menuActionState = MenuActionState()
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
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
                
                Button("Go to Current Track") {
                    menuActionState.shouldGoToCurrentTrack = true
                }
                .keyboardShortcut("l", modifiers: .command)
                
                Divider()
                
                Button("Open Cue File Helper") {
                    menuActionState.shouldOpenCueFileHelper = true
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

            }
            
            CommandGroup(replacing: .appInfo) {
                Button("About WAUX") {
                    menuActionState.shouldShowAbout = true
                }
            }
        }
        
        // Separate window for Cue File Helper
        WindowGroup(id: "cue-file-helper") {
            CueFileHelperView()
        }
        .defaultSize(width: 900, height: 600)
    }
}

// Wrapper view to handle window opening
struct MainWindowView: View {
    @EnvironmentObject var menuActionState: MenuActionState
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        ContentView()
            .onChange(of: menuActionState.shouldOpenCueFileHelper) { shouldOpen in
                if shouldOpen {
                    openWindow(id: "cue-file-helper")
                    menuActionState.shouldOpenCueFileHelper = false
                }
            }
    }
}
