import SwiftUI

struct FolderErrorHandler {
    static func userFriendlyMessage(for error: Error) -> String {
        if let playlistError = error as? PlaylistError {
            switch playlistError {
            case .noActiveCollection:
                return "No music collection is currently active. Please open a collection first."
            case .queryFailed(let message):
                return "Database operation failed: \(message)"
            case .invalidName:
                return "Please enter a valid folder name."
            case .folderNotFound:
                return "The folder could not be found. It may have been deleted."
            case .circularReference:
                return "Cannot move folder: this would create a circular reference."
            case .maxDepthExceeded:
                return "Cannot create folder: maximum nesting depth (10 levels) would be exceeded."
            case .folderNotEmpty:
                return "Cannot delete folder: folder contains playlists or subfolders."
            }
        }
        
        return error.localizedDescription
    }
    
    static func shouldShowConfirmation(for error: Error) -> Bool {
        if let playlistError = error as? PlaylistError {
            switch playlistError {
            case .folderNotEmpty:
                return true
            default:
                return false
            }
        }
        return false
    }
}