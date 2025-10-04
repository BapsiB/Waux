import SwiftUI

struct MainContentArea: View {
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var playlistService: PlaylistService
    @ObservedObject var audioService: AudioService
    let playlistTracks: [Track]
    let isLoadingPlaylistTracks: Bool
    @Binding var showingFolderPicker: Bool
    @Binding var selectedItem: SelectableItem?
    @Binding var isImportingNewFolder: Bool
    let initialLoadComplete: Bool
    @StateObject private var searchService = SearchService()
    @State private var showFolderView = false
    @StateObject private var folderManager = FolderHierarchyManager()
    @State private var hasAutoLoadedFirstTrack = false
    @State private var currentCollectionId: String? = nil
    
    private var activeCollection: CollectionDefinition? {
        collectionService.getActiveCollection()
    }
    
    private var tracksCount: Int {
        collectionService.tracks.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if collectionService.isLoading {
                ProgressView("Loading collection...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let item = selectedItem {
                // Show playlist tracks
                VStack(spacing: 0) {
                    // Header with title, audio player, and search
                    headerView(title: item.name, showCloseButton: true) {
                        selectedItem = nil
                    }
                    
                    if isLoadingPlaylistTracks {
                        ProgressView("Loading playlist tracks...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !playlistTracks.isEmpty {
                        TrackListView(
                            collectionService: collectionService, 
                            audioService: audioService, 
                            tracksFilter: playlistTracks,
                            searchService: searchService,
                            isImportingNewFolder: $isImportingNewFolder,
                            initialLoadComplete: initialLoadComplete
                        )
                    } else {
                        // Empty playlist content
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
                }
            } else if activeCollection != nil {
                // Show all tracks when no playlist is selected
                VStack(spacing: 0) {
                    // Header with title, audio player, search, and view toggle
                    headerView(title: "All Tracks", showCloseButton: false, showViewToggle: true)
                    
                    if showFolderView {
                        FolderHierarchyView(
                            collectionService: collectionService,
                            audioService: audioService,
                            folderManager: folderManager,
                            searchService: searchService
                        )
                    } else {
                        TrackListView(
                            collectionService: collectionService, 
                            audioService: audioService,
                            searchService: searchService,
                            isImportingNewFolder: $isImportingNewFolder,
                            initialLoadComplete: initialLoadComplete
                        )
                    }
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
                        print("[UI] Open Folder button tapped")
                        showingFolderPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            print("[UI] Rendering main area - isLoading: \(collectionService.isLoading), activeCollection: \(activeCollection != nil), tracksCount: \(tracksCount)")
        }
        .onChange(of: collectionService.isLoading) { _ in
            print("[UI] Collection loading state changed - isLoading: \(collectionService.isLoading), activeCollection: \(activeCollection != nil), tracksCount: \(tracksCount)")
        }
        .onChange(of: tracksCount) { _ in
            print("[UI] Tracks count changed - isLoading: \(collectionService.isLoading), activeCollection: \(activeCollection != nil), tracksCount: \(tracksCount)")
        }
        .onChange(of: collectionService.tracks) { newTracks in
            // Auto-load first track when collection is loaded and no track is currently playing
            if !collectionService.isLoading && 
               !newTracks.isEmpty && 
               audioService.currentTrack == nil && 
               !hasAutoLoadedFirstTrack {
                
                print("[UI] Auto-loading first track from collection")
                hasAutoLoadedFirstTrack = true
                
                let firstTrack = newTracks.first!
                Task {
                    _ = await audioService.loadTrack(firstTrack)
                    print("[UI] First track loaded: \(firstTrack.title)")
                }
            }
        }
        .onChange(of: activeCollection?.id) { newCollectionId in
            // Reset auto-load flag when collection changes
            if newCollectionId != currentCollectionId {
                currentCollectionId = newCollectionId
                hasAutoLoadedFirstTrack = false
                print("[UI] Collection changed, reset auto-load flag")
            }
        }
    }
    
    @ViewBuilder
    private func headerView(title: String, showCloseButton: Bool = false, showViewToggle: Bool = false, onClose: (() -> Void)? = nil) -> some View {
        HStack(alignment: .center, spacing: 16) {
            // Title and menu section aligned with play buttons
            HStack(spacing: 16) {
                // Title
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                // View toggle button (only show for "All Tracks")
                if showViewToggle {
                    Menu {
                        Button(action: {
                            showFolderView = false
                        }) {
                            HStack {
                                Image(systemName: "list.bullet")
                                Text("List")
                            }
                        }
                        
                        Button(action: {
                            showFolderView = true
                        }) {
                            HStack {
                                Image(systemName: "folder")
                                Text("Folders")
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: showFolderView ? "folder" : "list.bullet")
                                .font(.system(size: 16))
                                .frame(minWidth: 30)
                                .contentShape(Rectangle())
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(minHeight: 30)
                                .contentShape(Rectangle())
                        }
                        .offset(x: -5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(showFolderView ? "Switch to list view" : "Switch to folder view")
                }
            }
            .offset(y: -10) // Align with the CompactAudioPlayerView offset
            
            if showCloseButton {
                Button(action: {
                    onClose?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Close playlist and return to all tracks")
                .offset(y: -10) // Align with the CompactAudioPlayerView offset
            }
            
            Spacer()
            
            // Audio player controls (only show when track is loaded)
            if audioService.currentTrack != nil {
                CompactAudioPlayerView(audioService: audioService, collectionService: collectionService)
            }
            
            Spacer()
            
            // Search bar
            SearchBarView(searchService: searchService).offset(y: -10)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
        .frame(height: 60)
    }
}
