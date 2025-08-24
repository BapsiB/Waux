import SwiftUI

enum TrackColumn: String, CaseIterable, Hashable {
    case id
    case title
    case artist
    case album
    case albumArtist
    case composer
    case genre
    case year
    case trackNumber
    case discNumber
    case bpm
    case path
    case isUrl
    case duration
    case timeMarkers
    case waveformData
    case rating
    case comment
    case generalTags
    case type
    
    var displayName: String {
        switch self {
        case .id: return "ID"
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .albumArtist: return "Album Artist"
        case .composer: return "Composer"
        case .genre: return "Genre"
        case .year: return "Year"
        case .trackNumber: return "Track #"
        case .discNumber: return "Disc #"
        case .bpm: return "BPM"
        case .path: return "Path"
        case .isUrl: return "URL?"
        case .duration: return "Duration"
        case .timeMarkers: return "Markers"
        case .waveformData: return "Waveform"
        case .rating: return "Rating"
        case .comment: return "Comment"
        case .generalTags: return "Tags"
        case .type: return "Type"
        }
    }
}

struct TrackListView: View {
    let tracks: [Track]
    let collectionService: CollectionService
    @ObservedObject var audioService: AudioService
    @State private var sortOrder = [KeyPathComparator(\Track.title)]
    @State private var searchText = ""
    @State private var selectedTracks = Set<Track.ID>()
    @State private var showingRatingError = false
    @State private var ratingErrorMessage = ""
    @State private var visibleColumns: Set<TrackColumn> = [.title, .artist, .album, .duration, .rating, .type]
    @State private var showTagEditor = false
    
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
            
