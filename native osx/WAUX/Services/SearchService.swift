import Foundation
import SwiftUI

class SearchService: ObservableObject {
    @Published var searchText: String = ""
    
    // Search options
    @Published var searchInTitle: Bool = true
    @Published var searchInArtist: Bool = true
    @Published var searchInAlbum: Bool = true
    @Published var searchInTags: Bool = true
    @Published var searchInComposer: Bool = true
    @Published var searchInGenre: Bool = true
    @Published var searchInComment: Bool = true
    @Published var searchInAlbumArtist: Bool = true
    
    // Function to check if a track matches the search criteria
    func trackMatchesSearch(_ track: Track) -> Bool {
        guard !searchText.isEmpty else { return true }
        
        let searchTerm = searchText.lowercased()
        
        // Check each enabled search field
        if searchInTitle && track.title.localizedCaseInsensitiveContains(searchTerm) {
            return true
        }
        
        if searchInArtist && track.artist.localizedCaseInsensitiveContains(searchTerm) {
            return true
        }
        
        if searchInAlbum && track.album.localizedCaseInsensitiveContains(searchTerm) {
            return true
        }
        
        if searchInTags && !track.generalTags.isEmpty {
            for tag in track.generalTags {
                if tag.localizedCaseInsensitiveContains(searchTerm) {
                    return true
                }
            }
        }
        
        if searchInComposer, let composer = track.composer, !composer.isEmpty {
            if composer.localizedCaseInsensitiveContains(searchTerm) {
                return true
            }
        }
        
        if searchInGenre, let genre = track.genre, !genre.isEmpty {
            if genre.localizedCaseInsensitiveContains(searchTerm) {
                return true
            }
        }
        
        if searchInComment && !track.comment.isEmpty {
            if track.comment.localizedCaseInsensitiveContains(searchTerm) {
                return true
            }
        }
        
        if searchInAlbumArtist, let albumArtist = track.albumArtist, !albumArtist.isEmpty {
            if albumArtist.localizedCaseInsensitiveContains(searchTerm) {
                return true
            }
        }
        
        return false
    }
    
    // Function to filter tracks based on search criteria
    func filterTracks(_ tracks: [Track]) -> [Track] {
        if searchText.isEmpty {
            return tracks
        }
        
        return tracks.filter { trackMatchesSearch($0) }
    }
    
    // Reset search
    func clearSearch() {
        searchText = ""
    }
    
    // Select all search options
    func selectAllSearchOptions() {
        searchInTitle = true
        searchInArtist = true
        searchInAlbum = true
        searchInTags = true
        searchInComposer = true
        searchInGenre = true
        searchInComment = true
        searchInAlbumArtist = true
    }
    
    // Clear all search options
    func clearAllSearchOptions() {
        searchInTitle = false
        searchInArtist = false
        searchInAlbum = false
        searchInTags = false
        searchInComposer = false
        searchInGenre = false
        searchInComment = false
        searchInAlbumArtist = false
    }
}
