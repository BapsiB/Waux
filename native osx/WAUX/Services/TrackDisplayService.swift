import Foundation
import SwiftUI

// MARK: - TrackDisplayService
/// Service responsible for converting Track arrays to TrackDisplayItem arrays
/// and managing group display logic and filtering
class TrackDisplayService: ObservableObject {
    
    // MARK: - Private Properties
    private let trackGroupService: TrackGroupService
    
    // MARK: - Initialization
    init(trackGroupService: TrackGroupService) {
        self.trackGroupService = trackGroupService
    }
    
    // MARK: - Public Methods
    
    /// Converts an array of tracks to an array of TrackDisplayItems
    /// This is the main method that handles group membership detection and container creation
    /// - Parameter tracks: Array of tracks to convert
    /// - Returns: Array of TrackDisplayItems with proper grouping applied
    func convertTracksToDisplayItems(_ tracks: [Track]) -> [TrackDisplayItem] {
        var displayItems: [TrackDisplayItem] = []
        var processedTrackIds: Set<Int> = []
        
        for track in tracks {
            guard let trackId = track.id else {
                // Track without ID - treat as individual
                displayItems.append(.individual(track))
                continue
            }
            
            // Skip if already processed as part of a group
            if processedTrackIds.contains(trackId) {
                continue
            }
            
            // Check if track is part of a group
            if let group = trackGroupService.getGroupForTrack(trackId: trackId) {
                // Create container for the group
                if let groupedTrack = createGroupedTrack(for: group, from: tracks) {
                    displayItems.append(.container(groupedTrack))
                    
                    // If group is expanded, add group members
                    if group.isExpanded {
                        let groupMembers = createGroupMembers(for: group, from: tracks)
                        displayItems.append(contentsOf: groupMembers)
                    }
                    
                    // Mark all tracks in this group as processed
                    processedTrackIds.formUnion(group.trackIds)
                } else {
                    // Fallback: treat as individual if group creation fails
                    displayItems.append(.individual(track))
                    processedTrackIds.insert(trackId)
                }
            } else {
                // Track is not in any group - treat as individual
                displayItems.append(.individual(track))
                processedTrackIds.insert(trackId)
            }
        }
        
        return displayItems
    }
    
    /// Filters display items to show only container tracks when groups are collapsed
    /// - Parameter displayItems: Array of TrackDisplayItems to filter
    /// - Returns: Filtered array with collapsed groups showing only containers
    func filterCollapsedGroups(_ displayItems: [TrackDisplayItem]) -> [TrackDisplayItem] {
        var filteredItems: [TrackDisplayItem] = []
        var skipUntilNextContainer = false
        
        for item in displayItems {
            switch item {
            case .individual:
                // Always include individual tracks
                filteredItems.append(item)
                skipUntilNextContainer = false
                
            case .container(let groupedTrack):
                // Always include container tracks
                filteredItems.append(item)
                // Set flag to skip group members if group is collapsed
                skipUntilNextContainer = !groupedTrack.isExpanded
                
            case .groupMember:
                // Only include group members if we're not skipping them
                if !skipUntilNextContainer {
                    filteredItems.append(item)
                }
            }
        }
        
        return filteredItems
    }
    
    /// Toggles the expansion state of a group and returns updated display items
    /// - Parameters:
    ///   - groupId: ID of the group to toggle
    ///   - currentDisplayItems: Current array of display items
    /// - Returns: Updated array of display items with toggled expansion state
    func toggleGroupExpansion(groupId: String, currentDisplayItems: [TrackDisplayItem]) -> [TrackDisplayItem] {
        // Toggle the group expansion in the service
        trackGroupService.toggleGroupExpansion(groupId: groupId)
        
        // Find the updated group
        guard let updatedGroup = trackGroupService.groups.first(where: { $0.id == groupId }) else {
            return currentDisplayItems
        }
        
        var updatedItems: [TrackDisplayItem] = []
        var i = 0
        
        while i < currentDisplayItems.count {
            let item = currentDisplayItems[i]
            
            switch item {
            case .individual:
                updatedItems.append(item)
                i += 1
                
            case .container(let groupedTrack):
                if groupedTrack.group.id == groupId {
                    // Update the container with new expansion state
                    let updatedGroupedTrack = GroupedTrack(
                        group: updatedGroup,
                        mainTrack: groupedTrack.mainTrack,
                        allTracks: groupedTrack.allTracks
                    )
                    updatedItems.append(.container(updatedGroupedTrack))
                    
                    // Skip existing group members
                    i += 1
                    while i < currentDisplayItems.count {
                        if case .groupMember(_, let memberGroupId) = currentDisplayItems[i],
                           memberGroupId == groupId {
                            i += 1
                        } else {
                            break
                        }
                    }
                    
                    // Add group members if now expanded
                    if updatedGroup.isExpanded {
                        let groupMembers = createGroupMembers(for: updatedGroup, from: groupedTrack.allTracks)
                        updatedItems.append(contentsOf: groupMembers)
                    }
                } else {
                    updatedItems.append(item)
                    i += 1
                }
                
            case .groupMember:
                updatedItems.append(item)
                i += 1
            }
        }
        
        return updatedItems
    }
    
