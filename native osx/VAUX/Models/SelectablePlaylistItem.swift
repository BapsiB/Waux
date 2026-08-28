import Foundation

// Protocol that both Playlist and PlaylistFolder can conform to for unified selection
protocol SelectablePlaylistItem: Identifiable, Hashable {
    var id: String { get }
    var name: String { get }
    var trackIds: [Int] { get }
    var duration: TimeInterval { get }
    var formattedDuration: String { get }
    var dateCreated: Date { get }
    var dateModified: Date { get }
    var isFolder: Bool { get }
}

// Extension to make Playlist conform to SelectablePlaylistItem
extension Playlist: SelectablePlaylistItem {
    var isFolder: Bool { false }
}

// Extension to make PlaylistFolder conform to SelectablePlaylistItem
extension PlaylistFolder: SelectablePlaylistItem {
    var trackIds: [Int] {
        // This will be computed by the PlaylistService based on all playlists in this folder
        // For now, return empty array - the service will provide the actual implementation
        return []
    }
    
    var duration: TimeInterval {
        // This will be computed by the PlaylistService based on all playlists in this folder
        // For now, return 0 - the service will provide the actual implementation
        return 0
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var isFolder: Bool { true }
}

// Enum to represent either a playlist or folder as a selectable item
enum SelectableItem: Equatable {
    case playlist(Playlist)
    case folder(PlaylistFolder)
    
    var id: String {
        switch self {
        case .playlist(let playlist):
            return playlist.id
        case .folder(let folder):
            return folder.id
        }
    }
    
    var name: String {
        switch self {
        case .playlist(let playlist):
            return playlist.name
        case .folder(let folder):
            return folder.name
        }
    }
    
    var isFolder: Bool {
        switch self {
        case .playlist:
            return false
        case .folder:
            return true
        }
    }
    
    var selectableItem: any SelectablePlaylistItem {
        switch self {
        case .playlist(let playlist):
            return playlist
        case .folder(let folder):
            return folder
        }
    }
}
