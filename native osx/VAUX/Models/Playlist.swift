import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var trackIds: [Int]
    let dateCreated: Date
    var dateModified: Date
    var folderId: String? // nil for root level playlists
    
    init(id: String = UUID().uuidString, name: String, trackIds: [Int] = [], folderId: String? = nil) {
        self.id = id
        self.trackIds = trackIds
        self.name = name
        self.dateCreated = Date()
        self.dateModified = Date()
        self.folderId = folderId
    }
    
    // Computed property to get duration (would need to be calculated from actual tracks)
    var duration: TimeInterval {
        // This would need to be calculated from the actual track data
        // For now, return 0 as we don't have access to track durations here
        return 0
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    mutating func addTrack(_ trackId: Int) {
        if !trackIds.contains(trackId) {
            trackIds.append(trackId)
            dateModified = Date()
        }
    }
    
    mutating func removeTrack(_ trackId: Int) {
        trackIds.removeAll { $0 == trackId }
        dateModified = Date()
    }
    
    mutating func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < trackIds.count,
              destinationIndex >= 0 && destinationIndex < trackIds.count else { return }
        
        let trackId = trackIds.remove(at: sourceIndex)
        trackIds.insert(trackId, at: destinationIndex)
        dateModified = Date()
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        return lhs.id == rhs.id
    }
}
