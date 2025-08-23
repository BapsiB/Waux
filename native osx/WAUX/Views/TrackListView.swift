import SwiftUI

struct TrackListView: View {
    let tracks: [Track]
    @State private var sortOrder = [KeyPathComparator(\Track.title)]
    @State private var searchText = ""
    @State private var selectedTracks = Set<Track.ID>()
    
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
            // Search bar
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
            
            // Track table
            Table(filteredTracks, selection: $selectedTracks, sortOrder: $sortOrder) {
                TableColumn("Title", value: \.title) { track in
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
                
                TableColumn("Album", value: \.album) { track in
                    Text(track.album)
                }
                
                TableColumn("Duration", value: \.duration) { track in
                    Text(track.formattedDuration)
                        .monospacedDigit()
                }
                
                TableColumn("Rating", value: \.rating) { track in
                    HStack {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= track.rating ? "star.fill" : "star")
                                .foregroundColor(star <= track.rating ? .yellow : .gray)
                                .font(.caption)
                        }
                    }
                }
                
                TableColumn("Type", value: \.sourceType.rawValue) { track in
                    HStack {
                        Image(systemName: iconName(for: track.sourceType))
                            .foregroundColor(color(for: track.sourceType))
                        Text(track.sourceType.rawValue.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                TableColumn("Path", value: \.path) { track in
                    Text(track.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .tableStyle(.bordered)
            .onKeyPress("a", phases: .down) { press in
                if press.modifiers.contains(.command) {
                    // Select all tracks
                    selectedTracks = Set(filteredTracks.compactMap { $0.id })
                    return .handled
                }
                return .ignored
            }
        }
    }
    
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
    TrackListView(tracks: [
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
    ])
}
