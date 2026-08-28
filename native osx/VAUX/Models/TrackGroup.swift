import Foundation
import SwiftUI

// MARK: - TrackGroup
struct TrackGroup: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var mainTrackId: Int
    var trackIds: Set<Int>
    let dateCreated: Date
    var isExpanded: Bool
    
    init(trackIds: Set<Int>, mainTrackId: Int, name: String = "") {
        self.id = UUID().uuidString
        self.trackIds = trackIds
        self.mainTrackId = mainTrackId
        self.name = name
        self.dateCreated = Date()
        self.isExpanded = false
        
        // Validation: mainTrackId must be in trackIds
        assert(trackIds.contains(mainTrackId), "Main track ID must be included in track IDs")
        assert(trackIds.count >= 2, "Track group must contain at least 2 tracks")
    }
    
    // Database loading initializer
    init(id: String, name: String, mainTrackId: Int, trackIds: Set<Int>, dateCreated: Date, isExpanded: Bool) {
        self.id = id
        self.name = name
        self.mainTrackId = mainTrackId
        self.trackIds = trackIds
        self.dateCreated = dateCreated
        self.isExpanded = isExpanded
        
        // Validation: mainTrackId must be in trackIds (only if trackIds is not empty)
        if !trackIds.isEmpty {
            assert(trackIds.contains(mainTrackId), "Main track ID must be included in track IDs")
        }
    }
    
    // MARK: - Computed Properties
    var trackCount: Int {
        return trackIds.count
    }
    
    var displayName: String {
        return name.isEmpty ? "Track Group" : name
    }
    
    // MARK: - Methods
    mutating func addTrack(_ trackId: Int) {
        trackIds.insert(trackId)
    }
    
    mutating func removeTrack(_ trackId: Int) -> Bool {
        guard trackIds.count > 2 else { return false } // Cannot remove if only 2 tracks left
        guard trackId != mainTrackId else { return false } // Cannot remove main track directly
        
        trackIds.remove(trackId)
        return true
    }
    
    mutating func setMainTrack(_ trackId: Int) -> Bool {
        guard trackIds.contains(trackId) else { return false }
        mainTrackId = trackId
        return true
    }
    
    func contains(_ trackId: Int) -> Bool {
        return trackIds.contains(trackId)
    }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, name, mainTrackId, trackIds, dateCreated, isExpanded
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        mainTrackId = try container.decode(Int.self, forKey: .mainTrackId)
        trackIds = try container.decode(Set<Int>.self, forKey: .trackIds)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        isExpanded = try container.decode(Bool.self, forKey: .isExpanded)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(mainTrackId, forKey: .mainTrackId)
        try container.encode(trackIds, forKey: .trackIds)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(isExpanded, forKey: .isExpanded)
    }
}

// MARK: - TrackDisplayItem
enum TrackDisplayItem: Identifiable, Equatable {
    case individual(Track)
    case container(GroupedTrack)
    case groupMember(Track, groupId: String)

    static func == (lhs: TrackDisplayItem, rhs: TrackDisplayItem) -> Bool {
        guard lhs.id == rhs.id else { return false }
        let a = lhs.track
        let b = rhs.track
        return a.waveformPointCount == b.waveformPointCount
            && a.title == b.title
            && a.artist == b.artist
            && a.album == b.album
            && a.rating == b.rating
            && a.generalTags == b.generalTags
    }
    
    var id: String {
        switch self {
        case .individual(let track):
            return "track_\(track.id ?? -1)"
        case .container(let groupedTrack):
            return "group_\(groupedTrack.group.id)"
        case .groupMember(let track, let groupId):
            return "member_\(groupId)_\(track.id ?? -1)"
        }
    }
    
    var track: Track {
        switch self {
        case .individual(let track):
            return track
        case .container(let groupedTrack):
            return groupedTrack.mainTrack
        case .groupMember(let track, _):
            return track
        }
    }
    
    var isGroup: Bool {
        switch self {
        case .container:
            return true
        default:
            return false
        }
    }
    
    var isGroupMember: Bool {
        switch self {
        case .groupMember:
            return true
        default:
            return false
        }
    }
    
    var groupId: String? {
        switch self {
        case .container(let groupedTrack):
            return groupedTrack.group.id
        case .groupMember(_, let groupId):
            return groupId
        default:
            return nil
        }
    }
    
    var isContainer: Bool {
        switch self {
        case .container:
            return true
        default:
            return false
        }
    }
    
    var isMember: Bool {
        switch self {
        case .groupMember:
            return true
        default:
            return false
        }
    }
    