            // Simplified table with only essential columns visible by default
            Table(filteredTracks, selection: $selectedTracks, sortOrder: $sortOrder) {
                TableColumn("Title", value: \.title) { track in
                    titleCell(for: track)
                }
                .width(min: 150, ideal: 250)
                
                if visibleColumns.contains(.artist) {
                    TableColumn("Artist", value: \.artist) { track in
                        Text(track.artist)
                    }
                    .width(min: 100, ideal: 150)
                }
                
                if visibleColumns.contains(.album) {
                    TableColumn("Album", value: \.album) { track in
                        Text(track.album)
                    }
                    .width(min: 100, ideal: 150)
                }
                
                if visibleColumns.contains(.duration) {
                    TableColumn("Duration", value: \.duration) { track in
                        Text(track.formattedDuration)
                            .monospacedDigit()
                    }
                    .width(70)
                }
                
                if visibleColumns.contains(.rating) {
                    TableColumn("Rating", value: \.rating) { track in
                        ratingCell(for: track)
                    }
                    .width(100)
                }
                
                if visibleColumns.contains(.type) {
                    TableColumn("Type", value: \.sourceType.rawValue) { track in
                        typeCell(for: track)
                    }
                    .width(80)
                }
                
                if visibleColumns.contains(.albumArtist) {
                    TableColumn("Album Artist", value: \Track.albumArtistText) { track in
                        Text(track.albumArtistText)
                            .foregroundColor(track.albumArtist?.isEmpty == false ? .primary : .secondary)
                    }
                }
                if visibleColumns.contains(.composer) {
                    TableColumn("Composer", value: \Track.composerText) { track in
                        Text(track.composerText)
                            .foregroundColor(track.composer?.isEmpty == false ? .primary : .secondary)
                    }
                }
//                if visibleColumns.contains(.genre) {
//                    TableColumn("Genre", value: \Track.genreText) { track in
//                        Text(track.genreText)
//                            .foregroundColor(track.genre?.isEmpty == false ? .primary : .secondary)
//                    }
//                }
//                if visibleColumns.contains(.year) {
//                    TableColumn("Year", value: \Track.yearSortValue) { track in
//                        if let year = track.year {
//                            Text(String(year))
//                        } else {
//                            Text("")
//                                .foregroundColor(.secondary)
//                        }
//                    }
//                }
//                if visibleColumns.contains(.trackNumber) {
//                    TableColumn("Track #", value: \Track.trackNumberSortValue) { track in
//                        if let trackNumber = track.trackNumber {
//                            Text(String(trackNumber))
//                        } else {
//                            Text("")
//                                .foregroundColor(.secondary)
//                        }
//                    }
//                }
//                if visibleColumns.contains(.discNumber) {
//                    TableColumn("Disc #", value: \Track.discNumberSortValue) { track in
//                        if let discNumber = track.discNumber {
//                            Text(String(discNumber))
//                        } else {
//                            Text("")
//                                .foregroundColor(.secondary)
//                        }
//                    }
//                }
//                if visibleColumns.contains(.bpm) {
//                    TableColumn("BPM", value: \Track.bpmSortValue) { track in
//                        if let bpm = track.bpm {
//                            Text(String(bpm))
//                        } else {
//                            Text("")
//                                .foregroundColor(.secondary)
//                        }
//                    }
//                }
//                if visibleColumns.contains(.path) {
//                    TableColumn("Path", value: \Track.path) { track in
//                        Text(track.path)
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                            .lineLimit(1)
//                            .truncationMode(.middle)
//                    }
//                }
//                if visibleColumns.contains(.isUrl) {
//                    TableColumn("URL?", value: \Track.isUrlSortValue) { track in
//                        Image(systemName: track.isUrl ? "checkmark.circle.fill" : "xmark.circle")
//                            .foregroundColor(track.isUrl ? .green : .secondary)
//                    }
//                }
//                if visibleColumns.contains(.timeMarkers) {
//                    TableColumn("Markers", value: \Track.timeMarkersCount) { track in
//                        Text("\(track.timeMarkers.count)")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
//                }
                if visibleColumns.contains(.waveformData) {
                    TableColumn("Waveform", value: \Track.waveformPointCount) { track in
                        if let waveformData = track.waveformData {
                            Text("\(waveformData.count) pts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("—")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
//                if visibleColumns.contains(.comment) {
//                    TableColumn("Comment", value: \Track.comment) { track in
//                        Text(track.comment)
//                            .lineLimit(1)
//                            .truncationMode(.tail)
//                            .foregroundColor(track.comment.isEmpty ? .secondary : .primary)
//                    }
//                }
                if visibleColumns.contains(.generalTags) {
                    TableColumn("Tags", value: \Track.generalTagsText) { track in
                        InteractiveTagsView(
                            track: track,
                            onUpdate: { tags in
                                Task {
                                    do {
                                        try await collectionService.setTagsForTrack(trackId: track.id ?? 0, newTags: tags)
                                    } catch {
                                        print("[Tags] Failed to set tags: \(error)")
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .tableStyle(.bordered)
            .onTapGesture(count: 2) {
                if let selectedTrack = selectedTracks.first,
                   let track = filteredTracks.first(where: { $0.id == selectedTrack }) {
                    print("Double-clicked track: \(track.title)")
                    print("Track path: \(track.path)")
                    print("Is URL: \(track.isUrl)")
                    print("Duration: \(track.duration) ms")
                    Task {
                        await audioService.loadTrack(track)
                        audioService.play()
                    }
                }
            }
            .contextMenu {
                columnContextMenu
            }
            .onKeyPress("a", phases: .down) { press in
                if press.modifiers.contains(.command) {
                    selectedTracks = Set(filteredTracks.compactMap { $0.id })
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.space, phases: .down) { press in
                if !selectedTracks.isEmpty {
                    audioService.togglePlayPause()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.return, phases: .down) { press in
                if let selectedTrack = selectedTracks.first,
                   let track = filteredTracks.first(where: { $0.id == selectedTrack }) {
                    Task {
                        await audioService.loadTrack(track)
                        audioService.play()
                    }
                    return .handled
                }
                return .ignored
            }
        }
        .alert("Rating Update Error", isPresented: $showingRatingError) {
            Button("OK") { }
        } message: {
            Text(ratingErrorMessage)
        }
        .sheet(isPresented: $showTagEditor) {
            let selected = filteredTracks.filter { selectedTracks.contains($0.id) }
            TagEditorView(collectionService: collectionService, tracks: selected.isEmpty ? [] : selected)
        }
    }
    
    // Removed additionalColumns and additionalTableColumn helpers; columns are inlined in the Table builder above.
    
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
    
    // MARK: - Cell Views
    
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
    private func ratingCell(for track: Track) -> some View {
        InteractiveStarRating(track: track) { newRating in
            Task {
                do {
                    try await collectionService.updateTrackRating(
                        trackId: track.id ?? 0,
                        newRating: newRating
                    )
                } catch {
                    await MainActor.run {
                        ratingErrorMessage = "Failed to update rating: \(error.localizedDescription)"
                        showingRatingError = true
                    }
                    print("Error updating rating: \(error)")
                }
            }
        }
    }
    
    @ViewBuilder
    private func typeCell(for track: Track) -> some View {
        HStack {
            Image(systemName: iconName(for: track.sourceType))
                .foregroundColor(color(for: track.sourceType))
            Text(track.sourceType.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private var columnContextMenu: some View {
        // Track actions
        if !selectedTracks.isEmpty {
            Button("Play") {
                if let selectedTrack = selectedTracks.first,
                   let track = filteredTracks.first(where: { $0.id == selectedTrack }) {
                    print("Context menu play track: \(track.title)")
                    print("Track path: \(track.path)")
                    print("Is URL: \(track.isUrl)")
                    print("Duration: \(track.duration) ms")
                    Task {
                        await audioService.loadTrack(track)
                        audioService.play()
                    }
                }
            }
            Button("Edit Tags…") {
                showTagEditor = true
            }
            Divider()
        }
        
        // Column visibility
        ForEach(TrackColumn.allCases, id: \.self) { column in
            Button {
                if visibleColumns.contains(column) {
                    // Always keep title column visible
                    if column != .title && visibleColumns.count > 1 {
                        visibleColumns.remove(column)
                    }
                } else {
                    visibleColumns.insert(column)
                }
            } label: {
                HStack {
                    Text(column.displayName)
                    Spacer()
                    if visibleColumns.contains(column) {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .disabled(column == .title) // Title column is always visible
        }
        Divider()
        Button("Show All Columns") {
            visibleColumns = Set(TrackColumn.allCases)
        }
        Button("Show Default Columns") {
            visibleColumns = [.title, .artist, .album, .duration, .rating, .type]
        }
    }
    
    // MARK: - Helper Methods
    
    private func iconName(for sourceType: TrackSource) -> String {
        switch sourceType {
        case .local:
            return "music.note"
        case .youtube:
            return "play.rectangle"
        case .url:
            return "link"
        }
    }
    
    private func color(for sourceType: TrackSource) -> Color {
        switch sourceType {
        case .local:
            return .blue
        case .youtube:
            return .red
        case .url:
            return .green
        }
    }
}

#Preview {
    TrackListView(
        tracks: [
            Track(
                title: "Sample Track 1",
                artist: "Sample Artist",
                album: "Sample Album",
                path: "/path/to/track1.mp3",
                isUrl: false,
                duration: 180000,
                rating: 4
            ),
            Track(
                title: "Sample Track 2",
                artist: "Another Artist",
                album: "Another Album",
                path: "https://example.com/track2.mp3",
                isUrl: true,
                duration: 240000,
                rating: 3
            )
        ],
        collectionService: CollectionService(),
        audioService: AudioService()
    )
}
