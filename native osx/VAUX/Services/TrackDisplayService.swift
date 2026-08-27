import Foundation
import SwiftUI

// MARK: - TrackDisplayService
/// Service responsible for converting Track arrays to TrackDisplayItem arrays
/// and managing group display logic and filtering
class TrackDisplayService: ObservableObject {
    
    // MARK: - Private Properties
    private let trackGroupService: TrackGroupService
    
    // MARK: - Performance Optimization Properties
    /// Cache for converted display items to avoid repeated conversions
    private var displayItemsCache: [String: [TrackDisplayItem]] = [:]
    /// Cache for track lookup by ID for faster access
    private var trackLookupCache: [Int: Track] = [:]
    /// Queue for cache operations
    private let cacheQueue = DispatchQueue(label: "com.vaux.trackdisplay.cache", qos: .userInitiated)
    /// Maximum cache size to prevent memory issues
    private let maxCacheSize = 10
    
    // MARK: - Initialization
    init(trackGroupService: TrackGroupService) {
        self.trackGroupService = trackGroupService
    }
    
    // MARK: - Public Methods
    
    /// Converts an array of tracks to an array of TrackDisplayItems with performance optimizations
    /// This is the main method that handles group membership detection and container creation
    /// - Parameter tracks: Array of tracks to convert
    /// - Returns: Array of TrackDisplayItems with proper grouping applied
    func convertTracksToDisplayItems(_ tracks: [Track]) -> [TrackDisplayItem] {
        // Create cache key based on track IDs and group states
        let cacheKey = createCacheKey(for: tracks)
        
        // Check cache first
        if let cachedItems = getCachedDisplayItems(for: cacheKey) {
            return cachedItems
        }
        
        // Build track lookup cache for faster access
        updateTrackLookupCache(with: tracks)
        
        // Use batch lookup for better performance with large collections
        let trackIds = tracks.compactMap { $0.id }
        let trackGroups = trackGroupService.getGroupsForTracks(trackIds)
        
        var displayItems: [TrackDisplayItem] = []
        var processedTrackIds: Set<Int> = []
        
        // Process tracks in batches for better performance
        let batchSize = 100
        for batchStart in stride(from: 0, to: tracks.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, tracks.count)
            let batch = Array(tracks[batchStart..<batchEnd])
            
            let batchItems = processBatch(batch, trackGroups: trackGroups, processedTrackIds: &processedTrackIds)
            displayItems.append(contentsOf: batchItems)
        }
        
        // Cache the result
        cacheDisplayItems(displayItems, for: cacheKey)
        
