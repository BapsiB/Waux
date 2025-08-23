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
    @State private var showingFolderPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedPlaylist: Playlist?
    @State private var playlistTracks: [Track] = []
    @State private var isLoadingPlaylistTracks = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WAUX Audio Player")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Open Folder") {
                    showingFolderPicker = true
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
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Sidebar
                    VStack {
                        Text("Library")
                            .font(.headline)
                            .padding()
                        
                        if playlistService.isLoading {
                            ProgressView("Loading playlists...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if playlistService.playlists.isEmpty {
                            VStack {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 32))
                                    .foregroundColor(.gray)
                                Text("No playlists")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(playlistService.playlists, id: \.id, selection: $selectedPlaylist) { playlist in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    
                                    HStack {
                                        Text("\(playlist.trackPaths.count) tracks")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        if playlist.duration > 0 {
                                            Text("•")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            Text(playlist.formattedDuration)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listStyle(SidebarListStyle())
                        }
                    }
                    .frame(width: 200)
                    .background(Color(.controlBackgroundColor))
                    
                    // Main area
                    VStack {
                        if collectionService.isLoading {
                            ProgressView("Loading collection...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let selectedPlaylist = selectedPlaylist {
                            // Show playlist tracks
                            if isLoadingPlaylistTracks {
                                ProgressView("Loading playlist tracks...")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if !playlistTracks.isEmpty {
                                VStack {
                                    HStack {
                                        Text("Playlist: \(selectedPlaylist.name)")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                        
                                        Spacer()
                                        
                                        Text("\(playlistTracks.count) tracks")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal)
                                    .padding(.top)
                                    
                                    TrackListView(tracks: playlistTracks, collectionService: collectionService, audioService: audioService)
                                }
                            } else {
                                VStack(spacing: 20) {
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 64))
                                        .foregroundColor(.blue)
                                    
                                    Text("Empty Playlist")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                    
                                    Text("This playlist contains no tracks")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else if !collectionService.tracks.isEmpty {
                            // Show all tracks when no playlist is selected
                            VStack {
                                HStack {
                                    Text("All Tracks")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    Spacer()
                                    
                                    Text("\(collectionService.tracks.count) tracks")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.top)
                                
                                TrackListView(tracks: collectionService.tracks, collectionService: collectionService, audioService: audioService)
                            }
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
                                
                                Button("Open Folder") {
                                    showingFolderPicker = true
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Audio player at bottom
                if audioService.currentTrack != nil {
                    AudioPlayerView(audioService: audioService)
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .border(Color(.separatorColor), width: 1)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let folderURL = urls.first {
                    Task {
                        await openFolder(url: folderURL)
                    }
                }
            case .failure(let error):
                errorMessage = "Folder selection failed: \(error.localizedDescription)"
                showingError = true
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: selectedPlaylist) { _, newPlaylist in
            if let playlist = newPlaylist {
                Task {
                    await loadPlaylistTracks(playlist)
                }
            } else {
                playlistTracks = []
            }
        }
    }
    
    private func loadPlaylistTracks(_ playlist: Playlist) async {
        await MainActor.run {
            isLoadingPlaylistTracks = true
        }
        
        do {
            // Get tracks that match the playlist track paths
            let tracks = collectionService.tracks.filter { track in
                playlist.trackPaths.contains(track.path)
            }
            
            // Sort tracks according to playlist order
            let sortedTracks = playlist.trackPaths.compactMap { trackPath in
                tracks.first { $0.path == trackPath }
            }
            
            await MainActor.run {
                playlistTracks = sortedTracks
                isLoadingPlaylistTracks = false
            }
        } catch {
            await MainActor.run {
                playlistTracks = []
                isLoadingPlaylistTracks = false
                errorMessage = "Failed to load playlist tracks: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func openFolder(url: URL) async {
        do {
            print("Selected folder URL: \(url)")
            print("Folder path: \(url.path)")
            
            // Start accessing the security-scoped resource (folder-wide)
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "DatabaseError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot access the selected folder"])
            }
            
            // Store the folder URL so the service maintains access for sidecar files
            collectionService.setSecurityScopedURL(url)
            
            // Locate a .db file inside the folder (search recursively, skip hidden files)
            let fileManager = FileManager.default
            let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            var dbURL: URL?
            while let item = enumerator?.nextObject() as? URL {
                if item.pathExtension.lowercased() == "db" {
                    dbURL = item
                    break
                }
            }
            guard let dbURL else {
                url.stopAccessingSecurityScopedResource()
                throw NSError(domain: "DatabaseError", code: 4, userInfo: [NSLocalizedDescriptionKey: "No .db file found in the selected folder."])
            }
            
            print("Found database at: \(dbURL.path)")
            
            // Test database connection first (read-only)
            let canConnect = collectionService.testDatabaseConnection(path: dbURL.path)
            if !canConnect {
                url.stopAccessingSecurityScopedResource()
                throw NSError(domain: "DatabaseError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot connect to database file"])
            }
            
            let definition = CollectionDefinition(
                id: UUID().uuidString,
                name: dbURL.lastPathComponent,
                type: .local,
                dbPath: dbURL.path
            )
            
            try await collectionService.openCollection(definition)
            
            // Set up playlist service with the same database and collection
            playlistService.setDatabase(collectionService.getDatabase(), collectionDefinition: definition)
            
            // Load tracks then playlists sequentially to avoid concurrent access to the same SQLite connection
            try await collectionService.loadAllTracks()
            try await playlistService.loadPlaylists()
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to open folder: \(error.localizedDescription)"
                showingError = true
            }
            print("Error opening folder: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
