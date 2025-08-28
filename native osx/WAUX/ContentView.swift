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
            // Main content
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Sidebar
                    PlaylistSidebar(
                        playlistService: playlistService,
                        selectedPlaylist: $selectedPlaylist
                    )
                    
                    // Main area
                    MainContentArea(
                        collectionService: collectionService,
                        playlistService: playlistService,
                        audioService: audioService,
                        playlistTracks: playlistTracks,
                        isLoadingPlaylistTracks: isLoadingPlaylistTracks,
                        showingFolderPicker: $showingFolderPicker,
                        selectedPlaylist: $selectedPlaylist
                    )
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            print("[UI] File importer result received")
            switch result {
            case .success(let urls):
                if let folderURL = urls.first {
                    print("[UI] Folder selected: \(folderURL.path)")
                    Task {
                        await openFolder(url: folderURL)
                    }
                }
            case .failure(let error):
                print("[UI] Folder selection failed: \(error)")
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
            
            // Note: We don't stop accessing the security-scoped resource here
            // The CollectionService will manage the security access for individual operations
            
            print("[OpenFolder] Checking for existing DB at root...")
            // Check for a .db file at the root of the selected folder (non-recursive)
            let fileManager = FileManager.default
            let rootContents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            print("[OpenFolder] Root contains \(rootContents.count) items")
            if !rootContents.isEmpty {
                print("[OpenFolder] First 5 items: \(rootContents.prefix(5).map{ $0.lastPathComponent })")
            }
            let preferredDBURL = url.appendingPathComponent("waux.db")
            let dbAtRoot = rootContents.first { $0.pathExtension.lowercased() == "db" }
            var dbURL: URL
            if FileManager.default.fileExists(atPath: preferredDBURL.path) {
                dbURL = preferredDBURL
                print("[OpenFolder] Found WAUX database at root: \(dbURL.path)")
            } else if let existing = dbAtRoot {
                dbURL = existing
                print("[OpenFolder] Found database at root: \(dbURL.path)")
            } else {
                // No DB at root: create one at the folder root
                dbURL = preferredDBURL
                print("[OpenFolder] No database found at root. Creating new database at: \(dbURL.path)")
                try collectionService.createNewLocalDatabase(at: dbURL.path)
                print("[OpenFolder] Database created at: \(dbURL.path)")
            }
            
            // Test database connection first (read-only)
            print("[OpenFolder] Testing connection to DB: \(dbURL.path)")
            let canConnect = collectionService.testDatabaseConnection(path: dbURL.path)
            if !canConnect {
                throw NSError(domain: "DatabaseError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot connect to database file"])
            }
            
            let definition = CollectionDefinition(
                id: UUID().uuidString,
                name: dbURL.lastPathComponent,
                type: .local,
                dbPath: dbURL.path
            )
            
            print("[OpenFolder] Opening collection with DB path: \(definition.dbPath)")
            try await collectionService.openCollection(definition)
            print("[OpenFolder] Collection opened")
            
            // Set up playlist service with the same database and collection
            playlistService.setDatabase(collectionService.getDatabase(), collectionDefinition: definition)
            
            // If we just created a DB, import all audio files under the selected folder
            if dbAtRoot == nil {
                print("[OpenFolder] Importing audio files under root: \(url.path)")
                try await collectionService.importAllAudioFilesUnderRoot(rootFolderPath: url.path)
                print("[OpenFolder] Import completed")
            }

            // Load tracks then playlists sequentially to avoid concurrent access to the same SQLite connection
            print("[OpenFolder] Loading tracks...")
            try await collectionService.loadAllTracks()
            print("[OpenFolder] Tracks loaded: \(collectionService.tracks.count)")
            try await playlistService.loadPlaylists()
            print("[OpenFolder] Playlists loaded: \(playlistService.playlists.count)")
            
            // Trigger waveform processing for newly added tracks (if any)
            if !collectionService.pendingWaveformTrackIds.isEmpty {
                print("[OpenFolder] Queuing waveform processing for \(collectionService.pendingWaveformTrackIds.count) tracks")
                let waveformService = WaveformProcessingService(collectionService: collectionService)
                let idSet = Set(collectionService.pendingWaveformTrackIds)
                for track in collectionService.tracks where track.id.map({ idSet.contains($0) }) == true {
                    waveformService.analyzeIfMissing(track)
                }
                collectionService.pendingWaveformTrackIds.removeAll()
                print("[OpenFolder] Waveform queueing done")
            }

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
