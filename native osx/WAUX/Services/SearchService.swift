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
    
    // Function to filter display items based on search criteria
    // This ensures that grouped tracks are handled properly during search
    func filterDisplayItems(_ displayItems: [TrackDisplayItem]) -> [TrackDisplayItem] {
        if searchText.isEmpty {
            return displayItems
        }
        
        var filteredItems: [TrackDisplayItem] = []
        var processedGroupIds: Set<String> = []
        
        for item in displayItems {
            switch item {
            case .individual(let track):
                // Individual tracks: include if they match search
                if trackMatchesSearch(track) {
                    filteredItems.append(item)
                }
                
            case .container(let groupedTrack):
                // Container tracks: include if any track in the group matches search
                let groupMatches = groupedTrack.allTracks.contains { trackMatchesSearch($0) }
                if groupMatches {
                    filteredItems.append(item)
                    processedGroupIds.insert(groupedTrack.group.id)
                }
                
            case .groupMember(let track, let groupId):
                // Group members: only include if their container wasn't already included
                // and they match the search criteria
                if !processedGroupIds.contains(groupId) && trackMatchesSearch(track) {
                    filteredItems.append(item)
                }
            }
        }
        
        return filteredItems
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
