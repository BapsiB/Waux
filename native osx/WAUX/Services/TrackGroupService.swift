import Foundation
import SwiftUI
import SQLite3
import Combine

// MARK: - TrackGroupService Errors
enum TrackGroupError: LocalizedError {
    case insufficientTracks
    case trackNotFound(Int)
    case groupNotFound(String)
    case trackAlreadyInGroup(Int, String)
    case mainTrackNotInGroup(Int, String)
    case cannotRemoveMainTrack(Int)
    case cannotRemoveLastTracks
    case databaseError(String)
    case invalidTrackIds([Int])
    case groupDissolutionFailed(String)
    case mainTrackReassignmentFailed(String)
    case corruptedGroupData(String, String) // groupId, reason
    case validationFailed(String)
    case operationRollbackFailed(String)
    case trackExistenceValidationFailed([Int])
    case groupNameTooLong(String)
    case duplicateGroupName(String)
    case circularGroupReference(String)
    case concurrentModificationDetected(String)
    case databaseConnectionLost
    case transactionTimeout
    case foreignKeyConstraintViolation(String)
    case dataIntegrityViolation(String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientTracks:
            return "At least 2 tracks are required to create a group"
        case .trackNotFound(let id):
            return "Track with ID \(id) not found"
        case .groupNotFound(let id):
            return "Group with ID \(id) not found"
        case .trackAlreadyInGroup(let trackId, let groupId):
            return "Track \(trackId) is already in group \(groupId)"
        case .mainTrackNotInGroup(let trackId, let groupId):
            return "Track \(trackId) is not in group \(groupId) and cannot be set as main track"
        case .cannotRemoveMainTrack(let trackId):
            return "Cannot remove main track \(trackId) directly. Set a different main track first."
        case .cannotRemoveLastTracks:
            return "Cannot remove tracks when only 2 remain in group. Ungroup instead."
        case .databaseError(let message):
            return "Database error: \(message)"
        case .invalidTrackIds(let ids):
            return "Invalid track IDs: \(ids)"
        case .groupDissolutionFailed(let reason):
            return "Failed to dissolve group: \(reason)"
        case .mainTrackReassignmentFailed(let reason):
            return "Failed to reassign main track: \(reason)"
        case .corruptedGroupData(let groupId, let reason):
            return "Corrupted data detected for group \(groupId): \(reason)"
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        case .operationRollbackFailed(let reason):
            return "Failed to rollback operation: \(reason)"
        case .trackExistenceValidationFailed(let trackIds):
            return "Tracks do not exist in database: \(trackIds)"
        case .groupNameTooLong(let name):
            return "Group name is too long (max 255 characters): '\(name)'"
        case .duplicateGroupName(let name):
            return "A group with the name '\(name)' already exists"
        case .circularGroupReference(let groupId):
            return "Circular reference detected in group \(groupId)"
        case .concurrentModificationDetected(let groupId):
            return "Group \(groupId) was modified by another process"
        case .databaseConnectionLost:
            return "Database connection was lost"
        case .transactionTimeout:
            return "Database transaction timed out"
        case .foreignKeyConstraintViolation(let details):
            return "Foreign key constraint violation: \(details)"
        case .dataIntegrityViolation(let details):
            return "Data integrity violation: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .insufficientTracks:
            return "Select at least 2 tracks to create a group"
        case .trackNotFound:
            return "Refresh the track list and try again"
        case .groupNotFound:
            return "The group may have been deleted. Refresh the view and try again"
        case .trackAlreadyInGroup:
            return "Remove the track from its current group first, or add it to a different group"
        case .mainTrackNotInGroup:
            return "Select a track that is already in the group"
        case .databaseError, .databaseConnectionLost:
            return "Check database connection and try again"
        case .corruptedGroupData:
            return "The group data may be corrupted. Try refreshing the view or recreating the group"
        case .trackExistenceValidationFailed:
            return "Some tracks may have been deleted. Refresh the track list and try again"
        case .groupNameTooLong:
            return "Use a shorter name for the group (255 characters maximum)"
        case .duplicateGroupName:
            return "Choose a different name for the group"
        case .concurrentModificationDetected:
            return "Another process modified this group. Refresh and try again"
        case .transactionTimeout:
            return "The operation took too long. Try again with fewer tracks"
        default:
            return "Try the operation again. If the problem persists, restart the application"
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .insufficientTracks, .trackAlreadyInGroup, .mainTrackNotInGroup, 
             .groupNameTooLong, .duplicateGroupName, .trackExistenceValidationFailed:
            return true
        case .databaseConnectionLost, .corruptedGroupData, .dataIntegrityViolation:
            return false
        default:
            return true
        }
    }
}

// MARK: - TrackGroupService
class TrackGroupService: ObservableObject {
    // MARK: - Published Properties
    @Published var groups: [TrackGroup] = []
    
    // MARK: - Private Properties
    private var database: OpaquePointer?
    private let databaseQueue = DispatchQueue(label: "com.waux.trackgroup.database", qos: .userInitiated)
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    // MARK: - Performance Optimization Properties
    /// Cache for fast group membership lookups - maps track ID to group ID
    private var trackToGroupCache: [Int: String] = [:]
    /// Cache for group lookup by ID
    private var groupCache: [String: TrackGroup] = [:]
    /// Queue for cache operations to ensure thread safety
    private let cacheQueue = DispatchQueue(label: "com.waux.trackgroup.cache", qos: .userInitiated)
    /// Flag to track if caches are valid
    private var cacheValid = false
    
    // MARK: - Database Table Names
    private let tableTrackGroups = "track_groups"
    private let tableTrackGroupMembers = "track_group_members"
    
    // MARK: - Prepared Statement Cache
    private var preparedStatements: [String: OpaquePointer?] = [:]
    private let statementCacheQueue = DispatchQueue(label: "com.waux.trackgroup.statements", qos: .userInitiated)
    
    // MARK: - Initialization
    init() {
        print("TrackGroupService initialized")
    }
    
    // MARK: - Database Setup
    func setDatabase(_ database: OpaquePointer?) {
        self.database = database
        // Clear prepared statements when database changes
        clearPreparedStatements()
    }
    
    // MARK: - Prepared Statement Management
    
    /// Gets or creates a prepared statement for the given SQL
    private func getPreparedStatement(for sql: String, key: String) -> OpaquePointer? {
        return statementCacheQueue.sync {
            if let statement = preparedStatements[key] {
                return statement
            }
            
            guard let database = database else { return nil }
            
            var statement: OpaquePointer?
            let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            
            if result == SQLITE_OK {
                preparedStatements[key] = statement
                return statement
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                print("⚠️ Failed to prepare statement '\(key)': \(errorMessage)")
                return nil
            }
        }
    }
    
