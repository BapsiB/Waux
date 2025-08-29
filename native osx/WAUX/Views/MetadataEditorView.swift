import SwiftUI

struct MetadataEditorView: View {
    @ObservedObject var metadataManager: TrackMetadataManager
    @ObservedObject var collectionService: CollectionService
    private let trackIds: [Int]
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var metadataValues: [String: String] = [:]
    @State private var metadataNumbers: [String: Int?] = [:]
    @State private var errorMessage: String? = nil
    
    // Computed properties for current metadata state
    private var tracks: [Track] {
        metadataManager.getTracks(ids: trackIds)
    }
    
    private var isMultipleTracks: Bool {
        tracks.count > 1
    }
    
    init(metadataManager: TrackMetadataManager, collectionService: CollectionService, trackIds: [Int]) {
        self.metadataManager = metadataManager
        self.collectionService = collectionService
        self.trackIds = trackIds
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isMultipleTracks ? "Edit Multiple Tracks Metadata" : "Edit Track Metadata")
                .font(.title3)
                .fontWeight(.semibold)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Basic metadata
                    GroupBox("Basic Information") {
                        VStack(alignment: .leading, spacing: 12) {
                            metadataField("Title", key: "title", isRequired: true)
                            metadataField("Artist", key: "artist", isRequired: true)
                            metadataField("Album", key: "album", isRequired: true)
                            metadataField("Album Artist", key: "albumArtist")
                            metadataField("Composer", key: "composer")
                            metadataField("Genre", key: "genre")
                        }
                    }
                    
                    // Track details
                    GroupBox("Track Details") {
                        VStack(alignment: .leading, spacing: 12) {
                            metadataNumberField("Year", key: "year", range: 1900...2100)
                            metadataNumberField("Track Number", key: "trackNumber", range: 1...999)
                            metadataNumberField("Disc Number", key: "discNumber", range: 1...99)
                            metadataNumberField("BPM", key: "bpm", range: 1...999)
                        }
                    }
                    
                    // User data
                    GroupBox("User Data") {
                        VStack(alignment: .leading, spacing: 12) {
                            metadataField("Comment", key: "comment")
                            metadataField("Tags", key: "generalTags")
                        }
                    }
                    
                    // Read-only information
                    GroupBox("File Information") {
                        VStack(alignment: .leading, spacing: 8) {
                            readOnlyField("Duration", value: formatDuration(tracks.first?.duration ?? 0))
                            readOnlyField("Path", value: tracks.first?.path ?? "")
                            readOnlyField("Date Added", value: formatDate(tracks.first?.dateAdded ?? Date()))
                            readOnlyField("Type", value: tracks.first?.sourceType.rawValue.capitalized ?? "")
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            HStack {
                if metadataManager.isUpdating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Saving...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveMetadata() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(metadataManager.isUpdating)
            }
        }
        .padding(16)
        .frame(width: 600, height: 700)
        .onAppear { loadCurrentMetadata() }
    }
    
