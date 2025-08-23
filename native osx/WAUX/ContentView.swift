//
//  ContentView.swift
//  WAUX
//
//  Created by Baptiste Bohelay on 16/08/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioService = AudioService()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WAUX Audio Player")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Import Audio") {
                    // TODO: Implement file import
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            // Main content
            HStack(spacing: 0) {
                // Sidebar (placeholder)
                VStack {
                    Text("Library")
                        .font(.headline)
                        .padding()
                    
                    List {
                        Text("All Tracks")
                        Text("Playlists")
                        Text("Recently Added")
                        Text("Favorites")
                    }
                    .listStyle(SidebarListStyle())
                }
                .frame(width: 200)
                .background(Color(.controlBackgroundColor))
                
                // Main area
                VStack {
                    if audioService.currentTrack != nil {
                        AudioPlayerView(audioService: audioService)
                            .padding()
                    } else {
                        // Welcome screen
                        VStack(spacing: 20) {
                            Image(systemName: "music.note")
                                .font(.system(size: 64))
                                .foregroundColor(.blue)
                            
                            Text("Welcome to WAUX")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("Your audio collection manager")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            
                            Text("Import your audio files to get started")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Button("Import Audio Files") {
                                // TODO: Implement file import
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