    /// Clears all prepared statements
    private func clearPreparedStatements() {
        statementCacheQueue.sync {
            for (_, statement) in preparedStatements {
                if let stmt = statement {
                    sqlite3_finalize(stmt)
                }
            }
            preparedStatements.removeAll()
        }
    }
    
    deinit {
        clearPreparedStatements()
    }
    
    // MARK: - Group Management Operations
    
    /// Creates a new track group with validation for minimum track count
    /// - Parameters:
    ///   - trackIds: Array of track IDs to group (minimum 2 required)
    ///   - name: Optional name for the group
    ///   - mainTrackId: Optional main track ID (defaults to first track)
    /// - Returns: Created TrackGroup
    /// - Throws: TrackGroupError for validation failures or database errors
    func createGroup(trackIds: [Int], name: String? = nil, mainTrackId: Int? = nil) async throws -> TrackGroup {
        // Validate database connection
        try validateDatabaseConnection()
        
        // Store original state for rollback
        let originalGroups = groups
        
        do {
            // Validation: minimum track count
            guard trackIds.count >= 2 else {
                throw TrackGroupError.insufficientTracks
            }
            
            // Remove duplicates and convert to Set
            let uniqueTrackIds = Set(trackIds)
            guard uniqueTrackIds.count >= 2 else {
                throw TrackGroupError.insufficientTracks
            }
            
            // Validate group name if provided
            let groupName = name ?? ""
            try validateGroupName(groupName)
            
            // Validate all tracks exist and are not already in groups
            try await validateTracksExistAndNotGrouped(Array(uniqueTrackIds))
            
            // Determine main track
            let selectedMainTrackId = mainTrackId ?? trackIds.first!
            guard uniqueTrackIds.contains(selectedMainTrackId) else {
                throw TrackGroupError.mainTrackNotInGroup(selectedMainTrackId, "new group")
            }
            
            // Create group
            let group = TrackGroup(
                trackIds: uniqueTrackIds,
                mainTrackId: selectedMainTrackId,
                name: groupName
            )
            
            // Validate group integrity
            try validateGroupIntegrity(group)
            
            // Persist to database with transaction
            try await saveGroupToDatabase(group)
            
            // Update local state
            await MainActor.run { [weak self] in
                self?.groups.append(group)
            }
            
            // Update cache
            updateCacheForGroup(group)
            
            print("✅ Created group '\(group.displayName)' with \(group.trackCount) tracks")
            return group
            
        } catch {
            // Perform rollback on failure
            do {
                try await performRollback(operation: "createGroup", groupId: nil, originalState: originalGroups)
            } catch let rollbackError {
                print("❌ Rollback failed for createGroup: \(rollbackError.localizedDescription)")
            }
            
            // Re-throw original error
            throw error
        }
    }
    
    /// Deletes a track group with proper cleanup of member relationships
    /// - Parameter groupId: ID of the group to delete
    /// - Throws: TrackGroupError if group not found or database error
    func deleteGroup(groupId: String) async throws {
        // Validate database connection
        try validateDatabaseConnection()
        
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else {
            throw TrackGroupError.groupNotFound(groupId)
        }
        
        let group = groups[groupIndex]
        let originalGroups = groups
        
        do {
            // Delete from database with transaction
            try await deleteGroupFromDatabase(groupId)
            
            // Update local state
            await MainActor.run { [weak self] in
                self?.groups.remove(at: groupIndex)
            }
            
            // Update cache
            removeCacheForGroup(groupId)
            
            print("✅ Deleted group '\(group.displayName)' with \(group.trackCount) tracks")
            
        } catch {
            // Perform rollback on failure
            do {
                try await performRollback(operation: "deleteGroup", groupId: groupId, originalState: originalGroups)
            } catch let rollbackError {
                print("❌ Rollback failed for deleteGroup: \(rollbackError.localizedDescription)")
            }
            
            throw error
        }
    }
    
    /// Adds tracks to an existing group
    /// - Parameters:
    ///   - groupId: ID of the target group
    ///   - trackIds: Array of track IDs to add
    /// - Throws: TrackGroupError for validation failures or database errors
    func addTracksToGroup(groupId: String, trackIds: [Int]) async throws {
        // Validate database connection
        try validateDatabaseConnection()
        
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else {
            throw TrackGroupError.groupNotFound(groupId)
        }
        
        let originalGroups = groups
        var group = groups[groupIndex]
        let originalTrackIds = group.trackIds
        
        do {
            // Validate input
            guard !trackIds.isEmpty else {
                throw TrackGroupError.validationFailed("No tracks provided to add")
            }
            
            // Validate tracks exist and are not already in groups
            try await validateTracksExistAndNotGrouped(trackIds)
            
            // Add tracks to group
            for trackId in trackIds {
                group.addTrack(trackId)
            }
            
            // Validate updated group integrity
            try validateGroupIntegrity(group)
            
            // Update database with transaction
            try await updateGroupInDatabase(group)
            
            // Update local state
            await MainActor.run { [weak self] in
                self?.groups[groupIndex] = group
            }
            
            // Update cache
            updateCacheForGroup(group)
            
            let addedCount = group.trackIds.count - originalTrackIds.count
            print("✅ Added \(addedCount) tracks to group '\(group.displayName)'")
            
        } catch {
            // Perform rollback on failure
            do {
                try await performRollback(operation: "addTracksToGroup", groupId: groupId, originalState: originalGroups)
            } catch let rollbackError {
                print("❌ Rollback failed for addTracksToGroup: \(rollbackError.localizedDescription)")
            }
            
            throw error
        }
    }
    
