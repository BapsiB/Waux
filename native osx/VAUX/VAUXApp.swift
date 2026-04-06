//
//  VAUXApp.swift
//  VAUX
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
    /// When set, ContentView restores from this URL (File → Restore from Backup submenu).
    @Published var pendingRestoreBackupURL: URL?
}

@main
struct VAUXApp: App {
    @StateObject private var menuActionState = MenuActionState()
    @StateObject private var restoreBackupMenuState = RestoreBackupMenuState()
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(menuActionState)
                .environmentObject(restoreBackupMenuState)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            commandGroups
        }
        
        if #available(macOS 13.0, *) {
            WindowGroup(id: "cue-file-helper") {
                CueFileHelperView()
            }
            .defaultSize(width: 900, height: 600)
        }
    }
    
    @CommandsBuilder
    private var commandGroups: some Commands {
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
        
        CommandGroup(after: .importExport) {
            Menu("Restore from Backup") {
                if restoreBackupMenuState.entries.isEmpty {
                    Button("No backups in Application Support") {}
                        .disabled(true)
                } else {
                    ForEach(restoreBackupMenuState.entries) { entry in
                        Button(entry.menuTitle) {
                            menuActionState.pendingRestoreBackupURL = entry.url
                        }
                    }
                }
            }
        }
        
        CommandGroup(replacing: .appInfo) {
            Button("About VAUX") {
                menuActionState.shouldShowAbout = true
            }
        }
    }
}

// Wrapper view to handle window opening
struct MainWindowView: View {
    @EnvironmentObject var menuActionState: MenuActionState
    
    var body: some View {
        if #available(macOS 13.0, *) {
            MainWindowView13()
                .environmentObject(menuActionState)
        } else {
            MainWindowView12()
                .environmentObject(menuActionState)
        }
    }
}

@available(macOS 13.0, *)
struct MainWindowView13: View {
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

struct MainWindowView12: View {
    @EnvironmentObject var menuActionState: MenuActionState
    
    var body: some View {
        ContentView()
            .onChange(of: menuActionState.shouldOpenCueFileHelper) { shouldOpen in
                if shouldOpen {
                    // On macOS 12.4, we can't open separate windows programmatically with WindowGroup(id:)
                    // The Cue File Helper menu item will do nothing on older macOS versions
                    print("⚠️ Cue File Helper requires macOS 13.0 or later")
                    menuActionState.shouldOpenCueFileHelper = false
                }
            }
    }
}