    var isIndividual: Bool {
        switch self {
        case .individual:
            return true
        default:
            return false
        }
    }

    func replacingTrack(_ updated: Track) -> TrackDisplayItem {
        switch self {
        case .individual(let track):
            return track.id == updated.id ? .individual(updated) : self
        case .groupMember(let track, let groupId):
            return track.id == updated.id ? .groupMember(updated, groupId: groupId) : self
        case .container(let grouped):
            let allTracks = grouped.allTracks.map { $0.id == updated.id ? updated : $0 }
            let mainTrack = grouped.mainTrack.id == updated.id ? updated : grouped.mainTrack
            return .container(GroupedTrack(group: grouped.group, mainTrack: mainTrack, allTracks: allTracks))
        }
    }
}

// MARK: - GroupedTrack
struct GroupedTrack: Identifiable, Equatable {
    let group: TrackGroup
    let mainTrack: Track
    let allTracks: [Track]
    
    init(group: TrackGroup, mainTrack: Track, allTracks: [Track]) {
        self.group = group
        self.mainTrack = mainTrack
        self.allTracks = allTracks
        
        // Validation
        assert(mainTrack.id == group.mainTrackId, "Main track ID must match group's main track ID")
        assert(allTracks.contains { $0.id == group.mainTrackId }, "Main track must be in all tracks array")
        assert(allTracks.count == group.trackIds.count, "All tracks count must match group track IDs count")
    }
    
    // MARK: - Track-like Interface (Delegation to mainTrack)
    var id: Int? { mainTrack.id }
    var title: String { group.name.isEmpty ? mainTrack.title : group.displayName }
    var artist: String { mainTrack.artist }
    var album: String { mainTrack.album }
    var path: String { mainTrack.path }
    var isUrl: Bool { mainTrack.isUrl }
    var duration: Int { mainTrack.duration }
    var timeMarkers: [TimeMarker] { mainTrack.timeMarkers }
    var waveformStatus: WaveformStatus { mainTrack.waveformStatus }
    var rating: Int { mainTrack.rating }
    var comment: String { mainTrack.comment }
    var generalTags: [String] { mainTrack.generalTags }
    var dateAdded: Date { mainTrack.dateAdded }
    
    // Additional metadata fields
    var albumArtist: String? { mainTrack.albumArtist }
    var composer: String? { mainTrack.composer }
    var genre: String? { mainTrack.genre }
    var year: Int? { mainTrack.year }
    var trackNumber: Int? { mainTrack.trackNumber }
    var discNumber: Int? { mainTrack.discNumber }
    var bpm: Int? { mainTrack.bpm }
    
    // Computed properties from Track
    var sourceType: TrackSource { mainTrack.sourceType }
    var formattedDuration: String { mainTrack.formattedDuration }
    var displayTitle: String { mainTrack.displayTitle }
    
    // Sort helpers
    var idSortValue: Int { mainTrack.idSortValue }
    var idDisplay: String { mainTrack.idDisplay }
    var albumArtistText: String { mainTrack.albumArtistText }
    var composerText: String { mainTrack.composerText }
    var genreText: String { mainTrack.genreText }
    var yearSortValue: Int { mainTrack.yearSortValue }
    var trackNumberSortValue: Int { mainTrack.trackNumberSortValue }
    var discNumberSortValue: Int { mainTrack.discNumberSortValue }
    var bpmSortValue: Int { mainTrack.bpmSortValue }
    var isUrlSortValue: Int { mainTrack.isUrlSortValue }
    var timeMarkersCount: Int { mainTrack.timeMarkersCount }
    var waveformPointCount: Int { mainTrack.waveformPointCount }
    var generalTagsText: String { mainTrack.generalTagsText }
    var dateAddedSortValue: Int { mainTrack.dateAddedSortValue }
    var formattedDateAdded: String { mainTrack.formattedDateAdded }
    
    // Group-specific properties
    var isGroup: Bool { true }
    var trackCount: Int { allTracks.count }
    var isExpanded: Bool { group.isExpanded }
    
    // MARK: - Methods
    func withUpdates(_ updates: [String: Any]) -> GroupedTrack {
        let updatedMainTrack = mainTrack.withUpdates(updates)
        return GroupedTrack(group: group, mainTrack: updatedMainTrack, allTracks: allTracks)
    }
    
    func getTrackById(_ trackId: Int) -> Track? {
        return allTracks.first { $0.id == trackId }
    }
    
    func isMainTrack(_ track: Track) -> Bool {
        return track.id == group.mainTrackId
    }
}