    /// Removes a track from a group with automatic cleanup and main track reassignment
    /// - Parameters:
    ///   - groupId: ID of the group
    ///   - trackId: ID of the track to remove
    /// - Throws: TrackGroupError for validation failures or database errors
    func removeTrackFromGroup(groupId: String, trackId: Int) async throws {
        // Validate database connection
        try validateDatabaseConnection()
        
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else {
            throw TrackGroupError.groupNotFound(groupId)
        }
        
        let originalGroups = groups
        var group = groups[groupIndex]
        
        do {
            // Validate removal
            guard group.contains(trackId) else {
                throw TrackGroupError.trackNotFound(trackId)
            }
            
            // Validate track ID
            try validateTrackIds([trackId])
            
            // Special handling for removing main track - reassign main track first
            if trackId == group.mainTrackId {
                // If only 2 tracks left, removing main track will dissolve the group
                if group.trackCount <= 2 {
                    try await dissolveGroup(groupId: groupId)
                    return
                }
                try await handleMainTrackRemoval(group: &group, trackIdToRemove: trackId)
            }
            
            // Remove track
            let success = group.removeTrack(trackId)
            guard success else {
                throw TrackGroupError.cannotRemoveLastTracks
            }
            
            // Check if group should be dissolved (only 1 track left)
            if group.trackCount <= 1 {
                try await dissolveGroup(groupId: groupId)
                return
            }
            
            // Validate updated group integrity
            try validateGroupIntegrity(group)
            
            // Update database with transaction
            try await updateGroupInDatabase(group)
            
            // Update local state
            await MainActor.run { [weak self] in
                self?.groups[groupIndex] = group
            }
            
            // Update cache
            updateCacheForGroup(group)
            
            print("✅ Removed track \(trackId) from group '\(group.displayName)'")
            
        } catch {
            // Attempt recovery for corrupted group data
            if case TrackGroupError.corruptedGroupData = error {
                do {
                    try await recoverFromCorruptedGroup(groupId, error: error as! TrackGroupError)
                    return
                } catch {
                    print("❌ Failed to recover from corrupted group: \(error.localizedDescription)")
                }
            }
            
            // Perform rollback on failure
            do {
                try await performRollback(operation: "removeTrackFromGroup", groupId: groupId, originalState: originalGroups)
            } catch let rollbackError {
                print("❌ Rollback failed for removeTrackFromGroup: \(rollbackError.localizedDescription)")
            }
            
            throw error
        }
    }
    
    /// Sets the main track for a group with validation and persistence
    /// - Parameters:
    ///   - groupId: ID of the group
    ///   - trackId: ID of the track to set as main
    /// - Throws: TrackGroupError for validation failures or database errors
    func setMainTrack(groupId: String, trackId: Int) async throws {
        // Validate database connection
        try validateDatabaseConnection()
        
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else {
            throw TrackGroupError.groupNotFound(groupId)
        }
        
        let originalGroups = groups
        var group = groups[groupIndex]
        let originalMainTrackId = group.mainTrackId
        
        do {
            // Validate track ID
            try validateTrackIds([trackId])
            
            // Validate track is in group
            guard group.contains(trackId) else {
                throw TrackGroupError.mainTrackNotInGroup(trackId, groupId)
            }
            
            // Check if already main track (no-op)
            if group.mainTrackId == trackId {
                print("ℹ️ Track \(trackId) is already the main track for group '\(group.displayName)'")
                return
            }
            
            // Set main track
            let success = group.setMainTrack(trackId)
            guard success else {
                throw TrackGroupError.mainTrackNotInGroup(trackId, groupId)
            }
            
            // Validate updated group integrity
            try validateGroupIntegrity(group)
            
            // Update database with transaction
            try await updateGroupMainTrackInDatabase(groupId: groupId, mainTrackId: trackId)
            
            // Update local state
            await MainActor.run { [weak self] in
                self?.groups[groupIndex] = group
            }
            
            // Update cache
            updateCacheForGroup(group)
            
            print("✅ Set track \(trackId) as main track for group '\(group.displayName)' (was \(originalMainTrackId))")
            
        } catch {
            // Perform rollback on failure
            do {
                try await performRollback(operation: "setMainTrack", groupId: groupId, originalState: originalGroups)
            } catch let rollbackError {
                print("❌ Rollback failed for setMainTrack: \(rollbackError.localizedDescription)")
            }
            
            throw error
        }
    }
    
    /// Ungroups all tracks in a group, separating them back into individual tracks
    /// - Parameter groupId: ID of the group to ungroup
    /// - Throws: TrackGroupError if group not found or database error
    func ungroupTracks(groupId: String) async throws {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else {
            throw TrackGroupError.groupNotFound(groupId)
        }
        
        let group = groups[groupIndex]
        print("Ungrouping tracks from group '\(group.displayName)' with \(group.trackCount) tracks")
        
        // Delete group from database (this will cascade delete all member relationships)
        try await deleteGroupFromDatabase(groupId)
        
        // Update local state
        await MainActor.run { [weak self] in
            self?.groups.remove(at: groupIndex)
        }
        
        // Update cache
        removeCacheForGroup(groupId)
        
        print("Successfully ungrouped \(group.trackCount) tracks from group '\(group.displayName)'")
    }
    
    /// Toggles the expansion state of a group
    /// - Parameter groupId: ID of the group to toggle
    func toggleGroupExpansion(groupId: String) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else {
            return
        }
        
        groups[groupIndex].isExpanded.toggle()
        let newExpansionState = groups[groupIndex].isExpanded
        
