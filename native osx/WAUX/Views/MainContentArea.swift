import SwiftUI

struct MainContentArea: View {
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var playlistService: PlaylistService
    @ObservedObject var audioService: AudioService
    let playlistTracks: [Track]
    let isLoadingPlaylistTracks: Bool
    @Binding var showingFolderPicker: Bool
    @Binding var selectedPlaylist: Playlist?
    
    private var activeCollection: CollectionDefinition? {
        collectionService.getActiveCollection()
    }
    
    private var tracksCount: Int {
        collectionService.tracks.count
    }
    
    var body: some View {
        VStack {
            if collectionService.isLoading {
                ProgressView("Loading collection...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let playlist = selectedPlaylist {
                // Show playlist tracks
                VStack {
                    // Playlist header with close button
                    HStack {
                        Text("Playlist: \(playlist.name)")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        if !playlistTracks.isEmpty {
                            Text("\(playlistTracks.count) tracks")
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: {
                            selectedPlaylist = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Close playlist and return to all tracks")
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    if isLoadingPlaylistTracks {
                        ProgressView("Loading playlist tracks...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !playlistTracks.isEmpty {
                        TrackListView(collectionService: collectionService, audioService: audioService, tracksFilter: playlistTracks)
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
                VStack {
                    HStack {
                        Text("All Tracks")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Text("\(tracksCount) tracks")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    TrackListView(collectionService: collectionService, audioService: audioService)
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
}
