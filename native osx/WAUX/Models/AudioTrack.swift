import Foundation

struct AudioTrack: Identifiable, Codable {
    let id = UUID()
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval
    let url: URL
    let fileSize: Int64?
    let dateAdded: Date
    
    init(title: String, artist: String? = nil, album: String? = nil, duration: TimeInterval, url: URL, fileSize: Int64? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.url = url
        self.fileSize = fileSize
        self.dateAdded = Date()
    }
    
    var displayTitle: String {
        if let artist = artist, !artist.isEmpty {
            return "\(title) - \(artist)"
        }
        return title
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

