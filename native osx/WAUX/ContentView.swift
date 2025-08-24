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
    @StateObject private var preferenceService = PreferenceService.shared
    @State private var showingFolderPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedPlaylist: Playlist?
    @State private var playlistTracks: [Track] = []
    @State private var isLoadingPlaylistTracks = false
    @State private var hasAttemptedAutoLoad = false
    @EnvironmentObject private var menuActionState: MenuActionState
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with integrated audio player
            HStack(spacing: 16) {
                
                Spacer()
                
                // Audio player controls (only show when track is loaded)
                if audioService.currentTrack != nil {
                    HStack(spacing: 12) {
                        Button(action: {
                            // TODO: Implement previous track
                        }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                        .disabled(audioService.currentTrack == nil || audioService.isLoading)
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            audioService.togglePlayPause()
                        }) {
                            Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                        }
                        .disabled(audioService.currentTrack == nil || audioService.isLoading)
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            // TODO: Implement next track
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                        .disabled(audioService.currentTrack == nil || audioService.isLoading)
                        .buttonStyle(.plain)
                    }
                    
                    // Track info
                    if let track = audioService.currentTrack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            
                            if !track.artist.isEmpty && track.artist != "Unknown" {
                                Text(track.artist)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 200, alignment: .leading)
                    }
                    
                    // Timeline
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { audioService.duration > 0 ? audioService.currentTime / audioService.duration : 0 },
                                set: { ratio in
                                    audioService.seekToRatio(ratio)
                                }
                            ),
                            in: 0...1
                        )
                        .disabled(audioService.currentTrack == nil || audioService.isLoading)
                        .frame(width: 200)
                        
                        HStack {
                            Text(audioService.formatTime(audioService.currentTime))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            
                            Spacer()
                            
                            Text(audioService.formatTime(audioService.duration))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        .frame(width: 200)
                    }
                    
                    // Volume control
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Slider(value: Binding(
                            get: { Double(audioService.volume) },
                            set: { audioService.setVolume(Float($0)) }
                        ), in: 0...1)
                        .frame(width: 80)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    // Loading indicator
                    if audioService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(0.6)
                    }
                }
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
                            List(playlistService.playlists, id: \.id) { playlist in
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
                                .background(selectedPlaylist?.id == playlist.id ? Color.blue.opacity(0.2) : Color.clear)
                                .onTapGesture {
                                    selectedPlaylist = playlist
                                }
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
        .onChange(of: menuActionState.shouldOpenFolder) { _, shouldOpen in
            if shouldOpen {
                showingFolderPicker = true
                menuActionState.shouldOpenFolder = false
            }
        }
        .onChange(of: menuActionState.shouldImportAudio) { _, shouldImport in
            if shouldImport {
                // TODO: Implement file import
                menuActionState.shouldImportAudio = false
            }
        }
        .onChange(of: menuActionState.shouldClearSavedFolder) { _, shouldClear in
            if shouldClear {
                preferenceService.clearLastFolder()
                menuActionState.shouldClearSavedFolder = false
            }
        }
        .onChange(of: collectionService.tracks) { _, newTracks in
            print("[ContentView] tracks changed, count=\(newTracks.count)")
            // Keep playlistTracks in sync when tags/ratings change in the library
            if let playlist = selectedPlaylist {
                print("[ContentView] reloading playlist tracks for \(playlist.name)")
                Task { await loadPlaylistTracks(playlist) }
            }
        }
        .onAppear {
            if !hasAttemptedAutoLoad {
                hasAttemptedAutoLoad = true
                Task {
                    await attemptLoadLastFolder()
                }
            }
        }
    }
    
    private func attemptLoadLastFolder() async {
        // Try to load the last folder using the bookmark first (for security-scoped access)
        if let bookmarkURL = preferenceService.getLastFolderBookmarkURL() {
            print("Attempting to load last folder using bookmark: \(bookmarkURL.path)")
            await openFolder(url: bookmarkURL)
            return
        }
        
        // Fallback to path-based loading
        if let pathURL = preferenceService.getLastFolderURL() {
            print("Attempting to load last folder using path: \(pathURL.path)")
            await openFolder(url: pathURL)
            return
        }
        
        print("No last folder to load or failed to load last folder")
    }
    
    private func loadPlaylistTracks(_ playlist: Playlist) async {
        await MainActor.run {
            isLoadingPlaylistTracks = true
        }
        
        do {
            print("Loading playlist: \(playlist.name)")
            print("Playlist has \(playlist.trackPaths.count) track paths")
            print("Collection has \(collectionService.tracks.count) tracks")
            
            // Debug: Print first few playlist track paths
            if !playlist.trackPaths.isEmpty {
                print("First 3 playlist track paths:")
                for (index, path) in playlist.trackPaths.prefix(3).enumerated() {
                    print("  \(index): \(path)")
                }
            }
            
            // Debug: Print first few collection track paths
            if !collectionService.tracks.isEmpty {
                print("First 3 collection track paths:")
                for (index, track) in collectionService.tracks.prefix(3).enumerated() {
                    print("  \(index): \(track.path)")
                }
            }
            
            // Get tracks that match the playlist track paths
            // Try exact match first
            var tracks = collectionService.tracks.filter { track in
                playlist.trackPaths.contains(track.path)
            }
            
            print("Found \(tracks.count) exact matching tracks")
            
            // If no exact matches, try filename matching
            if tracks.isEmpty {
                tracks = collectionService.tracks.filter { track in
                    playlist.trackPaths.contains { playlistPath in
                        let trackFilename = URL(fileURLWithPath: track.path).lastPathComponent
                        let playlistFilename = URL(fileURLWithPath: playlistPath).lastPathComponent
                        return trackFilename == playlistFilename
                    }
                }
                print("Found \(tracks.count) filename matching tracks")
            }
            
            // If still no matches, try normalized path matching
            if tracks.isEmpty {
                tracks = collectionService.tracks.filter { track in
                    playlist.trackPaths.contains { playlistPath in
                        let normalizedTrackPath = URL(fileURLWithPath: track.path).standardized.path
                        let normalizedPlaylistPath = URL(fileURLWithPath: playlistPath).standardized.path
                        return normalizedTrackPath == normalizedPlaylistPath
                    }
                }
                print("Found \(tracks.count) normalized matching tracks")
            }
            
            // Sort tracks according to playlist order
            let sortedTracks = playlist.trackPaths.compactMap { trackPath in
                tracks.first { track in
                    track.path == trackPath || 
                    URL(fileURLWithPath: track.path).standardized.path == URL(fileURLWithPath: trackPath).standardized.path ||
                    URL(fileURLWithPath: track.path).lastPathComponent == URL(fileURLWithPath: trackPath).lastPathComponent
                }
            }
            
            print("Final sorted tracks count: \(sortedTracks.count)")
            
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
            
            // Save the folder preference for next time
            preferenceService.saveLastFolder(url)
            
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
