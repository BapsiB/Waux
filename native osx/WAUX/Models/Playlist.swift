import Foundation

struct Playlist: Identifiable, Codable {
    let id = UUID()
    var name: String
    var tracks: [AudioTrack]
    let dateCreated: Date
    var dateModified: Date
    
    init(name: String, tracks: [AudioTrack] = []) {
        self.name = name
        self.tracks = tracks
        self.dateCreated = Date()
        self.dateModified = Date()
    }
    
    var duration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    mutating func addTrack(_ track: AudioTrack) {
        tracks.append(track)
        dateModified = Date()
    }
    
    mutating func removeTrack(at index: Int) {
        guard index >= 0 && index < tracks.count else { return }
        tracks.remove(at: index)
        dateModified = Date()
    }
    
    mutating func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < tracks.count,
              destinationIndex >= 0 && destinationIndex < tracks.count else { return }
        
        let track = tracks.remove(at: sourceIndex)
        tracks.insert(track, at: destinationIndex)
        dateModified = Date()
    }
}

