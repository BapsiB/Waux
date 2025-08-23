//
//  ContentView.swift
//  WAUX
//
//  Created by Baptiste Bohelay on 16/08/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var audioService = AudioService()
    @StateObject private var collectionService = CollectionService()
    @StateObject private var playlistService = PlaylistService()
    @State private var showingDatabasePicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedTab = "tracks"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WAUX Audio Player")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Open Database") {
                    showingDatabasePicker = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Import Audio") {
                    // TODO: Implement file import
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            // Main content
            HStack(spacing: 0) {
                // Sidebar
                VStack {
                    Text("Library")
                        .font(.headline)
                        .padding()
                    
                    List {
                        Button("Tracks") {
                            selectedTab = "tracks"
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(selectedTab == "tracks" ? .blue : .primary)
                        
                        Button("Playlists") {
                            selectedTab = "playlists"
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(selectedTab == "playlists" ? .blue : .primary)
                        
                        Text("Recently Added")
                        Text("Favorites")
                    }
                    .listStyle(SidebarListStyle())
                }
                .frame(width: 200)
                .background(Color(.controlBackgroundColor))
                
                // Main area
                VStack {
                    if collectionService.isLoading {
                        ProgressView("Loading collection...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if selectedTab == "tracks" && !collectionService.tracks.isEmpty {
                        // Show tracks
                        TrackListView(tracks: collectionService.tracks)
                    } else if selectedTab == "playlists" {
                        // Show playlists
                        PlaylistView(playlistService: playlistService)
                    } else if audioService.currentTrack != nil {
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
                            
                            Text("Open a database to view your collection")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Button("Open Database") {
                                showingDatabasePicker = true
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
        .fileImporter(
            isPresented: $showingDatabasePicker,
            allowedContentTypes: [UTType(filenameExtension: "db")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await openDatabase(url: url)
                    }
                }
            case .failure(let error):
                errorMessage = "File selection failed: \(error.localizedDescription)"
                showingError = true
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func openDatabase(url: URL) async {
        do {
            print("Selected database URL: \(url)")
            print("Database path: \(url.path)")
            
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "DatabaseError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot access the selected file"])
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            // Test database connection first
            let canConnect = collectionService.testDatabaseConnection(path: url.path)
            if !canConnect {
                throw NSError(domain: "DatabaseError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot connect to database file"])
            }
            
            let definition = CollectionDefinition(
                id: UUID().uuidString,
                name: url.lastPathComponent,
                type: .local,
                dbPath: url.path
            )
            
            try await collectionService.openCollection(definition)
            
            // Set up playlist service with the same database and collection
            playlistService.setDatabase(collectionService.getDatabase(), collectionDefinition: definition)
            
            // Load both tracks and playlists
            async let tracksTask = collectionService.loadAllTracks()
            async let playlistsTask = playlistService.loadPlaylists()
            
            try await (tracksTask, playlistsTask)
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to open database: \(error.localizedDescription)"
                showingError = true
            }
            print("Error opening database: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
