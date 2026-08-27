import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var trackPaths: [String]
    let dateCreated: Date
    var dateModified: Date
    var folderId: String? // nil for root level playlists
    
    init(id: String = UUID().uuidString, name: String, trackPaths: [String] = [], folderId: String? = nil) {
        self.id = id
        self.name = name
        self.trackPaths = trackPaths
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
    
    mutating func addTrack(_ trackPath: String) {
        if !trackPaths.contains(trackPath) {
            trackPaths.append(trackPath)
            dateModified = Date()
        }
    }
    
    mutating func removeTrack(_ trackPath: String) {
        trackPaths.removeAll { $0 == trackPath }
        dateModified = Date()
    }
    
    mutating func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < trackPaths.count,
              destinationIndex >= 0 && destinationIndex < trackPaths.count else { return }
        
        let trackPath = trackPaths.remove(at: sourceIndex)
        trackPaths.insert(trackPath, at: destinationIndex)
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

