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
    @State private var selectedItem: SelectableItem?
    @State private var playlistTracks: [Track] = []
    @State private var isLoadingPlaylistTracks = false
    @State private var hasAttemptedAutoLoad = false
    @State private var isImportingNewFolder = false
    @State private var initialLoadComplete = false
    @State private var hasRunInitialScan = false
    @State private var showFileChangesSheet = false
    @State private var fileChangesData: FileChangesData? = nil
    @State private var previousTracks: [Track] = []
    @EnvironmentObject private var menuActionState: MenuActionState
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Main content
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // Sidebar
                        PlaylistSidebar(
                            playlistService: playlistService,
                            selectedItem: $selectedItem
                        )
                        
                        // Main area
                        MainContentArea(
                            collectionService: collectionService,
                            playlistService: playlistService,
                            audioService: audioService,
                            playlistTracks: playlistTracks,
                            isLoadingPlaylistTracks: isLoadingPlaylistTracks,
                            showingFolderPicker: $showingFolderPicker,
                            selectedItem: $selectedItem,
                            isImportingNewFolder: $isImportingNewFolder,
                            initialLoadComplete: initialLoadComplete
                        )
                    }
                }
            }
            
            // Snackbar overlay
            if let message = playlistService.snackbarMessage {
                VStack {
                    Spacer()
                    
                    SnackbarView(message: message) {
                        playlistService.dismissSnackbar()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
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
        .onChange(of: selectedItem) { newItem in
            handleSelectedItemChange(newItem)
        }
        .onChange(of: menuActionState.shouldOpenFolder) { shouldOpen in
            if shouldOpen {
                showingFolderPicker = true
                menuActionState.shouldOpenFolder = false
            }
        }
        .onChange(of: menuActionState.shouldImportAudio) { shouldImport in
            if shouldImport {
                // TODO: Implement file import
                menuActionState.shouldImportAudio = false
            }
        }
        .onChange(of: menuActionState.shouldClearSavedFolder) { shouldClear in
            if shouldClear {
                preferenceService.clearLastFolder()
                menuActionState.shouldClearSavedFolder = false
            }
        }
        .onChange(of: menuActionState.shouldRegenerateWaveforms) { shouldRegenerate in
            if shouldRegenerate {
                Task {
                    await regenerateAllWaveforms()
                }
                menuActionState.shouldRegenerateWaveforms = false
            }
        }
        .onChange(of: menuActionState.shouldGoToCurrentTrack) { shouldGoTo in
            if shouldGoTo {
                NotificationCenter.default.post(name: NSNotification.Name("GoToCurrentTrack"), object: nil)
                menuActionState.shouldGoToCurrentTrack = false
            }
        }
        .onChange(of: collectionService.tracks) { newTracks in
            print("[ContentView] tracks changed, count=\(newTracks.count)")
            
            // Only reload playlist tracks if the track structure changed (added/removed tracks)
            // Don't reload for metadata changes (tags, ratings, etc.)
            let oldTrackIds = Set(previousTracks.compactMap(\.id))
            let newTrackIds = Set(newTracks.compactMap(\.id))
            let tracksAddedOrRemoved = oldTrackIds != newTrackIds
            
            if tracksAddedOrRemoved, let item = selectedItem {
                print("[ContentView] track structure changed, reloading playlist tracks for \(item.name)")
                Task { await loadPlaylistTracks(for: item) }
            } else if let item = selectedItem {
                // For metadata-only changes, update playlist tracks in place
                print("[ContentView] metadata changed, updating playlist tracks in place for \(item.name)")
                Task { @MainActor in
                    // Update existing playlist tracks with new metadata
                    playlistTracks = playlistTracks.compactMap { playlistTrack in
                        if let trackId = playlistTrack.id,
                           let updatedTrack = newTracks.first(where: { $0.id == trackId }) {
                            return updatedTrack
                        }
                        return playlistTrack
                    }
                }
            }
            
            // Update previous tracks for next comparison
            previousTracks = newTracks
        }
        .onAppear {
            if !hasAttemptedAutoLoad {
                hasAttemptedAutoLoad = true
                Task {
                    await attemptLoadLastFolder()
                }
            }
        }
        .sheet(item: $fileChangesData) { data in
            FileChangesSheet(
                newFiles: data.newFiles,
                deletedTracks: data.deletedTracks,
                movedUpdates: data.movedUpdates,
                onDismiss: {
                    fileChangesData = nil
                },
                onApply: { adds, deletes, moves in
                    Task {
                        do {
                            try await collectionService.applyFilesystemChanges(
                                newFiles: adds,
                                deletedTrackIds: deletes,
                                movedUpdates: moves
                            )
                        } catch {
                            await MainActor.run {
                                // Show error alert to user
                                errorMessage = "Failed to apply filesystem changes: \(error.localizedDescription)"
                                showingError = true
                            }
                        }
                    }
                }
            )
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
    
    private func handleSelectedItemChange(_ newItem: SelectableItem?) {
        if let item = newItem {
            Task {
                await loadPlaylistTracks(for: item)
            }
        } else {
            playlistTracks = []
        }
    }
    
    private func loadPlaylistTracks(for item: SelectableItem) async {
        await MainActor.run {
            isLoadingPlaylistTracks = true
        }
        
        do {
            let trackPaths: [String]
            let itemName: String
            
            switch item {
            case .playlist(let playlist):
                trackPaths = playlist.trackPaths
                itemName = playlist.name
            case .folder(let folder):
                trackPaths = try await playlistService.getFolderTrackPaths(folderId: folder.id)
                itemName = folder.name
            }
            
            print("Loading \(item.isFolder ? "folder" : "playlist"): \(itemName)")
            print("Item has \(trackPaths.count) track paths")
            print("Collection has \(collectionService.tracks.count) tracks")
            
            // Debug: Print first few track paths
            if !trackPaths.isEmpty {
                print("First 3 track paths:")
                for (index, path) in trackPaths.prefix(3).enumerated() {
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
            
            // Get tracks that match the track paths
            // Try exact match first
            var tracks = collectionService.tracks.filter { track in
                trackPaths.contains(track.path)
            }
            
            print("Found \(tracks.count) exact matching tracks")
            
            // If no exact matches, try filename matching
            if tracks.isEmpty {
                tracks = collectionService.tracks.filter { track in
                    trackPaths.contains { playlistPath in
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
                    trackPaths.contains { playlistPath in
                        let normalizedTrackPath = URL(fileURLWithPath: track.path).standardized.path
                        let normalizedPlaylistPath = URL(fileURLWithPath: playlistPath).standardized.path
                        return normalizedTrackPath == normalizedPlaylistPath
                    }
                }
                print("Found \(tracks.count) normalized matching tracks")
            }
            
            // Sort tracks according to track order
            let sortedTracks = trackPaths.compactMap { trackPath in
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
        // Reset initial load complete flag and scan flag for new folder
        await MainActor.run {
            initialLoadComplete = false
            hasRunInitialScan = false
        }
        
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
            let preferredDBURL = url.appendingPathComponent("collection.vaux")
            let dbAtRoot = rootContents.first { $0.pathExtension.lowercased() == "vaux" }
            var dbURL: URL
            if FileManager.default.fileExists(atPath: preferredDBURL.path) {
                dbURL = preferredDBURL
                print("[OpenFolder] Found VAUX database at root: \(dbURL.path)")
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
            
            // Set up playlist service with the same database, collection, and queue
            playlistService.setDatabase(collectionService.getDatabase(), collectionDefinition: definition, databaseQueue: collectionService.databaseQueue, collectionService: collectionService)
            
            // If we just created a DB, import all audio files under the selected folder
            if dbAtRoot == nil {
                print("[OpenFolder] Importing audio files under root: \(url.path)")
                await MainActor.run {
                    isImportingNewFolder = true
                }
                try await collectionService.importAllAudioFilesUnderRoot(rootFolderPath: url.path)
                await MainActor.run {
                    isImportingNewFolder = false
                }
                print("[OpenFolder] Import completed")
            }

            // Load tracks, folders, then playlists sequentially to avoid concurrent access to the same SQLite connection
            print("[OpenFolder] Loading tracks...")
            try await collectionService.loadAllTracks()
            print("[OpenFolder] Tracks loaded: \(collectionService.tracks.count)")
            try await playlistService.loadFolders()
            print("[OpenFolder] Folders loaded: \(playlistService.folders.count)")
            try await playlistService.loadPlaylists()
            print("[OpenFolder] Playlists loaded: \(playlistService.playlists.count)")
            
            // Mark initial load as complete
            await MainActor.run {
                initialLoadComplete = true
            }
            
            // Scan for file changes once at startup
            await scanForFileChanges()
            
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
    
    private func scanForFileChanges() async {
        // Skip scan if we're currently importing a new folder or have already run the scan
        if isImportingNewFolder || hasRunInitialScan {
            print("🔍 [ContentView] Skipping scan - importing: \(isImportingNewFolder), already scanned: \(hasRunInitialScan)")
            return
        }
        
        do {
            print("🔍 [ContentView] Starting filesystem scan at startup...")
            hasRunInitialScan = true
            let changes = try await collectionService.scanFilesystemChanges()
            print("🔍 [ContentView] Scan completed - new: \(changes.newFiles.count), deleted: \(changes.deletedTracks.count), moved: \(changes.movedUpdates.count)")
            
            if !changes.newFiles.isEmpty || !changes.deletedTracks.isEmpty || !changes.movedUpdates.isEmpty {
                print("🔍 [ContentView] Changes detected, showing sheet...")
                print("🔍 [ContentView] New files: \(changes.newFiles.count), Deleted: \(changes.deletedTracks.count), Moved: \(changes.movedUpdates.count)")
                
                await MainActor.run {
                    fileChangesData = FileChangesData(
                        newFiles: changes.newFiles,
                        deletedTracks: changes.deletedTracks,
                        movedUpdates: changes.movedUpdates
                    )
                }
            } else {
                print("🔍 [ContentView] No changes detected")
            }
        } catch {
            print("🔍 [ContentView] Scan failed: \(error)")
        }
    }
    
    private func regenerateAllWaveforms() async {
        print("[ContentView] Starting waveform regeneration for all tracks")
        
        do {
            // Clear all existing waveform data
            try await collectionService.clearAllWaveformData()
            print("[ContentView] ✅ Cleared all waveform data")
            
            // Create waveform service and regenerate for all tracks
            let waveformService = WaveformProcessingService(collectionService: collectionService)
            
            // Process all tracks that have valid files
            let tracksToProcess = collectionService.tracks.filter { track in
                !track.isUrl && track.waveformData == nil
            }
            
            print("[ContentView] 📊 Regenerating waveforms for \(tracksToProcess.count) tracks")
            
            for track in tracksToProcess {
                waveformService.analyzeIfMissing(track)
            }
            
            print("[ContentView] ✅ Waveform regeneration queued for all tracks")
            
        } catch {
            print("[ContentView] ❌ Failed to regenerate waveforms: \(error)")
            await MainActor.run {
                errorMessage = "Failed to regenerate waveforms: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - File Changes Data
struct FileChangesData: Identifiable {
    let id = UUID()
    let newFiles: [String]
    let deletedTracks: [Track]
    let movedUpdates: [CollectionService.MovedFileUpdate]
}

// MARK: - File Changes Sheet
struct FileChangesSheet: View {
    let newFiles: [String]
    let deletedTracks: [Track]
    let movedUpdates: [CollectionService.MovedFileUpdate]
    var onDismiss: () -> Void
    var onApply: (_ adds: [String], _ deletes: [Int], _ moves: [CollectionService.MovedFileUpdate]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("Library Changes Detected")
                    .font(.title2)
                    .bold()
            }
            
            Text("The following changes have been detected in your music library:")
                .foregroundColor(.secondary)
            
            // Summary
            VStack(alignment: .leading, spacing: 8) {
                if !newFiles.isEmpty {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                        Text("\(newFiles.count) new file\(newFiles.count == 1 ? "" : "s") added to library")
                            .fontWeight(.medium)
                    }
                }
                
                if !deletedTracks.isEmpty {
                    HStack {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                        Text("\(deletedTracks.count) file\(deletedTracks.count == 1 ? "" : "s") removed from library")
                            .fontWeight(.medium)
                    }
                }
                
                if !movedUpdates.isEmpty {
                    HStack {
                        Image(systemName: "arrow.right.arrow.left.circle.fill")
                            .foregroundColor(.blue)
                        Text("\(movedUpdates.count) file\(movedUpdates.count == 1 ? "" : "s") moved/renamed")
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(.vertical, 8)
            
            // Details section
            if !newFiles.isEmpty || !deletedTracks.isEmpty || !movedUpdates.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Details:")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            // New files
                            if !newFiles.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("New Files:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.green)
                                    
                                    ForEach(newFiles.prefix(10), id: \.self) { path in
                                        HStack {
                                            Image(systemName: "plus.circle")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if newFiles.count > 10 {
                                        Text("... and \(newFiles.count - 10) more")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                            }
                            
                            // Deleted files
                            if !deletedTracks.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Removed Files:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.red)
                                    
                                    ForEach(deletedTracks.prefix(10), id: \.id) { track in
                                        HStack {
                                            Image(systemName: "minus.circle")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                            Text(track.displayTitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if deletedTracks.count > 10 {
                                        Text("... and \(deletedTracks.count - 10) more")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                            }
                            
                            // Moved files
                            if !movedUpdates.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Moved Files:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                    
                                    ForEach(movedUpdates.prefix(10), id: \.id) { upd in
                                        HStack {
                                            Image(systemName: "arrow.right.arrow.left")
                                                .foregroundColor(.blue)
                                                .font(.caption)
                                            Text(upd.trackTitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if movedUpdates.count > 10 {
                                        Text("... and \(movedUpdates.count - 10) more")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 200)
                }
            }
            
            Spacer()
            
            // Action button
            HStack {
                Spacer()
                Button("OK") {
                    // Apply all changes when OK is clicked
                    let deletedIds = deletedTracks.compactMap { $0.id }
                    onApply(newFiles, deletedIds, movedUpdates)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
    }
}

#Preview {
    ContentView()
}
