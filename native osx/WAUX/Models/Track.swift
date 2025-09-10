import Foundation
import SwiftUI

// MARK: - Enums
enum TrackSource: String, Codable {
    case local = "local"
    case url = "url"
    case youtube = "youtube"
}

enum CollectionType: String, Codable {
    case local = "local"
    case shared = "shared"
}

// MARK: - TimeMarker
struct TimeMarker: Codable, Identifiable, Equatable {
    let id = UUID()
    let time: Int // milliseconds
    let label: String
    let color: Color?
    
    init(time: Int, label: String, color: Color? = nil) {
        self.time = time
        self.label = label
        self.color = color
    }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case time, label, colorValue
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(Int.self, forKey: .time)
        label = try container.decode(String.self, forKey: .label)
        
        if let colorValue = try container.decodeIfPresent(Int.self, forKey: .colorValue) {
            color = Color(hex: colorValue)
        } else {
            color = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time, forKey: .time)
        try container.encode(label, forKey: .label)
        
        if let color = color {
            try container.encode(color.toHex(), forKey: .colorValue)
        }
    }
}

// MARK: - Track
struct Track: Identifiable, Codable, Comparable, Equatable, Hashable {
    let id: Int?
    let title: String
    let artist: String
    let album: String
    let path: String
    let isUrl: Bool
    let duration: Int // milliseconds
    let timeMarkers: [TimeMarker]
    let waveformData: [Double]?
    let rating: Int // 0-5 stars
    let comment: String
    let generalTags: [String]
    let dateAdded: Date // When the track was added to the collection
    
    // Additional metadata fields
    let albumArtist: String?
    let composer: String?
    let genre: String?
    let year: Int?
    let trackNumber: Int?
    let discNumber: Int?
    let bpm: Int?
    
    init(
        id: Int? = nil,
        title: String,
        artist: String,
        album: String,
        albumArtist: String? = nil,
        composer: String? = nil,
        genre: String? = nil,
        year: Int? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        bpm: Int? = nil,
        path: String,
        isUrl: Bool,
        duration: Int,
        timeMarkers: [TimeMarker] = [],
        waveformData: [Double]? = nil,
        rating: Int = 0,
        comment: String = "",
        generalTags: [String] = [],
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.composer = composer
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.bpm = bpm
        self.path = path
        self.isUrl = isUrl
        self.duration = duration
        self.timeMarkers = timeMarkers
        self.waveformData = waveformData
        self.rating = rating
        self.comment = comment
        self.generalTags = generalTags
        self.dateAdded = dateAdded
    }
    
    var sourceType: TrackSource {
        if !isUrl {
            return .local
        } else {
            if path.contains("youtube.com") || path.contains("youtu.be") {
                return .youtube
            } else {
                return .url
            }
        }
    }
    