    /// Gets all tracks from display items (useful for operations that need the underlying tracks)
    /// - Parameter displayItems: Array of display items
    /// - Returns: Array of all tracks represented in the display items
    func getAllTracks(from displayItems: [TrackDisplayItem]) -> [Track] {
        var tracks: [Track] = []
        var addedTrackIds: Set<Int> = []
        
        for item in displayItems {
            let track = item.track
            if let trackId = track.id, !addedTrackIds.contains(trackId) {
                tracks.append(track)
                addedTrackIds.insert(trackId)
            } else if track.id == nil {
                // Track without ID - add it anyway
                tracks.append(track)
            }
        }
        
        return tracks
    }
    
    /// Gets tracks that should be included in selection operations
    /// - Parameter displayItems: Array of display items
    /// - Returns: Array of tracks that can be selected (excludes group members when group is collapsed)
    func getSelectableTracks(from displayItems: [TrackDisplayItem]) -> [Track] {
        let filteredItems = filterCollapsedGroups(displayItems)
        return filteredItems.map { $0.track }
    }
    
    // MARK: - Private Helper Methods
    
    /// Creates a GroupedTrack for a given group
    /// - Parameters:
    ///   - group: The TrackGroup to create a container for
    ///   - tracks: Array of all available tracks
    /// - Returns: GroupedTrack if successful, nil if main track not found
    private func createGroupedTrack(for group: TrackGroup, from tracks: [Track]) -> GroupedTrack? {
        // Find the main track
        guard let mainTrack = tracks.first(where: { $0.id == group.mainTrackId }) else {
            print("⚠️ [TrackDisplayService] Main track \(group.mainTrackId) not found for group \(group.id)")
            return nil
        }
        
        // Find all tracks in the group
        let allTracks = tracks.filter { track in
            guard let trackId = track.id else { return false }
            return group.trackIds.contains(trackId)
        }
        
        // Validate we have all expected tracks
        if allTracks.count != group.trackIds.count {
            print("⚠️ [TrackDisplayService] Expected \(group.trackIds.count) tracks for group \(group.id), found \(allTracks.count)")
            // If we don't have all tracks, we can't create a proper GroupedTrack
            // This could happen if some tracks were deleted but the group wasn't updated
            return nil
        }
        
        return GroupedTrack(group: group, mainTrack: mainTrack, allTracks: allTracks)
    }
    
    /// Creates group member display items for an expanded group
    /// - Parameters:
    ///   - group: The TrackGroup to create members for
    ///   - tracks: Array of all available tracks
    /// - Returns: Array of TrackDisplayItems for group members
    private func createGroupMembers(for group: TrackGroup, from tracks: [Track]) -> [TrackDisplayItem] {
        let groupTracks = tracks.filter { track in
            guard let trackId = track.id else { return false }
            return group.trackIds.contains(trackId)
        }
        
        // Sort group members with main track first
        let sortedGroupTracks = groupTracks.sorted { track1, track2 in
            if track1.id == group.mainTrackId { return true }
            if track2.id == group.mainTrackId { return false }
            return track1.title < track2.title
        }
        
        return sortedGroupTracks.map { track in
            .groupMember(track, groupId: group.id)
        }
    }
}

// MARK: - TrackDisplayItem Extensions
extension TrackDisplayItem {
    
    /// Returns the group ID if this item is part of a group, nil otherwise
    var associatedGroupId: String? {
        switch self {
        case .container(let groupedTrack):
            return groupedTrack.group.id
        case .groupMember(_, let groupId):
            return groupId
        case .individual:
            return nil
        }
    }
    
    /// Returns true if this item can be selected in the UI
    var isSelectable: Bool {
        // All items are selectable, but the UI may filter based on group expansion state
        return true
    }
    
    /// Returns a user-friendly description for debugging
    var debugDescription: String {
        switch self {
        case .individual(let track):
            return "Individual: \(track.title)"
        case .container(let groupedTrack):
            return "Container: \(groupedTrack.title) (\(groupedTrack.trackCount) tracks, expanded: \(groupedTrack.isExpanded))"
        case .groupMember(let track, let groupId):
            return "Member: \(track.title) (group: \(groupId))"
        }
    }
}