        return displayItems
    }
    
    /// Processes a batch of tracks for conversion to display items
    private func processBatch(_ tracks: [Track], trackGroups: [Int: TrackGroup], processedTrackIds: inout Set<Int>) -> [TrackDisplayItem] {
        var batchItems: [TrackDisplayItem] = []
        
        for track in tracks {
            guard let trackId = track.id else {
                // Track without ID - treat as individual
                batchItems.append(.individual(track))
                continue
            }
            
            // Skip if already processed as part of a group
            if processedTrackIds.contains(trackId) {
                continue
            }
            
            // Check if track is part of a group using batch lookup
            if let group = trackGroups[trackId] {
                // Create container for the group
                if let groupedTrack = createGroupedTrackOptimized(for: group) {
                    batchItems.append(.container(groupedTrack))
                    
                    // If group is expanded, add group members
                    if group.isExpanded {
                        let groupMembers = createGroupMembersOptimized(for: group)
                        batchItems.append(contentsOf: groupMembers)
                    }
                    
                    // Mark all tracks in this group as processed
                    processedTrackIds.formUnion(group.trackIds)
                } else {
                    // Fallback: treat as individual if group creation fails
                    batchItems.append(.individual(track))
                    processedTrackIds.insert(trackId)
                }
            } else {
                // Track is not in any group - treat as individual
                batchItems.append(.individual(track))
                processedTrackIds.insert(trackId)
            }
        }
        
        return batchItems
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
        
        // Clear cache since group state changed
        clearCache()
        
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
    
    /// Lazy loading version of convertTracksToDisplayItems for large collections
    /// Returns a subset of display items for initial rendering, with ability to load more
    /// - Parameters:
    ///   - tracks: Array of tracks to convert
    ///   - startIndex: Starting index for the subset
    ///   - count: Number of items to return
    /// - Returns: Tuple containing display items and whether there are more items available
    func convertTracksToDisplayItemsLazy(_ tracks: [Track], startIndex: Int = 0, count: Int = 100) -> (items: [TrackDisplayItem], hasMore: Bool) {
        let endIndex = min(startIndex + count, tracks.count)
        let subset = Array(tracks[startIndex..<endIndex])
        
        let displayItems = convertTracksToDisplayItems(subset)
        let hasMore = endIndex < tracks.count
        
        return (displayItems, hasMore)
    }
    
    /// Optimized method for checking if any tracks in a collection are grouped
    /// Useful for UI decisions about whether to show group-related controls
    /// - Parameter tracks: Array of tracks to check
    /// - Returns: True if any tracks are in groups, false otherwise
    func hasGroupedTracks(in tracks: [Track]) -> Bool {
        let trackIds = tracks.compactMap { $0.id }
        
        // Use batch lookup for efficiency
        let trackGroups = trackGroupService.getGroupsForTracks(trackIds)
        return !trackGroups.isEmpty
    }
    
    /// Gets statistics about grouping in a collection for UI display
    /// - Parameter tracks: Array of tracks to analyze
    /// - Returns: Tuple with group count, grouped track count, and ungrouped track count
    func getGroupingStatistics(for tracks: [Track]) -> (groupCount: Int, groupedTrackCount: Int, ungroupedTrackCount: Int) {
        let trackIds = tracks.compactMap { $0.id }
        let trackGroups = trackGroupService.getGroupsForTracks(trackIds)
        
        let groupedTrackIds = Set(trackGroups.keys)
        let groupedTrackCount = groupedTrackIds.count
        let ungroupedTrackCount = trackIds.count - groupedTrackCount
        
        // Count unique groups
        let uniqueGroups = Set(trackGroups.values.map { $0.id })
        let groupCount = uniqueGroups.count
        
        return (groupCount, groupedTrackCount, ungroupedTrackCount)
    }
    
    /// Gets tracks that should be included in selection operations
    /// - Parameter displayItems: Array of display items
    /// - Returns: Array of tracks that can be selected (excludes group members when group is collapsed)
    func getSelectableTracks(from displayItems: [TrackDisplayItem]) -> [Track] {
        let filteredItems = filterCollapsedGroups(displayItems)
        return filteredItems.map { $0.track }
    }
    
    // MARK: - Cache Management Methods
    
    /// Creates a cache key for a set of tracks
    private func createCacheKey(for tracks: [Track]) -> String {
        let trackIds = tracks.compactMap { $0.id }.sorted()
        let groupStates = trackGroupService.groups.map { "\($0.id):\($0.isExpanded)" }.sorted()
        return "\(trackIds.hashValue)_\(groupStates.joined(separator: ","))"
    }
    
    /// Gets cached display items if available
    private func getCachedDisplayItems(for key: String) -> [TrackDisplayItem]? {
        return cacheQueue.sync {
            return displayItemsCache[key]
        }
    }
    
    /// Caches display items with size management
    private func cacheDisplayItems(_ items: [TrackDisplayItem], for key: String) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Manage cache size
            if self.displayItemsCache.count >= self.maxCacheSize {
                // Remove oldest entries (simple FIFO)
                let keysToRemove = Array(self.displayItemsCache.keys.prefix(self.maxCacheSize / 2))
                for keyToRemove in keysToRemove {
                    self.displayItemsCache.removeValue(forKey: keyToRemove)
                }
            }
            
            self.displayItemsCache[key] = items
        }
    }
    
    /// Updates the track lookup cache for faster access
    private func updateTrackLookupCache(with tracks: [Track]) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.trackLookupCache.removeAll()
            for track in tracks {
                if let trackId = track.id {
                    self.trackLookupCache[trackId] = track
                }
            }
        }
    }
    
    /// Clears all caches (call when groups are modified)
    func clearCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            self.displayItemsCache.removeAll()
            self.trackLookupCache.removeAll()
        }
    }
    
    // MARK: - Optimized Helper Methods
    
    /// Creates a GroupedTrack using cached track lookup for better performance
    private func createGroupedTrackOptimized(for group: TrackGroup) -> GroupedTrack? {
        return cacheQueue.sync {
            // Find the main track using cache
            guard let mainTrack = trackLookupCache[group.mainTrackId] else {
                print("⚠️ [TrackDisplayService] Main track \(group.mainTrackId) not found in cache for group \(group.id)")
                return nil
            }
            
            // Find all tracks in the group using cache
            var allTracks: [Track] = []
            for trackId in group.trackIds {
                if let track = trackLookupCache[trackId] {
                    allTracks.append(track)
                }
            }
            
            // Validate we have all expected tracks
            if allTracks.count != group.trackIds.count {
                print("⚠️ [TrackDisplayService] Expected \(group.trackIds.count) tracks for group \(group.id), found \(allTracks.count)")
                return nil
            }
            
            return GroupedTrack(group: group, mainTrack: mainTrack, allTracks: allTracks)
        }
    }
    
    /// Creates group member display items using cached track lookup
    private func createGroupMembersOptimized(for group: TrackGroup) -> [TrackDisplayItem] {
        return cacheQueue.sync {
            var groupTracks: [Track] = []
            
            // Use cache for faster lookup
            for trackId in group.trackIds {
                if let track = trackLookupCache[trackId] {
                    groupTracks.append(track)
                }
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
    
    // MARK: - Legacy Helper Methods (for backward compatibility)
    
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