    var formattedDuration: String {
        let totalSeconds = duration / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var displayTitle: String {
        if !artist.isEmpty && artist != "Unknown" {
            return "\(title) - \(artist)"
        }
        return title
    }
    
    // MARK: - Sort helpers (non-optional, Comparable)
    var idSortValue: Int { id ?? Int.max }
    var idDisplay: String { id.map(String.init) ?? "" }
    var albumArtistText: String { albumArtist ?? "" }
    var composerText: String { composer ?? "" }
    var genreText: String { genre ?? "" }
    var yearSortValue: Int { year ?? Int.min }
    var trackNumberSortValue: Int { trackNumber ?? Int.min }
    var discNumberSortValue: Int { discNumber ?? Int.min }
    var bpmSortValue: Int { bpm ?? Int.min }
    var isUrlSortValue: Int { isUrl ? 1 : 0 }
    var timeMarkersCount: Int { timeMarkers.count }
    var waveformPointCount: Int { waveformData?.count ?? 0 }
    var generalTagsText: String { generalTags.joined(separator: ", ") }
    var formattedDateAdded: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateAdded)
    }
    
    // MARK: - Comparable
    static func < (lhs: Track, rhs: Track) -> Bool {
        // First compare by rating (higher ratings first)
        if lhs.rating != rhs.rating {
            // If either track has no rating (0), it should go last
            if lhs.rating == 0 { return false }
            if rhs.rating == 0 { return true }
            // Otherwise, higher rating comes first (descending order)
            return lhs.rating > rhs.rating
        }
        
        // If ratings are equal, compare by source type
        if lhs.sourceType != rhs.sourceType {
            // Define source type priority: local > youtube > url
            let sourcePriority: [TrackSource: Int] = [
                .local: 0,
                .youtube: 1,
                .url: 2
            ]
            return sourcePriority[lhs.sourceType]! < sourcePriority[rhs.sourceType]!
        }
        
        // If source types are equal, sort by title
        return lhs.title.lowercased() < rhs.title.lowercased()
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        // Use id if available, otherwise use a combination of path and title for uniqueness
        if let id = id {
            hasher.combine(id)
        } else {
            hasher.combine(path)
            hasher.combine(title)
            hasher.combine(artist)
        }
    }
    
    static func == (lhs: Track, rhs: Track) -> Bool {
        // If both have IDs, compare by stable ID and user-editable fields that affect UI
        if let lhsId = lhs.id, let rhsId = rhs.id {
            return lhsId == rhsId
                && lhs.rating == rhs.rating
                && lhs.comment == rhs.comment
                && lhs.generalTags == rhs.generalTags
                && lhs.waveformPointCount == rhs.waveformPointCount
        }
        // Otherwise, compare by key identity plus user-editable fields
        return lhs.path == rhs.path
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.rating == rhs.rating
            && lhs.comment == rhs.comment
            && lhs.generalTags == rhs.generalTags
            && lhs.waveformPointCount == rhs.waveformPointCount
    }
    
    // MARK: - Update Helper
    func withUpdates(_ updates: [String: Any]) -> Track {
        return Track(
            id: self.id,
            title: updates["title"] as? String ?? self.title,
            artist: updates["artist"] as? String ?? self.artist,
            album: updates["album"] as? String ?? self.album,
            albumArtist: updates["albumArtist"] as? String ?? self.albumArtist,
            composer: updates["composer"] as? String ?? self.composer,
            genre: updates["genre"] as? String ?? self.genre,
            year: updates["year"] as? Int ?? self.year,
            trackNumber: updates["trackNumber"] as? Int ?? self.trackNumber,
            discNumber: updates["discNumber"] as? Int ?? self.discNumber,
            bpm: updates["bpm"] as? Int ?? self.bpm,
            path: self.path,
            isUrl: self.isUrl,
            duration: self.duration,
            timeMarkers: self.timeMarkers,
            waveformData: updates["waveformData"] as? [Double] ?? self.waveformData,
            rating: updates["rating"] as? Int ?? self.rating,
            comment: updates["comment"] as? String ?? self.comment,
            generalTags: updates["generalTags"] as? [String] ?? self.generalTags,
            dateAdded: self.dateAdded
        )
    }
}

// MARK: - CollectionDefinition
struct CollectionDefinition: Identifiable, Codable {
    let id: String
    let name: String
    let type: CollectionType
    let dbPath: String
    let rootPath: String?
    
    init(id: String, name: String, type: CollectionType, dbPath: String, rootPath: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.dbPath = dbPath
        self.rootPath = rootPath
        
        // Validation
        if type == .shared && (rootPath == nil || rootPath!.isEmpty) {
            fatalError("Shared collections must have a non-empty rootPath.")
        }
        if type == .local && rootPath != nil {
            fatalError("Local collections should not have a rootPath.")
        }
    }
}

// MARK: - Color Extensions
extension Color {
    init(hex: Int) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
    
    func toHex() -> Int {
        let components = NSColor(self).cgColor.components ?? [0, 0, 0, 0]
        let red = Int(components[0] * 255.0)
        let green = Int(components[1] * 255.0)
        let blue = Int(components[2] * 255.0)
        return (red << 16) | (green << 8) | blue
    }
}