    @ViewBuilder
    private func metadataField(_ label: String, key: String, isRequired: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.headline)
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                }
                Spacer()
            }
            
            TextField(label, text: Binding(
                get: { 
                    let value = metadataValues[key] ?? ""
                    return value == "multiple" ? "" : value
                },
                set: { newValue in
                    metadataValues[key] = newValue.isEmpty ? "multiple" : newValue
                }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .overlay(
                Group {
                    if metadataValues[key] == "multiple" {
                        HStack {
                            Spacer()
                            Text("multiple")
                                .italic()
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .padding(.trailing, 8)
                        }
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private func metadataNumberField(_ label: String, key: String, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.headline)
            
            TextField(label, text: Binding(
                get: { 
                    if let value = metadataNumbers[key] {
                        return String(value ?? 0)
                    } else {
                        return ""
                    }
                },
                set: { newValue in
                    if let intValue = Int(newValue) {
                        metadataNumbers[key] = intValue
                    } else if newValue.isEmpty {
                        metadataNumbers[key] = nil
                    }
                }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .overlay(
                Group {
                    if metadataNumbers[key] == nil && isMultipleTracks {
                        HStack {
                            Spacer()
                            Text("multiple")
                                .italic()
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .padding(.trailing, 8)
                        }
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private func readOnlyField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    private func loadCurrentMetadata() {
        guard !tracks.isEmpty else { return }
        
        // For single track, load all values
        if tracks.count == 1, let track = tracks.first {
            metadataValues["title"] = track.title
            metadataValues["artist"] = track.artist
            metadataValues["album"] = track.album
            metadataValues["albumArtist"] = track.albumArtist ?? ""
            metadataValues["composer"] = track.composer ?? ""
            metadataValues["genre"] = track.genre ?? ""
            metadataValues["comment"] = track.comment
            metadataValues["generalTags"] = track.generalTags.joined(separator: ", ")
            
            metadataNumbers["year"] = track.year
            metadataNumbers["trackNumber"] = track.trackNumber
            metadataNumbers["discNumber"] = track.discNumber
            metadataNumbers["bpm"] = track.bpm
        } else {
            // For multiple tracks, check for common values or show "multiple"
            let titles = Set(tracks.map { $0.title })
            metadataValues["title"] = titles.count == 1 ? (titles.first ?? "") : "multiple"
            
            let artists = Set(tracks.map { $0.artist })
            metadataValues["artist"] = artists.count == 1 ? (artists.first ?? "") : "multiple"
            
            let albums = Set(tracks.map { $0.album })
            metadataValues["album"] = albums.count == 1 ? (albums.first ?? "") : "multiple"
            
            let albumArtists = Set(tracks.compactMap { $0.albumArtist })
            metadataValues["albumArtist"] = albumArtists.count == 1 ? (albumArtists.first ?? "") : "multiple"
            
            let composers = Set(tracks.compactMap { $0.composer })
            metadataValues["composer"] = composers.count == 1 ? (composers.first ?? "") : "multiple"
            
            let genres = Set(tracks.compactMap { $0.genre })
            metadataValues["genre"] = genres.count == 1 ? (genres.first ?? "") : "multiple"
            
            let comments = Set(tracks.map { $0.comment })
            metadataValues["comment"] = comments.count == 1 ? (comments.first ?? "") : "multiple"
            
            let allTags = Set(tracks.flatMap { $0.generalTags })
            metadataValues["generalTags"] = allTags.isEmpty ? "" : allTags.joined(separator: ", ")
            
            let years = Set(tracks.compactMap { $0.year })
            metadataNumbers["year"] = years.count == 1 ? years.first : nil
            
            let trackNumbers = Set(tracks.compactMap { $0.trackNumber })
            metadataNumbers["trackNumber"] = trackNumbers.count == 1 ? trackNumbers.first : nil
            
            let discNumbers = Set(tracks.compactMap { $0.discNumber })
            metadataNumbers["discNumber"] = discNumbers.count == 1 ? discNumbers.first : nil
            
            let bpms = Set(tracks.compactMap { $0.bpm })
            metadataNumbers["bpm"] = bpms.count == 1 ? bpms.first : nil
        }
    }
    
    private func saveMetadata() {
        Task {
            do {
                for trackId in trackIds {
                    var updates: [String: Any] = [:]
                    
                    // Update string fields
                    for (key, value) in metadataValues {
                        if value != "multiple" {
                            switch key {
                            case "title": updates["title"] = value
                            case "artist": updates["artist"] = value
                            case "album": updates["album"] = value
                            case "albumArtist": updates["albumArtist"] = value.isEmpty ? nil : value
                            case "composer": updates["composer"] = value.isEmpty ? nil : value
                            case "genre": updates["genre"] = value.isEmpty ? nil : value
                            case "comment": updates["comment"] = value
                            case "generalTags": 
                                let tags = value.isEmpty ? [] : value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                updates["generalTags"] = tags
                            default: break
                            }
                        }
                    }
                    
                    // Update number fields
                    for (key, value) in metadataNumbers {
                        if let value = value {
                            switch key {
                            case "year": updates["year"] = value
                            case "trackNumber": updates["trackNumber"] = value
                            case "discNumber": updates["discNumber"] = value
                            case "bpm": updates["bpm"] = value
                            default: break
                            }
                        }
                    }
                    
                    if !updates.isEmpty {
                        try await metadataManager.updateTrackMetadata(trackId: trackId, updates: updates)
                    }
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save metadata: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func formatDuration(_ duration: Int) -> String {
        let totalSeconds = duration / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
