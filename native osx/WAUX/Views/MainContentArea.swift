import SwiftUI

struct MainContentArea: View {
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var playlistService: PlaylistService
    @ObservedObject var audioService: AudioService
    let playlistTracks: [Track]
    let isLoadingPlaylistTracks: Bool
    @Binding var showingFolderPicker: Bool
    @Binding var selectedPlaylist: Playlist?
    @State private var searchText = ""
    
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
            } else if let playlist = selectedPlaylist {
                // Show playlist tracks
                VStack(spacing: 0) {
                    // Header with title, audio player, and search
                    headerView(title: playlist.name, showCloseButton: true) {
                        selectedPlaylist = nil
                    }
                    
                    if isLoadingPlaylistTracks {
                        ProgressView("Loading playlist tracks...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !playlistTracks.isEmpty {
                        TrackListView(
                            collectionService: collectionService, 
                            audioService: audioService, 
                            tracksFilter: playlistTracks,
                            searchText: $searchText
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
                    // Header with title, audio player, and search
                    headerView(title: "All Tracks", showCloseButton: false)
                    
                    TrackListView(
                        collectionService: collectionService, 
                        audioService: audioService,
                        searchText: $searchText
                    )
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
        .onChange(of: collectionService.isLoading) { _, _ in
            print("[UI] Collection loading state changed - isLoading: \(collectionService.isLoading), activeCollection: \(activeCollection != nil), tracksCount: \(tracksCount)")
        }
        .onChange(of: tracksCount) { _, _ in
            print("[UI] Tracks count changed - isLoading: \(collectionService.isLoading), activeCollection: \(activeCollection != nil), tracksCount: \(tracksCount)")
        }
    }
    
    @ViewBuilder
    private func headerView(title: String, showCloseButton: Bool = false, onClose: (() -> Void)? = nil) -> some View {
        HStack(spacing: 16) {
            // Title
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
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
            }
            
            Spacer()
            
            // Audio player controls (only show when track is loaded)
            if audioService.currentTrack != nil {
                CompactAudioPlayerView(audioService: audioService)
            }
            
            Spacer()
            
            // Search bar (smaller)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("Search tracks...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 150)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
        .frame(height: 60)
    }
}