        // Persist expansion state
        Task {
            try? await updateGroupExpansionInDatabase(
                groupId: groupId,
                isExpanded: newExpansionState
            )
        }
    }
    
    /// Efficient lookup method for group membership queries with caching
    /// - Parameter trackId: ID of the track to find
    /// - Returns: TrackGroup if track is in a group, nil otherwise
    func getGroupForTrack(trackId: Int) -> TrackGroup? {
        return cacheQueue.sync {
            // Ensure cache is valid
            if !cacheValid {
                rebuildCache()
            }
            
            // Fast cache lookup
            guard let groupId = trackToGroupCache[trackId] else {
                return nil
            }
            
            return groupCache[groupId]
        }
    }
    
    /// Batch lookup for multiple tracks - more efficient than individual lookups
    /// - Parameter trackIds: Array of track IDs to find groups for
    /// - Returns: Dictionary mapping track ID to TrackGroup (only includes tracks that are in groups)
    func getGroupsForTracks(_ trackIds: [Int]) -> [Int: TrackGroup] {
        return cacheQueue.sync {
            // Ensure cache is valid
            if !cacheValid {
                rebuildCache()
            }
            
            var result: [Int: TrackGroup] = [:]
            for trackId in trackIds {
                if let groupId = trackToGroupCache[trackId],
                   let group = groupCache[groupId] {
                    result[trackId] = group
                }
            }
            return result
        }
    }
    
    /// Checks if a track is in any group (faster than getGroupForTrack when you only need boolean result)
    /// - Parameter trackId: ID of the track to check
    /// - Returns: True if track is in a group, false otherwise
    func isTrackInGroup(trackId: Int) -> Bool {
        return cacheQueue.sync {
            // Ensure cache is valid
            if !cacheValid {
                rebuildCache()
            }
            
            return trackToGroupCache[trackId] != nil
        }
    }
    
    /// Gets all tracks that are not in any group (optimized version)
    /// - Parameter allTracks: Array of all tracks
    /// - Returns: Array of tracks not in groups
    func getUngroupedTracks(from allTracks: [Track]) -> [Track] {
        return cacheQueue.sync {
            // Ensure cache is valid
            if !cacheValid {
                rebuildCache()
            }
            
            return allTracks.filter { track in
                guard let trackId = track.id else { return true }
                return trackToGroupCache[trackId] == nil
            }
        }
    }
    
    /// Optimized method to get all grouped track IDs
    /// - Returns: Set of all track IDs that are in groups
    func getAllGroupedTrackIds() -> Set<Int> {
        return cacheQueue.sync {
            // Ensure cache is valid
            if !cacheValid {
                rebuildCache()
            }
            
            return Set(trackToGroupCache.keys)
        }
    }
    
    /// Gets performance statistics for monitoring
    /// - Returns: Dictionary with performance metrics
    func getPerformanceStatistics() -> [String: Any] {
        return cacheQueue.sync {
            return [
                "totalGroups": groups.count,
                "totalGroupedTracks": trackToGroupCache.count,
                "cacheValid": cacheValid,
                "averageTracksPerGroup": groups.isEmpty ? 0 : Double(trackToGroupCache.count) / Double(groups.count),
                "expandedGroups": groups.filter { $0.isExpanded }.count
            ]
        }
    }
    
    /// Loads all groups from database with data validation and error recovery
    func loadGroups() async throws {
        // Validate database connection
        try validateDatabaseConnection()
        
        do {
            let loadedGroups = try await loadGroupsFromDatabase()
            
            // Validate and filter corrupted groups
            var validGroups: [TrackGroup] = []
            var corruptedGroupIds: [String] = []
            
            for group in loadedGroups {
                do {
                    try validateGroupIntegrity(group)
                    validGroups.append(group)
                } catch {
                    print("⚠️ Corrupted group detected: \(group.id) - \(error.localizedDescription)")
                    corruptedGroupIds.append(group.id)
                    
                    // Attempt recovery
                    do {
                        try await recoverFromCorruptedGroup(group.id, error: error as? TrackGroupError ?? TrackGroupError.corruptedGroupData(group.id, "Unknown corruption"))
                        
                        // Try to reload the recovered group
                        try await reloadGroupFromDatabase(group.id)
                        if let recoveredGroup = groups.first(where: { $0.id == group.id }) {
                            try validateGroupIntegrity(recoveredGroup)
                            validGroups.append(recoveredGroup)
                            print("✅ Successfully recovered group: \(group.id)")
                        }
                    } catch {
                        print("❌ Failed to recover corrupted group \(group.id): \(error.localizedDescription)")
                    }
                }
            }
            
            await MainActor.run { [weak self] in
                self?.groups = validGroups
            }
            
            // Invalidate cache to force rebuild on next access
            invalidateCache()
            
            let message = "✅ Loaded \(validGroups.count) track groups from database"
            if !corruptedGroupIds.isEmpty {
                print("\(message) (\(corruptedGroupIds.count) corrupted groups handled)")
            } else {
                print(message)
            }
            
        } catch {
            print("❌ Failed to load groups from database: \(error.localizedDescription)")
            
            // Clear groups on load failure to prevent inconsistent state
            await MainActor.run { [weak self] in
                self?.groups = []
            }
            
            throw error
        }
    }
    
    // MARK: - Group Cleanup and Dissolution Methods
    
    /// Handles removal of main track by automatically reassigning to another track
    /// - Parameters:
    ///   - group: The group to modify (passed by reference)
    ///   - trackIdToRemove: The main track ID being removed
    /// - Throws: TrackGroupError if no suitable replacement track found
    private func handleMainTrackRemoval(group: inout TrackGroup, trackIdToRemove: Int) async throws {
        // Find a suitable replacement main track (any track except the one being removed)
        let remainingTrackIds = group.trackIds.filter { $0 != trackIdToRemove }
        
        guard let newMainTrackId = remainingTrackIds.first else {
            throw TrackGroupError.mainTrackReassignmentFailed("No suitable replacement main track found in group '\(group.displayName)'")
        }
        
        // Set new main track
        let success = group.setMainTrack(newMainTrackId)
        guard success else {
            throw TrackGroupError.mainTrackReassignmentFailed("Failed to set track \(newMainTrackId) as main track in group '\(group.displayName)'")
        }
        
        print("Automatically reassigned main track from \(trackIdToRemove) to \(newMainTrackId) in group '\(group.displayName)'")
    }
    
    /// Dissolves a group when it has only one track remaining
    /// - Parameter groupId: ID of the group to dissolve
    /// - Throws: TrackGroupError for database errors
    private func dissolveGroup(groupId: String) async throws {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else {
            throw TrackGroupError.groupNotFound(groupId)
        }
        
        let group = groups[groupIndex]
        print("Automatically dissolving group '\(group.displayName)' - only \(group.trackCount) track(s) remaining")
        
        // Delete from database with error handling
        do {
            try await deleteGroupFromDatabase(groupId)
        } catch {
            throw TrackGroupError.groupDissolutionFailed("Failed to delete group '\(group.displayName)' from database: \(error.localizedDescription)")
        }
        
        // Update local state
        await MainActor.run { [weak self] in
            self?.groups.remove(at: groupIndex)
        }
        
        print("Group '\(group.displayName)' dissolved successfully")
    }
    
    /// Handles cleanup when a track is deleted from the system
    /// This method should be called by CollectionService when tracks are deleted
    /// - Parameter trackId: ID of the deleted track
    func handleTrackDeletion(trackId: Int) async throws {
        // Find group containing this track
        guard let group = getGroupForTrack(trackId: trackId) else {
            return // Track not in any group
        }
        
        print("Handling deletion of track \(trackId) from group '\(group.displayName)'")
        
        // If this is the only track in the group, dissolve the group
        if group.trackCount <= 1 {
            try await dissolveGroup(groupId: group.id)
            return
        }
        
        // If this is the main track, reassign main track before removal
        if trackId == group.mainTrackId {
            var mutableGroup = group
            try await handleMainTrackRemoval(group: &mutableGroup, trackIdToRemove: trackId)
            
            // Update the group in our array
            if let groupIndex = groups.firstIndex(where: { $0.id == group.id }) {
                await MainActor.run { [weak self] in
                    self?.groups[groupIndex] = mutableGroup
                }
            }
        }
        
        // Remove track from group
        try await removeTrackFromGroup(groupId: group.id, trackId: trackId)
    }
    
    /// Completely removes all group data for a track (used during track deletion)
    /// - Parameter trackId: ID of the track to clean up
    private func cleanupTrackFromAllGroups(trackId: Int) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async { [weak self] in
                guard let self = self, let database = self.database else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Database not available"))
                    return
                }
                
                // Remove track from all group memberships
                let deleteSQL = "DELETE FROM \(self.tableTrackGroupMembers) WHERE track_id = ?"
                var statement: OpaquePointer?
                
                let result = sqlite3_prepare_v2(database, deleteSQL, -1, &statement, nil)
                guard result == SQLITE_OK else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Failed to prepare track cleanup statement"))
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_int(statement, 1, Int32(trackId))
                
                let stepResult = sqlite3_step(statement)
                if stepResult == SQLITE_DONE {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Failed to cleanup track from groups"))
                }
            }
        }
    }
    
    // MARK: - Cache Management Methods
    
    /// Rebuilds the internal caches for fast lookups
    private func rebuildCache() {
        trackToGroupCache.removeAll()
        groupCache.removeAll()
        
        for group in groups {
            groupCache[group.id] = group
            for trackId in group.trackIds {
                trackToGroupCache[trackId] = group.id
            }
        }
        
        cacheValid = true
        print("🔄 [TrackGroupService] Cache rebuilt: \(groups.count) groups, \(trackToGroupCache.count) track mappings")
    }
    
    /// Invalidates the cache (call when groups are modified)
    private func invalidateCache() {
        cacheValid = false
    }
    
    /// Updates cache for a specific group (more efficient than full rebuild)
    private func updateCacheForGroup(_ group: TrackGroup) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Remove old mappings for this group
            self.trackToGroupCache = self.trackToGroupCache.filter { $0.value != group.id }
            
            // Add new mappings
            self.groupCache[group.id] = group
            for trackId in group.trackIds {
                self.trackToGroupCache[trackId] = group.id
            }
        }
    }
    
    /// Removes cache entries for a deleted group
    private func removeCacheForGroup(_ groupId: String) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Remove group from cache
            self.groupCache.removeValue(forKey: groupId)
            
            // Remove track mappings for this group
            self.trackToGroupCache = self.trackToGroupCache.filter { $0.value != groupId }
        }
    }
    
    // MARK: - Validation Methods
    
    /// Validates group name constraints
    private func validateGroupName(_ name: String) throws {
        // Check length constraint
        if name.count > 255 {
            throw TrackGroupError.groupNameTooLong(name)
        }
        
        // Check for duplicate names (if name is not empty)
        if !name.isEmpty {
            let existingGroup = groups.first { $0.name.lowercased() == name.lowercased() }
            if existingGroup != nil {
                throw TrackGroupError.duplicateGroupName(name)
            }
        }
    }
    
    /// Validates track IDs format and basic constraints
    private func validateTrackIds(_ trackIds: [Int]) throws {
        // Check for empty array
        guard !trackIds.isEmpty else {
            throw TrackGroupError.invalidTrackIds(trackIds)
        }
        
        // Check for invalid IDs (negative or zero)
        let invalidIds = trackIds.filter { $0 <= 0 }
        if !invalidIds.isEmpty {
            throw TrackGroupError.invalidTrackIds(invalidIds)
        }
    }
    
    /// Validates that tracks exist and are not already in groups
    private func validateTracksExistAndNotGrouped(_ trackIds: [Int]) async throws {
        // Basic ID validation first
        try validateTrackIds(trackIds)
        
        // Check if any tracks are already in groups
        let groupedTrackIds = Set(groups.flatMap { $0.trackIds })
        let alreadyGrouped = trackIds.filter { groupedTrackIds.contains($0) }
        
        if !alreadyGrouped.isEmpty {
            // Find which group contains the first conflicting track
            if let conflictingTrackId = alreadyGrouped.first,
               let existingGroup = getGroupForTrack(trackId: conflictingTrackId) {
                throw TrackGroupError.trackAlreadyInGroup(conflictingTrackId, existingGroup.id)
            }
        }
        
        // Validate track existence in database
        try await validateTracksExistInDatabase(trackIds)
    }
    
    /// Validates that tracks exist in the database
    private func validateTracksExistInDatabase(_ trackIds: [Int]) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async { [weak self] in
                guard let self = self, let database = self.database else {
                    continuation.resume(throwing: TrackGroupError.databaseConnectionLost)
                    return
                }
                
                do {
                    var nonExistentTracks: [Int] = []
                    
                    for trackId in trackIds {
                        let checkSQL = "SELECT COUNT(*) FROM music WHERE id = ?"
                        var statement: OpaquePointer?
                        
                        let result = sqlite3_prepare_v2(database, checkSQL, -1, &statement, nil)
                        guard result == SQLITE_OK else {
                            continuation.resume(throwing: TrackGroupError.databaseError("Failed to prepare track existence check"))
                            return
                        }
                        
                        defer { sqlite3_finalize(statement) }
                        
                        sqlite3_bind_int(statement, 1, Int32(trackId))
                        
                        if sqlite3_step(statement) == SQLITE_ROW {
                            let count = sqlite3_column_int(statement, 0)
                            if count == 0 {
                                nonExistentTracks.append(trackId)
                            }
                        } else {
                            nonExistentTracks.append(trackId)
                        }
                    }
                    
                    if !nonExistentTracks.isEmpty {
                        continuation.resume(throwing: TrackGroupError.trackExistenceValidationFailed(nonExistentTracks))
                    } else {
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Validates group data integrity
    private func validateGroupIntegrity(_ group: TrackGroup) throws {
        // Check minimum track count
        if group.trackIds.count < 2 {
            throw TrackGroupError.corruptedGroupData(group.id, "Group has fewer than 2 tracks")
        }
        
        // Check main track is in track IDs
        if !group.trackIds.contains(group.mainTrackId) {
            throw TrackGroupError.corruptedGroupData(group.id, "Main track ID \(group.mainTrackId) not found in track IDs")
        }
        
        // Check for duplicate track IDs (Set should prevent this, but validate anyway)
        let trackIdArray = Array(group.trackIds)
        if trackIdArray.count != Set(trackIdArray).count {
            throw TrackGroupError.corruptedGroupData(group.id, "Duplicate track IDs detected")
        }
        
        // Validate group name
        try validateGroupName(group.name)
    }
    
    /// Validates database connection and state
    private func validateDatabaseConnection() throws {
        guard database != nil else {
            throw TrackGroupError.databaseConnectionLost
        }
    }
    
    // MARK: - Error Recovery Methods
    
    /// Attempts to recover from corrupted group data
    private func recoverFromCorruptedGroup(_ groupId: String, error: TrackGroupError) async throws {
        print("⚠️ Attempting to recover from corrupted group data: \(error.localizedDescription)")
        
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else {
            // Group not found in memory, try to remove from database
            try await deleteGroupFromDatabase(groupId)
            return
        }
        
        var group = groups[groupIndex]
        var recovered = false
        
        switch error {
        case .corruptedGroupData(_, let reason):
            if reason.contains("Main track ID") {
                // Try to reassign main track to first available track
                if let firstTrackId = group.trackIds.first {
                    group.mainTrackId = firstTrackId
                    recovered = true
                    print("✅ Recovered by reassigning main track to \(firstTrackId)")
                }
            } else if reason.contains("fewer than 2 tracks") {
                // Dissolve the group
                try await dissolveGroup(groupId: groupId)
                recovered = true
                print("✅ Recovered by dissolving invalid group")
            }
        default:
            break
        }
        
        if recovered {
            // Update the group in memory and database
            await MainActor.run { [weak self] in
                self?.groups[groupIndex] = group
            }
            try await updateGroupInDatabase(group)
        } else {
            // If we can't recover, remove the corrupted group
            try await deleteGroup(groupId: groupId)
            print("⚠️ Removed corrupted group that could not be recovered")
        }
    }
    
    /// Performs rollback operations for failed transactions
    private func performRollback(operation: String, groupId: String?, originalState: [TrackGroup]?) async throws {
        print("🔄 Performing rollback for failed operation: \(operation)")
        
        do {
            // Restore original state if provided
            if let originalState = originalState {
                await MainActor.run { [weak self] in
                    self?.groups = originalState
                }
            }
            
            // If we have a specific group ID, try to reload it from database
            if let groupId = groupId {
                try await reloadGroupFromDatabase(groupId)
            } else {
                // Reload all groups from database
                try await loadGroups()
            }
            
            print("✅ Rollback completed successfully")
        } catch {
            throw TrackGroupError.operationRollbackFailed("Failed to rollback \(operation): \(error.localizedDescription)")
        }
    }
    
    /// Reloads a specific group from database
    private func reloadGroupFromDatabase(_ groupId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async { [weak self] in
                guard let self = self, let database = self.database else {
                    continuation.resume(throwing: TrackGroupError.databaseConnectionLost)
                    return
                }
                
                do {
                    let selectSQL = """
                        SELECT id, name, main_track_id, date_created, is_expanded 
                        FROM \(self.tableTrackGroups) WHERE id = ?
                    """
                    
                    var statement: OpaquePointer?
                    let result = sqlite3_prepare_v2(database, selectSQL, -1, &statement, nil)
                    guard result == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to prepare group reload statement")
                    }
                    
                    defer { sqlite3_finalize(statement) }
                    
                    sqlite3_bind_text(statement, 1, groupId, -1, self.SQLITE_TRANSIENT)
                    
                    if sqlite3_step(statement) == SQLITE_ROW {
                        let id = String(cString: sqlite3_column_text(statement, 0))
                        let name = String(cString: sqlite3_column_text(statement, 1))
                        let mainTrackId = Int(sqlite3_column_int(statement, 2))
                        let dateCreatedString = String(cString: sqlite3_column_text(statement, 3))
                        let isExpanded = sqlite3_column_int(statement, 4) != 0
                        
                        let dateCreated = ISO8601DateFormatter().date(from: dateCreatedString) ?? Date()
                        
                        // Load track IDs
                        let trackIds = try self.loadTrackIdsForGroup(groupId: id, database: database)
                        
                        let reloadedGroup = TrackGroup(
                            id: id,
                            name: name,
                            mainTrackId: mainTrackId,
                            trackIds: Set(trackIds),
                            dateCreated: dateCreated,
                            isExpanded: isExpanded
                        )
                        
                        // Update in memory
                        Task { @MainActor [weak self] in
                            if let index = self?.groups.firstIndex(where: { $0.id == groupId }) {
                                self?.groups[index] = reloadedGroup
                            } else {
                                self?.groups.append(reloadedGroup)
                            }
                        }
                        
                        continuation.resume()
                    } else {
                        // Group not found in database, remove from memory
                        Task { @MainActor [weak self] in
                            self?.groups.removeAll { $0.id == groupId }
                        }
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Private Helper Methods
}

// MARK: - Database Operations
extension TrackGroupService {
    
    /// Saves a group to the database with enhanced error handling and validation
    private func saveGroupToDatabase(_ group: TrackGroup) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async { [weak self] in
                guard let self = self, let database = self.database else {
                    continuation.resume(throwing: TrackGroupError.databaseConnectionLost)
                    return
                }
                
                var transactionStarted = false
                
                do {
                    // Validate foreign key constraints are enabled
                    let pragmaResult = sqlite3_exec(database, "PRAGMA foreign_keys = ON", nil, nil, nil)
                    guard pragmaResult == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to enable foreign key constraints")
                    }
                    
                    // Begin transaction with timeout
                    var result = sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
                    guard result == SQLITE_OK else {
                        if result == SQLITE_BUSY {
                            throw TrackGroupError.transactionTimeout
                        }
                        throw TrackGroupError.databaseError("Failed to begin transaction: \(String(cString: sqlite3_errmsg(database)))")
                    }
                    transactionStarted = true
                    
                    // Check for duplicate group ID
                    let checkDuplicateSQL = "SELECT COUNT(*) FROM \(self.tableTrackGroups) WHERE id = ?"
                    var checkStatement: OpaquePointer?
                    result = sqlite3_prepare_v2(database, checkDuplicateSQL, -1, &checkStatement, nil)
                    guard result == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to prepare duplicate check statement")
                    }
                    
                    defer { sqlite3_finalize(checkStatement) }
                    
                    sqlite3_bind_text(checkStatement, 1, group.id, -1, self.SQLITE_TRANSIENT)
                    
                    if sqlite3_step(checkStatement) == SQLITE_ROW {
                        let count = sqlite3_column_int(checkStatement, 0)
                        if count > 0 {
                            throw TrackGroupError.dataIntegrityViolation("Group with ID \(group.id) already exists")
                        }
                    }
                    
                    // Insert group
                    let insertGroupSQL = """
                        INSERT INTO \(self.tableTrackGroups) 
                        (id, name, main_track_id, date_created, is_expanded) 
                        VALUES (?, ?, ?, ?, ?)
                    """
                    
                    var statement: OpaquePointer?
                    result = sqlite3_prepare_v2(database, insertGroupSQL, -1, &statement, nil)
                    guard result == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to prepare group insert statement: \(String(cString: sqlite3_errmsg(database)))")
                    }
                    
                    defer { sqlite3_finalize(statement) }
                    
                    sqlite3_bind_text(statement, 1, group.id, -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, group.name, -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_int(statement, 3, Int32(group.mainTrackId))
                    sqlite3_bind_text(statement, 4, ISO8601DateFormatter().string(from: group.dateCreated), -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_int(statement, 5, group.isExpanded ? 1 : 0)
                    
                    result = sqlite3_step(statement)
                    guard result == SQLITE_DONE else {
                        if result == SQLITE_CONSTRAINT {
                            throw TrackGroupError.foreignKeyConstraintViolation("Main track ID \(group.mainTrackId) does not exist")
                        }
                        throw TrackGroupError.databaseError("Failed to insert group: \(String(cString: sqlite3_errmsg(database)))")
                    }
                    
                    // Insert group members with batch processing
                    let insertMemberSQL = """
                        INSERT INTO \(self.tableTrackGroupMembers) (group_id, track_id) VALUES (?, ?)
                    """
                    
                    var memberStatement: OpaquePointer?
                    result = sqlite3_prepare_v2(database, insertMemberSQL, -1, &memberStatement, nil)
                    guard result == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to prepare member insert statement: \(String(cString: sqlite3_errmsg(database)))")
                    }
                    
                    defer { sqlite3_finalize(memberStatement) }
                    
                    for trackId in group.trackIds {
                        sqlite3_bind_text(memberStatement, 1, group.id, -1, self.SQLITE_TRANSIENT)
                        sqlite3_bind_int(memberStatement, 2, Int32(trackId))
                        
                        result = sqlite3_step(memberStatement)
                        guard result == SQLITE_DONE else {
                            if result == SQLITE_CONSTRAINT {
                                throw TrackGroupError.foreignKeyConstraintViolation("Track ID \(trackId) does not exist")
                            }
                            throw TrackGroupError.databaseError("Failed to insert group member \(trackId): \(String(cString: sqlite3_errmsg(database)))")
                        }
                        
                        sqlite3_reset(memberStatement)
                    }
                    
                    // Commit transaction
                    result = sqlite3_exec(database, "COMMIT", nil, nil, nil)
                    guard result == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to commit transaction: \(String(cString: sqlite3_errmsg(database)))")
                    }
                    
                    continuation.resume()
                    
                } catch {
                    // Rollback transaction if it was started
                    if transactionStarted {
                        let rollbackResult = sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        if rollbackResult != SQLITE_OK {
                            print("⚠️ Failed to rollback transaction: \(String(cString: sqlite3_errmsg(database)))")
                        }
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Deletes a group from the database
    private func deleteGroupFromDatabase(_ groupId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async { [weak self] in
                guard let self = self, let database = self.database else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Database not available"))
                    return
                }
                
                do {
                    // Begin transaction
                    var result = sqlite3_exec(database, "BEGIN TRANSACTION", nil, nil, nil)
                    guard result == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to begin transaction")
                    }
                    
                    // Delete group members (foreign key constraints should handle this, but explicit is better)
                    let deleteMembersSQL = "DELETE FROM \(self.tableTrackGroupMembers) WHERE group_id = ?"
                    var memberStatement: OpaquePointer?
                    result = sqlite3_prepare_v2(database, deleteMembersSQL, -1, &memberStatement, nil)
                    guard result == SQLITE_OK else {
                        sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        throw TrackGroupError.databaseError("Failed to prepare member delete statement")
                    }
                    
                    defer { sqlite3_finalize(memberStatement) }
                    
                    sqlite3_bind_text(memberStatement, 1, groupId, -1, self.SQLITE_TRANSIENT)
                    result = sqlite3_step(memberStatement)
                    guard result == SQLITE_DONE else {
                        sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        throw TrackGroupError.databaseError("Failed to delete group members")
                    }
                    
                    // Delete group
                    let deleteGroupSQL = "DELETE FROM \(self.tableTrackGroups) WHERE id = ?"
                    var groupStatement: OpaquePointer?
                    result = sqlite3_prepare_v2(database, deleteGroupSQL, -1, &groupStatement, nil)
                    guard result == SQLITE_OK else {
                        sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        throw TrackGroupError.databaseError("Failed to prepare group delete statement")
                    }
                    
                    defer { sqlite3_finalize(groupStatement) }
                    
                    sqlite3_bind_text(groupStatement, 1, groupId, -1, self.SQLITE_TRANSIENT)
                    result = sqlite3_step(groupStatement)
                    guard result == SQLITE_DONE else {
                        sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        throw TrackGroupError.databaseError("Failed to delete group")
                    }
                    
                    // Commit transaction
                    result = sqlite3_exec(database, "COMMIT", nil, nil, nil)
                    guard result == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to commit transaction")
                    }
                    
                    continuation.resume()
                } catch {
                    sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Updates a group in the database
    private func updateGroupInDatabase(_ group: TrackGroup) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async { [weak self] in
                guard let self = self, let database = self.database else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Database not available"))
                    return
                }
                
                do {
                    // Begin transaction
                    var result = sqlite3_exec(database, "BEGIN TRANSACTION", nil, nil, nil)
                    guard result == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to begin transaction")
                    }
                    
                    // Update group
                    let updateGroupSQL = """
                        UPDATE \(self.tableTrackGroups) 
                        SET name = ?, main_track_id = ?, is_expanded = ? 
                        WHERE id = ?
                    """
                    
                    var statement: OpaquePointer?
                    result = sqlite3_prepare_v2(database, updateGroupSQL, -1, &statement, nil)
                    guard result == SQLITE_OK else {
                        sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        throw TrackGroupError.databaseError("Failed to prepare group update statement")
                    }
                    
                    defer { sqlite3_finalize(statement) }
                    
                    sqlite3_bind_text(statement, 1, group.name, -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_int(statement, 2, Int32(group.mainTrackId))
                    sqlite3_bind_int(statement, 3, group.isExpanded ? 1 : 0)
                    sqlite3_bind_text(statement, 4, group.id, -1, self.SQLITE_TRANSIENT)
                    
                    result = sqlite3_step(statement)
                    guard result == SQLITE_DONE else {
                        sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        throw TrackGroupError.databaseError("Failed to update group")
                    }
                    
                    // Delete existing members
                    let deleteMembersSQL = "DELETE FROM \(self.tableTrackGroupMembers) WHERE group_id = ?"
                    var deleteStatement: OpaquePointer?
                    result = sqlite3_prepare_v2(database, deleteMembersSQL, -1, &deleteStatement, nil)
                    guard result == SQLITE_OK else {
                        sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        throw TrackGroupError.databaseError("Failed to prepare member delete statement")
                    }
                    
                    defer { sqlite3_finalize(deleteStatement) }
                    
                    sqlite3_bind_text(deleteStatement, 1, group.id, -1, self.SQLITE_TRANSIENT)
                    result = sqlite3_step(deleteStatement)
                    guard result == SQLITE_DONE else {
                        sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        throw TrackGroupError.databaseError("Failed to delete existing members")
                    }
                    
                    // Insert updated members
                    let insertMemberSQL = """
                        INSERT INTO \(self.tableTrackGroupMembers) (group_id, track_id) VALUES (?, ?)
                    """
                    
                    var memberStatement: OpaquePointer?
                    result = sqlite3_prepare_v2(database, insertMemberSQL, -1, &memberStatement, nil)
                    guard result == SQLITE_OK else {
                        sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        throw TrackGroupError.databaseError("Failed to prepare member insert statement")
                    }
                    
                    defer { sqlite3_finalize(memberStatement) }
                    
                    for trackId in group.trackIds {
                        sqlite3_bind_text(memberStatement, 1, group.id, -1, self.SQLITE_TRANSIENT)
                        sqlite3_bind_int(memberStatement, 2, Int32(trackId))
                        
                        result = sqlite3_step(memberStatement)
                        guard result == SQLITE_DONE else {
                            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                            throw TrackGroupError.databaseError("Failed to insert updated member")
                        }
                        
                        sqlite3_reset(memberStatement)
                    }
                    
                    // Commit transaction
                    result = sqlite3_exec(database, "COMMIT", nil, nil, nil)
                    guard result == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to commit transaction")
                    }
                    
                    continuation.resume()
                } catch {
                    sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Updates only the main track for a group
    private func updateGroupMainTrackInDatabase(groupId: String, mainTrackId: Int) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async { [weak self] in
                guard let self = self, let database = self.database else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Database not available"))
                    return
                }
                
                let updateSQL = "UPDATE \(self.tableTrackGroups) SET main_track_id = ? WHERE id = ?"
                var statement: OpaquePointer?
                
                let result = sqlite3_prepare_v2(database, updateSQL, -1, &statement, nil)
                guard result == SQLITE_OK else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Failed to prepare main track update statement"))
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_int(statement, 1, Int32(mainTrackId))
                sqlite3_bind_text(statement, 2, groupId, -1, self.SQLITE_TRANSIENT)
                
                let stepResult = sqlite3_step(statement)
                if stepResult == SQLITE_DONE {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Failed to update main track"))
                }
            }
        }
    }
    
    /// Updates only the expansion state for a group
    private func updateGroupExpansionInDatabase(groupId: String, isExpanded: Bool) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async { [weak self] in
                guard let self = self, let database = self.database else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Database not available"))
                    return
                }
                
                let updateSQL = "UPDATE \(self.tableTrackGroups) SET is_expanded = ? WHERE id = ?"
                var statement: OpaquePointer?
                
                let result = sqlite3_prepare_v2(database, updateSQL, -1, &statement, nil)
                guard result == SQLITE_OK else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Failed to prepare expansion update statement"))
                    return
                }
                
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_int(statement, 1, isExpanded ? 1 : 0)
                sqlite3_bind_text(statement, 2, groupId, -1, self.SQLITE_TRANSIENT)
                
                let stepResult = sqlite3_step(statement)
                if stepResult == SQLITE_DONE {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Failed to update expansion state"))
                }
            }
        }
    }
    
    /// Loads all groups from the database
    private func loadGroupsFromDatabase() async throws -> [TrackGroup] {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async { [weak self] in
                guard let self = self, let database = self.database else {
                    continuation.resume(throwing: TrackGroupError.databaseError("Database not available"))
                    return
                }
                
                do {
                    var groups: [TrackGroup] = []
                    
                    // Load groups
                    let selectGroupsSQL = """
                        SELECT id, name, main_track_id, date_created, is_expanded 
                        FROM \(self.tableTrackGroups)
                    """
                    
                    var statement: OpaquePointer?
                    let result = sqlite3_prepare_v2(database, selectGroupsSQL, -1, &statement, nil)
                    guard result == SQLITE_OK else {
                        throw TrackGroupError.databaseError("Failed to prepare groups select statement")
                    }
                    
                    defer { sqlite3_finalize(statement) }
                    
                    while sqlite3_step(statement) == SQLITE_ROW {
                        let id = String(cString: sqlite3_column_text(statement, 0))
                        let name = String(cString: sqlite3_column_text(statement, 1))
                        let mainTrackId = Int(sqlite3_column_int(statement, 2))
                        let dateCreatedString = String(cString: sqlite3_column_text(statement, 3))
                        let isExpanded = sqlite3_column_int(statement, 4) != 0
                        
                        let dateCreated = ISO8601DateFormatter().date(from: dateCreatedString) ?? Date()
                        
                        // Load track IDs for this group
                        let trackIds = try self.loadTrackIdsForGroup(groupId: id, database: database)
                        
                        let group = TrackGroup(
                            id: id,
                            name: name,
                            mainTrackId: mainTrackId,
                            trackIds: Set(trackIds),
                            dateCreated: dateCreated,
                            isExpanded: isExpanded
                        )
                        
                        groups.append(group)
                    }
                    
                    continuation.resume(returning: groups)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Loads track IDs for a specific group
    private func loadTrackIdsForGroup(groupId: String, database: OpaquePointer) throws -> [Int] {
        let selectMembersSQL = """
            SELECT track_id FROM \(tableTrackGroupMembers) WHERE group_id = ?
        """
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, selectMembersSQL, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw TrackGroupError.databaseError("Failed to prepare members select statement")
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, groupId, -1, SQLITE_TRANSIENT)
        
        var trackIds: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let trackId = Int(sqlite3_column_int(statement, 0))
            trackIds.append(trackId)
        }
        
        return trackIds
    }
}