import SwiftUI

// Example showing how to integrate the TrackMetadataManager into your app
struct ContentView_Integration_Example: View {
    @StateObject private var collectionService = CollectionService()
    @StateObject private var audioService = AudioService()
    
    // The new metadata manager - single source of truth for track updates
    @StateObject private var metadataManager: TrackMetadataManager
    
    init() {
        let collectionService = CollectionService()
        let metadataManager = TrackMetadataManager(collectionService: collectionService)
        
        // Use _StateObject for proper initialization
        _collectionService = StateObject(wrappedValue: collectionService)
        _metadataManager = StateObject(wrappedValue: metadataManager)
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar content
            VStack {
                Text("Collections")
                    .font(.headline)
                // Collection list here
            }
        } detail: {
            // Main content - Use metadataManager.getAllTracks() instead of collectionService.tracks
            TrackListView_New(
                metadataManager: metadataManager,
                collectionService: collectionService,
                audioService: audioService
            )
        }
    }
}

// Updated TrackListView that uses TrackMetadataManager
struct TrackListView_New: View {
    @ObservedObject var metadataManager: TrackMetadataManager
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var audioService: AudioService
    
    @State private var sortOrder = [KeyPathComparator(\Track.title)]
    @State private var searchText = ""
    @State private var selectedTracks = Set<Track.ID>()
    @State private var showTagEditor = false
    
    // Use metadataManager instead of collectionService for track data
    private var tracks: [Track] {
        metadataManager.getAllTracks()
    }
    
    var filteredTracks: [Track] {
        if searchText.isEmpty {
            return tracks.sorted(using: sortOrder)
        } else {
            return tracks.filter { track in
                track.title.localizedCaseInsensitiveContains(searchText) ||
                track.artist.localizedCaseInsensitiveContains(searchText) ||
                track.album.localizedCaseInsensitiveContains(searchText)
            }.sorted(using: sortOrder)
        }
    }
    
    var body: some View {
        VStack {
            searchBar
            
            Table(filteredTracks, selection: $selectedTracks, sortOrder: $sortOrder) {
                TableColumn("Title", value: \.title) { track in
                    titleCell(for: track)
                }
                .width(min: 150, ideal: 250)
                
                TableColumn("Artist", value: \.artist) { track in
                    Text(track.artist)
                }
                .width(min: 100, ideal: 150)
                
                TableColumn("Album", value: \.album) { track in
                    Text(track.album)
                }
                .width(min: 100, ideal: 150)
                
                TableColumn("Duration", value: \.duration) { track in
                    Text(track.formattedDuration)
                        .monospacedDigit()
                }
                .width(70)
                
                TableColumn("Rating", value: \.rating) { track in
                    // Use the new rating component with metadata manager
                    if let trackId = track.id {
                        InteractiveStarRating_New(
                            trackId: trackId,
                            metadataManager: metadataManager
                        )
                    }
                }
                .width(100)
                
                TableColumn("Tags", value: \.generalTagsText) { track in
                    // Use the new tags component with metadata manager
                    if let trackId = track.id {
                        InteractiveTagsView_New(
                            trackId: trackId,
                            metadataManager: metadataManager
                        )
                    }
                }
            }
            .contextMenu {
                contextMenu
            }
        }
        .sheet(isPresented: $showTagEditor) {
            let selectedTrackIds = filteredTracks
                .filter { selectedTracks.contains($0.id) }
                .compactMap { $0.id }
            
            // Use the new TagEditorView with metadata manager
            TagEditorView_New(
                metadataManager: metadataManager,
                collectionService: collectionService,
                trackIds: selectedTrackIds
            )
        }
    }
    
    @ViewBuilder
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search tracks...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Spacer()
            
            Text("\(filteredTracks.count) tracks")
                .foregroundColor(.secondary)
            
            if !selectedTracks.isEmpty {
                Text("\(selectedTracks.count) selected")
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal)
        .padding(.top)
    }
    
    @ViewBuilder
    private func titleCell(for track: Track) -> some View {
        VStack(alignment: .leading) {
            Text(track.title)
                .fontWeight(.medium)
            if !track.artist.isEmpty && track.artist != "Unknown" {
                Text(track.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var contextMenu: some View {
        if !selectedTracks.isEmpty {
            Button("Edit Tags…") {
                showTagEditor = true
            }
        }
    }
}
