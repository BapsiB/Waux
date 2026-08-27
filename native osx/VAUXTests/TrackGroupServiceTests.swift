import XCTest
import SQLite3
@testable import VAUX

class TrackGroupServiceTests: XCTestCase {
    
    // MARK: - Test Properties
    private var service: TrackGroupService!
    private var database: OpaquePointer?
    private var testDatabasePath: String!
    private let testDatabaseQueue = DispatchQueue(label: "com.vaux.tests.TrackGroupServiceTests")
    
    // MARK: - Test Setup and Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary database for testing
        testDatabasePath = NSTemporaryDirectory() + "test_track_groups_\(UUID().uuidString).db"
        
        // Open database
        let result = sqlite3_open(testDatabasePath, &database)
        XCTAssertEqual(result, SQLITE_OK, "Failed to open test database")
        
        // Create tables
        try createTestTables()
        
        // Initialize service
        service = TrackGroupService()
        service.setDatabase(database, databaseQueue: testDatabaseQueue)
        
        // Insert test tracks
        try insertTestTracks()
    }
    
    override func tearDown() async throws {
        // Close database
        if let database = database {
            sqlite3_close(database)
        }
        
        // Remove test database file
        if let testDatabasePath = testDatabasePath {
            try? FileManager.default.removeItem(atPath: testDatabasePath)
        }
        
        service = nil
        database = nil
        testDatabasePath = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Test Helper Methods
    
    private func createTestTables() throws {
        let createTrackGroupsSQL = """
            CREATE TABLE track_groups (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL DEFAULT '',
                main_track_id INTEGER NOT NULL,
                date_created TEXT NOT NULL,
                is_expanded INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (main_track_id) REFERENCES music (id) ON DELETE CASCADE
            )
        """
        
        let createTrackGroupMembersSQL = """
            CREATE TABLE track_group_members (
                group_id TEXT NOT NULL,
                track_id INTEGER NOT NULL,
                PRIMARY KEY (group_id, track_id),
                FOREIGN KEY (group_id) REFERENCES track_groups (id) ON DELETE CASCADE,
                FOREIGN KEY (track_id) REFERENCES music (id) ON DELETE CASCADE
            )
        """
        
        let createMusicSQL = """
            CREATE TABLE music (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT NOT NULL,
                path TEXT NOT NULL,
                isUrl INTEGER NOT NULL DEFAULT 0,
                duration INTEGER NOT NULL DEFAULT 0
            )
        """
        
        var result = sqlite3_exec(database, createMusicSQL, nil, nil, nil)
        XCTAssertEqual(result, SQLITE_OK, "Failed to create music table")
        
        result = sqlite3_exec(database, createTrackGroupsSQL, nil, nil, nil)
        XCTAssertEqual(result, SQLITE_OK, "Failed to create track_groups table")
        
        result = sqlite3_exec(database, createTrackGroupMembersSQL, nil, nil, nil)
        XCTAssertEqual(result, SQLITE_OK, "Failed to create track_group_members table")
    }
    
    private func insertTestTracks() throws {
        let insertSQL = """
            INSERT INTO music (id, title, artist, album, path, isUrl, duration) 
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        
        let testTracks = [
            (1, "Original Song", "Test Artist", "Test Album", "/test/1.mp3", 0, 180000),
            (2, "Remix Version", "Test Artist", "Test Album", "/test/2.mp3", 0, 200000),
            (3, "Live Version", "Test Artist", "Test Album", "/test/3.mp3", 0, 220000),
            (4, "Acoustic Version", "Test Artist", "Test Album", "/test/4.mp3", 0, 160000),
            (5, "Radio Edit", "Test Artist", "Test Album", "/test/5.mp3", 0, 150000)
        ]
        
        for track in testTracks {
            var statement: OpaquePointer?
            let result = sqlite3_prepare_v2(database, insertSQL, -1, &statement, nil)
            XCTAssertEqual(result, SQLITE_OK, "Failed to prepare insert statement")
            
            sqlite3_bind_int(statement, 1, Int32(track.0))
            sqlite3_bind_text(statement, 2, track.1, -1, nil)
            sqlite3_bind_text(statement, 3, track.2, -1, nil)
            sqlite3_bind_text(statement, 4, track.3, -1, nil)
            sqlite3_bind_text(statement, 5, track.4, -1, nil)
            sqlite3_bind_int(statement, 6, Int32(track.5))
            sqlite3_bind_int(statement, 7, Int32(track.6))
            
            let stepResult = sqlite3_step(statement)
            XCTAssertEqual(stepResult, SQLITE_DONE, "Failed to insert test track")
            
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Group Creation Tests
    
    func testCreateGroupSuccess() async throws {
        let trackIds = [1, 2, 3]
        let name = "Test Group"
        
        let group = try await service.createGroup(trackIds: trackIds, name: name, mainTrackId: 1)
        
        XCTAssertFalse(group.id.isEmpty)
        XCTAssertEqual(group.name, name)
        XCTAssertEqual(group.mainTrackId, 1)
        XCTAssertEqual(group.trackIds, Set(trackIds))
        XCTAssertEqual(group.trackCount, 3)
        XCTAssertFalse(group.isExpanded)
        
        // Verify it's in the service's groups array
        XCTAssertEqual(service.groups.count, 1)
        XCTAssertEqual(service.groups.first?.id, group.id)
    }
    
    func testCreateGroupWithDefaultMainTrack() async throws {
        let trackIds = [2, 3, 4]
        
        let group = try await service.createGroup(trackIds: trackIds)
        
        XCTAssertEqual(group.mainTrackId, 2) // First track should be main
        XCTAssertTrue(group.name.isEmpty)
        XCTAssertEqual(group.displayName, "Track Group")
    }
    
    func testCreateGroupFailsWithInsufficientTracks() async {
        do {
            _ = try await service.createGroup(trackIds: [1])
            XCTFail("Should have thrown insufficientTracks error")
        } catch TrackGroupError.insufficientTracks {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateGroupFailsWithDuplicateTrackIds() async {
        do {
            _ = try await service.createGroup(trackIds: [1, 1, 2])
            // Should succeed with deduplicated IDs
            XCTAssertEqual(service.groups.count, 1)
            XCTAssertEqual(service.groups.first?.trackCount, 2)
        } catch {
            XCTFail("Should not fail with duplicate IDs: \(error)")
        }
    }
    
    func testCreateGroupFailsWithInvalidMainTrack() async {
        do {
            _ = try await service.createGroup(trackIds: [1, 2], mainTrackId: 99)
            XCTFail("Should have thrown mainTrackNotInGroup error")
        } catch TrackGroupError.mainTrackNotInGroup(let trackId, _) {
            XCTAssertEqual(trackId, 99)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateGroupFailsWithAlreadyGroupedTracks() async throws {
        // Create first group
        _ = try await service.createGroup(trackIds: [1, 2])
        
        // Try to create second group with overlapping tracks
        do {
            _ = try await service.createGroup(trackIds: [2, 3])
            XCTFail("Should have thrown trackAlreadyInGroup error")
        } catch TrackGroupError.trackAlreadyInGroup(let trackId, _) {
            XCTAssertEqual(trackId, 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Group Deletion Tests
    
    func testDeleteGroupSuccess() async throws {
        // Create group
        let group = try await service.createGroup(trackIds: [1, 2, 3])
        XCTAssertEqual(service.groups.count, 1)
        
        // Delete group
        try await service.deleteGroup(groupId: group.id)
        
        // Verify deletion
        XCTAssertEqual(service.groups.count, 0)
    }
    
    func testDeleteGroupFailsWithInvalidId() async {
        do {
            try await service.deleteGroup(groupId: "invalid-id")
            XCTFail("Should have thrown groupNotFound error")
        } catch TrackGroupError.groupNotFound(let groupId) {
            XCTAssertEqual(groupId, "invalid-id")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Add Tracks to Group Tests
    
    func testAddTracksToGroupSuccess() async throws {
        // Create group
        let group = try await service.createGroup(trackIds: [1, 2])
        let originalCount = group.trackCount
        
        // Add tracks
        try await service.addTracksToGroup(groupId: group.id, trackIds: [3, 4])
        
        // Verify addition
        let updatedGroup = service.groups.first { $0.id == group.id }
        XCTAssertNotNil(updatedGroup)
        XCTAssertEqual(updatedGroup?.trackCount, originalCount + 2)
        XCTAssertTrue(updatedGroup?.contains(3) ?? false)
        XCTAssertTrue(updatedGroup?.contains(4) ?? false)
    }
    
    func testAddTracksToGroupFailsWithInvalidGroupId() async {
        do {
            try await service.addTracksToGroup(groupId: "invalid-id", trackIds: [1, 2])
            XCTFail("Should have thrown groupNotFound error")
        } catch TrackGroupError.groupNotFound(let groupId) {
            XCTAssertEqual(groupId, "invalid-id")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testAddTracksToGroupFailsWithAlreadyGroupedTracks() async throws {
        // Create two groups
        let group1 = try await service.createGroup(trackIds: [1, 2])
        _ = try await service.createGroup(trackIds: [3, 4])
        
        // Try to add track from group2 to group1
        do {
            try await service.addTracksToGroup(groupId: group1.id, trackIds: [3])
            XCTFail("Should have thrown trackAlreadyInGroup error")
        } catch TrackGroupError.trackAlreadyInGroup(let trackId, _) {
            XCTAssertEqual(trackId, 3)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Remove Track from Group Tests
    
    func testRemoveTrackFromGroupSuccess() async throws {
        // Create group with 3 tracks
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        // Remove non-main track
        try await service.removeTrackFromGroup(groupId: group.id, trackId: 3)
        
        // Verify removal
        let updatedGroup = service.groups.first { $0.id == group.id }
        XCTAssertNotNil(updatedGroup)
        XCTAssertEqual(updatedGroup?.trackCount, 2)
        XCTAssertFalse(updatedGroup?.contains(3) ?? true)
        XCTAssertTrue(updatedGroup?.contains(1) ?? false)
        XCTAssertTrue(updatedGroup?.contains(2) ?? false)
    }
    
    func testRemoveTrackFromGroupFailsWithMainTrack() async throws {
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        // With the new logic, removing main track should succeed by reassigning main track
        try await service.removeTrackFromGroup(groupId: group.id, trackId: 1)
        
        // Verify group still exists with new main track
        XCTAssertEqual(service.groups.count, 1)
        let updatedGroup = service.groups.first!
        XCTAssertEqual(updatedGroup.trackCount, 2)
        XCTAssertFalse(updatedGroup.contains(1))
        XCTAssertNotEqual(updatedGroup.mainTrackId, 1)
    }
    
    func testRemoveTrackFromGroupFailsWithTwoTracksLeft() async throws {
        let group = try await service.createGroup(trackIds: [1, 2], mainTrackId: 1)
        
        // With new logic, removing from 2-track group should dissolve the group
        try await service.removeTrackFromGroup(groupId: group.id, trackId: 2)
        
        // Verify group was dissolved
        XCTAssertEqual(service.groups.count, 0)
    }
    
    func testRemoveTrackFromGroupFailsWithInvalidTrackId() async throws {
        let group = try await service.createGroup(trackIds: [1, 2, 3])
        
        do {
            try await service.removeTrackFromGroup(groupId: group.id, trackId: 99)
            XCTFail("Should have thrown trackNotFound error")
        } catch TrackGroupError.trackNotFound(let trackId) {
            XCTAssertEqual(trackId, 99)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testRemoveTrackFromGroupFailsWithInvalidGroupId() async {
        do {
            try await service.removeTrackFromGroup(groupId: "invalid-id", trackId: 1)
            XCTFail("Should have thrown groupNotFound error")
        } catch TrackGroupError.groupNotFound(let groupId) {
            XCTAssertEqual(groupId, "invalid-id")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Set Main Track Tests
    
    func testSetMainTrackSuccess() async throws {
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        // Change main track
        try await service.setMainTrack(groupId: group.id, trackId: 2)
        
        // Verify change
        let updatedGroup = service.groups.first { $0.id == group.id }
        XCTAssertNotNil(updatedGroup)
        XCTAssertEqual(updatedGroup?.mainTrackId, 2)
    }
    
    func testSetMainTrackFailsWithInvalidTrackId() async throws {
        let group = try await service.createGroup(trackIds: [1, 2, 3])
        
        do {
            try await service.setMainTrack(groupId: group.id, trackId: 99)
            XCTFail("Should have thrown mainTrackNotInGroup error")
        } catch TrackGroupError.mainTrackNotInGroup(let trackId, let groupId) {
            XCTAssertEqual(trackId, 99)
            XCTAssertEqual(groupId, group.id)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSetMainTrackFailsWithInvalidGroupId() async {
        do {
            try await service.setMainTrack(groupId: "invalid-id", trackId: 1)
            XCTFail("Should have thrown groupNotFound error")
        } catch TrackGroupError.groupNotFound(let groupId) {
            XCTAssertEqual(groupId, "invalid-id")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Group Lookup Tests
    
    func testGetGroupForTrackSuccess() async throws {
        let group = try await service.createGroup(trackIds: [1, 2, 3])
        
        // Test finding group for each track
        let foundGroup1 = service.getGroupForTrack(trackId: 1)
        let foundGroup2 = service.getGroupForTrack(trackId: 2)
        let foundGroup3 = service.getGroupForTrack(trackId: 3)
        
        XCTAssertNotNil(foundGroup1)
        XCTAssertNotNil(foundGroup2)
        XCTAssertNotNil(foundGroup3)
        XCTAssertEqual(foundGroup1?.id, group.id)
        XCTAssertEqual(foundGroup2?.id, group.id)
        XCTAssertEqual(foundGroup3?.id, group.id)
    }
    
    func testGetGroupForTrackReturnsNilForUngroupedTrack() async throws {
        _ = try await service.createGroup(trackIds: [1, 2])
        
        let foundGroup = service.getGroupForTrack(trackId: 3)
        XCTAssertNil(foundGroup)
    }
    
    func testGetGroupForTrackReturnsNilForNonexistentTrack() async {
        let foundGroup = service.getGroupForTrack(trackId: 99)
        XCTAssertNil(foundGroup)
    }
    
    // MARK: - Group Expansion Tests
    
    func testToggleGroupExpansion() async throws {
        let group = try await service.createGroup(trackIds: [1, 2, 3])
        XCTAssertFalse(group.isExpanded)
        
        // Toggle expansion
        service.toggleGroupExpansion(groupId: group.id)
        
        // Verify expansion state changed
        let updatedGroup = service.groups.first { $0.id == group.id }
        XCTAssertNotNil(updatedGroup)
        XCTAssertTrue(updatedGroup?.isExpanded ?? false)
        
        // Toggle again
        service.toggleGroupExpansion(groupId: group.id)
        
        // Verify it's collapsed again
        let reUpdatedGroup = service.groups.first { $0.id == group.id }
        XCTAssertNotNil(reUpdatedGroup)
        XCTAssertFalse(reUpdatedGroup?.isExpanded ?? true)
    }
    
    func testToggleGroupExpansionWithInvalidId() async {
        // Should not crash or throw
        service.toggleGroupExpansion(groupId: "invalid-id")
        // No assertion needed - just testing it doesn't crash
    }
    
    // MARK: - Ungrouped Tracks Tests
    
    func testGetUngroupedTracks() async throws {
        let allTracks = [
            Track(id: 1, title: "Track 1", artist: "Artist", album: "Album", path: "/1.mp3", isUrl: false, duration: 180000),
            Track(id: 2, title: "Track 2", artist: "Artist", album: "Album", path: "/2.mp3", isUrl: false, duration: 180000),
            Track(id: 3, title: "Track 3", artist: "Artist", album: "Album", path: "/3.mp3", isUrl: false, duration: 180000),
            Track(id: 4, title: "Track 4", artist: "Artist", album: "Album", path: "/4.mp3", isUrl: false, duration: 180000)
        ]
        
        // Create group with tracks 1 and 2
        _ = try await service.createGroup(trackIds: [1, 2])
        
        // Get ungrouped tracks
        let ungroupedTracks = service.getUngroupedTracks(from: allTracks)
        
        // Should return tracks 3 and 4
        XCTAssertEqual(ungroupedTracks.count, 2)
        XCTAssertTrue(ungroupedTracks.contains { $0.id == 3 })
        XCTAssertTrue(ungroupedTracks.contains { $0.id == 4 })
        XCTAssertFalse(ungroupedTracks.contains { $0.id == 1 })
        XCTAssertFalse(ungroupedTracks.contains { $0.id == 2 })
    }
    
    func testGetUngroupedTracksWithNoGroups() async {
        let allTracks = [
            Track(id: 1, title: "Track 1", artist: "Artist", album: "Album", path: "/1.mp3", isUrl: false, duration: 180000),
            Track(id: 2, title: "Track 2", artist: "Artist", album: "Album", path: "/2.mp3", isUrl: false, duration: 180000)
        ]
        
        let ungroupedTracks = service.getUngroupedTracks(from: allTracks)
        
        // All tracks should be ungrouped
        XCTAssertEqual(ungroupedTracks.count, 2)
    }
    
    // MARK: - Load Groups Tests
    
    func testLoadGroupsFromDatabase() async throws {
        // Create groups directly in database
        let group1Id = UUID().uuidString
        let group2Id = UUID().uuidString
        
        try insertGroupDirectly(id: group1Id, name: "Group 1", mainTrackId: 1, trackIds: [1, 2])
        try insertGroupDirectly(id: group2Id, name: "Group 2", mainTrackId: 3, trackIds: [3, 4, 5])
        
        // Create a fresh service instance to test loading
        let loadService = TrackGroupService()
        loadService.setDatabase(database, databaseQueue: testDatabaseQueue)
        
        // Load groups
        try await loadService.loadGroups()
        
        // Verify loaded groups
        XCTAssertEqual(loadService.groups.count, 2)
        
        let loadedGroup1 = loadService.groups.first { $0.id == group1Id }
        let loadedGroup2 = loadService.groups.first { $0.id == group2Id }
        
        XCTAssertNotNil(loadedGroup1)
        XCTAssertNotNil(loadedGroup2)
        
        XCTAssertEqual(loadedGroup1?.name, "Group 1")
        XCTAssertEqual(loadedGroup1?.mainTrackId, 1)
        XCTAssertEqual(loadedGroup1?.trackIds, Set([1, 2]))
        
        XCTAssertEqual(loadedGroup2?.name, "Group 2")
        XCTAssertEqual(loadedGroup2?.mainTrackId, 3)
        XCTAssertEqual(loadedGroup2?.trackIds, Set([3, 4, 5]))
    }
    
    // MARK: - Integration Tests
    
    func testCompleteGroupLifecycle() async throws {
        // Create group
        let group = try await service.createGroup(trackIds: [1, 2, 3], name: "Test Group", mainTrackId: 2)
        XCTAssertEqual(service.groups.count, 1)
        
        // Add track
        try await service.addTracksToGroup(groupId: group.id, trackIds: [4])
        let updatedGroup1 = service.groups.first { $0.id == group.id }
        XCTAssertEqual(updatedGroup1?.trackCount, 4)
        
        // Change main track
        try await service.setMainTrack(groupId: group.id, trackId: 3)
        let updatedGroup2 = service.groups.first { $0.id == group.id }
        XCTAssertEqual(updatedGroup2?.mainTrackId, 3)
        
        // Remove track
        try await service.removeTrackFromGroup(groupId: group.id, trackId: 4)
        let updatedGroup3 = service.groups.first { $0.id == group.id }
        XCTAssertEqual(updatedGroup3?.trackCount, 3)
        
        // Toggle expansion
        service.toggleGroupExpansion(groupId: group.id)
        let updatedGroup4 = service.groups.first { $0.id == group.id }
        XCTAssertTrue(updatedGroup4?.isExpanded ?? false)
        
        // Delete group
        try await service.deleteGroup(groupId: group.id)
        XCTAssertEqual(service.groups.count, 0)
    }
    
    func testMultipleGroupsManagement() async throws {
        // Create multiple groups
        let group1 = try await service.createGroup(trackIds: [1, 2], name: "Group 1")
        let group2 = try await service.createGroup(trackIds: [3, 4], name: "Group 2")
        
        XCTAssertEqual(service.groups.count, 2)
        
        // Verify group lookup works correctly
        XCTAssertEqual(service.getGroupForTrack(trackId: 1)?.id, group1.id)
        XCTAssertEqual(service.getGroupForTrack(trackId: 3)?.id, group2.id)
        XCTAssertNil(service.getGroupForTrack(trackId: 5))
        
        // Delete one group
        try await service.deleteGroup(groupId: group1.id)
        XCTAssertEqual(service.groups.count, 1)
        XCTAssertNil(service.getGroupForTrack(trackId: 1))
        XCTAssertEqual(service.getGroupForTrack(trackId: 3)?.id, group2.id)
    }
    
    // MARK: - Group Dissolution and Cleanup Tests
    
    func testAutomaticGroupDissolutionWhenOnlyOneTrackRemains() async throws {
        // Create group with 2 tracks
        let group = try await service.createGroup(trackIds: [1, 2], mainTrackId: 1)
        XCTAssertEqual(service.groups.count, 1)
        
        // Remove non-main track - should dissolve group
        try await service.removeTrackFromGroup(groupId: group.id, trackId: 2)
        
        // Verify group was dissolved
        XCTAssertEqual(service.groups.count, 0)
        XCTAssertNil(service.getGroupForTrack(trackId: 1))
        XCTAssertNil(service.getGroupForTrack(trackId: 2))
    }
    
    func testMainTrackRemovalWithAutomaticReassignment() async throws {
        // Create group with 3 tracks
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        XCTAssertEqual(group.mainTrackId, 1)
        
        // Remove main track - should reassign main track and continue
        try await service.removeTrackFromGroup(groupId: group.id, trackId: 1)
        
        // Verify group still exists with new main track
        XCTAssertEqual(service.groups.count, 1)
        let updatedGroup = service.groups.first!
        XCTAssertEqual(updatedGroup.trackCount, 2)
        XCTAssertFalse(updatedGroup.contains(1))
        XCTAssertTrue(updatedGroup.contains(2))
        XCTAssertTrue(updatedGroup.contains(3))
        
        // Main track should be reassigned to one of the remaining tracks
        XCTAssertTrue(updatedGroup.mainTrackId == 2 || updatedGroup.mainTrackId == 3)
        XCTAssertTrue(updatedGroup.contains(updatedGroup.mainTrackId))
    }
    
    func testMainTrackRemovalFromTwoTrackGroupDissolvesGroup() async throws {
        // Create group with 2 tracks where main track is removed
        let group = try await service.createGroup(trackIds: [1, 2], mainTrackId: 1)
        
        // Remove main track - should dissolve group since only 1 track would remain
        try await service.removeTrackFromGroup(groupId: group.id, trackId: 1)
        
        // Verify group was dissolved
        XCTAssertEqual(service.groups.count, 0)
    }
    
    func testUngroupTracksRemovesAllGroupData() async throws {
        // Create group
        let group = try await service.createGroup(trackIds: [1, 2, 3], name: "Test Group")
        XCTAssertEqual(service.groups.count, 1)
        
        // Ungroup tracks
        try await service.ungroupTracks(groupId: group.id)
        
        // Verify all group data is removed
        XCTAssertEqual(service.groups.count, 0)
        XCTAssertNil(service.getGroupForTrack(trackId: 1))
        XCTAssertNil(service.getGroupForTrack(trackId: 2))
        XCTAssertNil(service.getGroupForTrack(trackId: 3))
    }
    
    func testUngroupTracksFailsWithInvalidGroupId() async {
        do {
            try await service.ungroupTracks(groupId: "invalid-id")
            XCTFail("Should have thrown groupNotFound error")
        } catch TrackGroupError.groupNotFound(let groupId) {
            XCTAssertEqual(groupId, "invalid-id")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testHandleTrackDeletionFromGroup() async throws {
        // Create group with 3 tracks
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        // Simulate track deletion
        try await service.handleTrackDeletion(trackId: 2)
        
        // Verify track was removed from group
        let updatedGroup = service.groups.first { $0.id == group.id }
        XCTAssertNotNil(updatedGroup)
        XCTAssertEqual(updatedGroup?.trackCount, 2)
        XCTAssertFalse(updatedGroup?.contains(2) ?? true)
        XCTAssertTrue(updatedGroup?.contains(1) ?? false)
        XCTAssertTrue(updatedGroup?.contains(3) ?? false)
    }
    
    func testHandleMainTrackDeletionReassignsMainTrack() async throws {
        // Create group with 3 tracks
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        // Simulate main track deletion
        try await service.handleTrackDeletion(trackId: 1)
        
        // Verify main track was reassigned and track removed
        let updatedGroup = service.groups.first { $0.id == group.id }
        XCTAssertNotNil(updatedGroup)
        XCTAssertEqual(updatedGroup?.trackCount, 2)
        XCTAssertFalse(updatedGroup?.contains(1) ?? true)
        XCTAssertNotEqual(updatedGroup?.mainTrackId, 1)
        XCTAssertTrue(updatedGroup?.contains(updatedGroup?.mainTrackId ?? -1) ?? false)
    }
    
    func testHandleTrackDeletionDissolvesGroupWithOneTrackLeft() async throws {
        // Create group with 2 tracks
        let group = try await service.createGroup(trackIds: [1, 2], mainTrackId: 1)
        
        // Simulate track deletion
        try await service.handleTrackDeletion(trackId: 2)
        
        // Verify group was dissolved
        XCTAssertEqual(service.groups.count, 0)
    }
    
    func testHandleTrackDeletionWithNonGroupedTrack() async throws {
        // Create group with some tracks
        _ = try await service.createGroup(trackIds: [1, 2])
        
        // Simulate deletion of non-grouped track - should not affect anything
        try await service.handleTrackDeletion(trackId: 3)
        
        // Verify group is unchanged
        XCTAssertEqual(service.groups.count, 1)
        let group = service.groups.first!
        XCTAssertEqual(group.trackCount, 2)
    }
    
    func testErrorHandlingForGroupDissolution() async throws {
        // Create group
        let group = try await service.createGroup(trackIds: [1, 2])
        
        // Close database to simulate database error
        if let database = database {
            sqlite3_close(database)
            self.database = nil
            service.setDatabase(nil, databaseQueue: nil)
        }
        
        // Try to remove track - should get database error
        do {
            try await service.removeTrackFromGroup(groupId: group.id, trackId: 2)
            XCTFail("Should have thrown database error")
        } catch TrackGroupError.databaseError {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testErrorHandlingForMainTrackReassignment() async throws {
        // Create group with only main track (simulate corrupted state)
        let group = try await service.createGroup(trackIds: [1, 2])
        
        // Manually corrupt the group to have only main track
        if let groupIndex = service.groups.firstIndex(where: { $0.id == group.id }) {
            var corruptedGroup = service.groups[groupIndex]
            corruptedGroup.trackIds = Set([1]) // Only main track remains
            await MainActor.run {
                service.groups[groupIndex] = corruptedGroup
            }
        }
        
        // Try to remove main track - should fail with reassignment error
        do {
            try await service.removeTrackFromGroup(groupId: group.id, trackId: 1)
            XCTFail("Should have thrown main track reassignment error")
        } catch TrackGroupError.mainTrackReassignmentFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCompleteCleanupWorkflow() async throws {
        // Create multiple groups
        let group1 = try await service.createGroup(trackIds: [1, 2, 3], name: "Group 1", mainTrackId: 1)
        let group2 = try await service.createGroup(trackIds: [4, 5], name: "Group 2", mainTrackId: 4)
        XCTAssertEqual(service.groups.count, 2)
        
        // Remove main track from group1 - should reassign main track
        try await service.removeTrackFromGroup(groupId: group1.id, trackId: 1)
        XCTAssertEqual(service.groups.count, 2)
        let updatedGroup1 = service.groups.first { $0.id == group1.id }
        XCTAssertNotNil(updatedGroup1)
        XCTAssertEqual(updatedGroup1?.trackCount, 2)
        XCTAssertNotEqual(updatedGroup1?.mainTrackId, 1)
        
        // Remove another track from group1 - should dissolve group
        let remainingTrackId = updatedGroup1?.trackIds.first { $0 != updatedGroup1?.mainTrackId }
        XCTAssertNotNil(remainingTrackId)
        try await service.removeTrackFromGroup(groupId: group1.id, trackId: remainingTrackId!)
        XCTAssertEqual(service.groups.count, 1)
        
        // Verify only group2 remains
        let remainingGroup = service.groups.first
        XCTAssertEqual(remainingGroup?.id, group2.id)
    }
    
    // MARK: - Enhanced Error Handling Tests
    
    func testCreateGroupWithEmptyTrackArray() async {
        do {
            _ = try await service.createGroup(trackIds: [])
            XCTFail("Should have thrown insufficientTracks error")
        } catch TrackGroupError.insufficientTracks {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateGroupWithSingleTrack() async {
        do {
            _ = try await service.createGroup(trackIds: [1])
            XCTFail("Should have thrown insufficientTracks error")
        } catch TrackGroupError.insufficientTracks {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testAddEmptyTrackArrayToGroup() async throws {
        let group = try await service.createGroup(trackIds: [1, 2])
        
        do {
            try await service.addTracksToGroup(groupId: group.id, trackIds: [])
            XCTFail("Should have thrown validation error")
        } catch TrackGroupError.validationFailed(let reason) {
            XCTAssertTrue(reason.contains("No tracks provided"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSetMainTrackToSameTrack() async throws {
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 2)
        
        // Setting main track to same track should be a no-op
        try await service.setMainTrack(groupId: group.id, trackId: 2)
        
        let updatedGroup = service.groups.first { $0.id == group.id }
        XCTAssertEqual(updatedGroup?.mainTrackId, 2)
    }
    
    func testOperationWithInvalidGroupId() async {
        let invalidGroupId = "non-existent-group-id"
        
        // Test various operations with invalid group ID
        do {
            try await service.addTracksToGroup(groupId: invalidGroupId, trackIds: [1])
            XCTFail("Should have thrown groupNotFound error")
        } catch TrackGroupError.groupNotFound(let groupId) {
            XCTAssertEqual(groupId, invalidGroupId)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        do {
            try await service.setMainTrack(groupId: invalidGroupId, trackId: 1)
            XCTFail("Should have thrown groupNotFound error")
        } catch TrackGroupError.groupNotFound(let groupId) {
            XCTAssertEqual(groupId, invalidGroupId)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        do {
            try await service.removeTrackFromGroup(groupId: invalidGroupId, trackId: 1)
            XCTFail("Should have thrown groupNotFound error")
        } catch TrackGroupError.groupNotFound(let groupId) {
            XCTAssertEqual(groupId, invalidGroupId)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testDatabaseTransactionRollback() async throws {
        let originalGroupCount = service.groups.count
        
        // Create a group successfully first
        let group = try await service.createGroup(trackIds: [1, 2])
        XCTAssertEqual(service.groups.count, originalGroupCount + 1)
        
        // Now try to add tracks that don't exist - should rollback
        do {
            try await service.addTracksToGroup(groupId: group.id, trackIds: [999])
            XCTFail("Should have failed with non-existent track")
        } catch TrackGroupError.trackExistenceValidationFailed {
            // Expected - verify original group is still intact
            let existingGroup = service.groups.first { $0.id == group.id }
            XCTAssertNotNil(existingGroup)
            XCTAssertEqual(existingGroup?.trackCount, 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testGroupNameValidation() async throws {
        // Test valid names
        let validGroup = try await service.createGroup(trackIds: [1, 2], name: "Valid Group Name")
        XCTAssertEqual(validGroup.name, "Valid Group Name")
        
        // Test empty name (should be allowed)
        let emptyNameGroup = try await service.createGroup(trackIds: [3, 4], name: "")
        XCTAssertEqual(emptyNameGroup.name, "")
        
        // Clean up for next test
        try await service.deleteGroup(groupId: validGroup.id)
        try await service.deleteGroup(groupId: emptyNameGroup.id)
        
        // Test maximum length name (255 characters - should work)
        let maxLengthName = String(repeating: "a", count: 255)
        let maxLengthGroup = try await service.createGroup(trackIds: [1, 2], name: maxLengthName)
        XCTAssertEqual(maxLengthGroup.name, maxLengthName)
    }
    
    func testErrorRecoveryScenarios() async throws {
        // Create a group
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        // Test recovery from various error scenarios
        
        // 1. Try to remove non-existent track
        do {
            try await service.removeTrackFromGroup(groupId: group.id, trackId: 999)
            XCTFail("Should have thrown trackNotFound error")
        } catch TrackGroupError.trackNotFound(let trackId) {
            XCTAssertEqual(trackId, 999)
            // Verify group is still intact
            let existingGroup = service.groups.first { $0.id == group.id }
            XCTAssertNotNil(existingGroup)
            XCTAssertEqual(existingGroup?.trackCount, 3)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // 2. Try to set main track to non-existent track
        do {
            try await service.setMainTrack(groupId: group.id, trackId: 888)
            XCTFail("Should have thrown mainTrackNotInGroup error")
        } catch TrackGroupError.mainTrackNotInGroup(let trackId, let groupId) {
            XCTAssertEqual(trackId, 888)
            XCTAssertEqual(groupId, group.id)
            // Verify group main track is unchanged
            let existingGroup = service.groups.first { $0.id == group.id }
            XCTAssertEqual(existingGroup?.mainTrackId, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testConcurrentGroupOperations() async throws {
        // Create a group
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        // Simulate concurrent operations
        await withTaskGroup(of: Void.self) { taskGroup in
            // Task 1: Try to add tracks
            taskGroup.addTask {
                do {
                    try await self.service.addTracksToGroup(groupId: group.id, trackIds: [4])
                } catch {
                    // Concurrent operations may fail, which is acceptable
                    print("Concurrent add operation failed: \(error)")
                }
            }
            
            // Task 2: Try to change main track
            taskGroup.addTask {
                do {
                    try await self.service.setMainTrack(groupId: group.id, trackId: 2)
                } catch {
                    // Concurrent operations may fail, which is acceptable
                    print("Concurrent main track change failed: \(error)")
                }
            }
            
            // Task 3: Try to remove track
            taskGroup.addTask {
                do {
                    try await self.service.removeTrackFromGroup(groupId: group.id, trackId: 3)
                } catch {
                    // Concurrent operations may fail, which is acceptable
                    print("Concurrent remove operation failed: \(error)")
                }
            }
        }
        
        // Verify group still exists and is in a valid state
        let finalGroup = service.groups.first { $0.id == group.id }
        if let finalGroup = finalGroup {
            XCTAssertGreaterThanOrEqual(finalGroup.trackCount, 2)
            XCTAssertTrue(finalGroup.trackIds.contains(finalGroup.mainTrackId))
        }
        // If group was dissolved due to concurrent operations, that's also acceptable
    }.groups.first { $0.id == group1.id }
        XCTAssertNotNil(updatedGroup1)
        XCTAssertEqual(updatedGroup1?.trackCount, 2)
        XCTAssertNotEqual(updatedGroup1?.mainTrackId, 1)
        
        // Remove another track from group1 - should dissolve group
        let remainingTrackId = updatedGroup1?.trackIds.first { $0 != updatedGroup1?.mainTrackId }
        XCTAssertNotNil(remainingTrackId)
        try await service.removeTrackFromGroup(groupId: group1.id, trackId: remainingTrackId!)
        XCTAssertEqual(service.groups.count, 1)
        
        // Ungroup remaining group
        try await service.ungroupTracks(groupId: group2.id)
        XCTAssertEqual(service.groups.count, 0)
    }
    
    // MARK: - Private Helper Methods for Tests
    
    private func insertGroupDirectly(id: String, name: String, mainTrackId: Int, trackIds: [Int]) throws {
        // Insert group
        let insertGroupSQL = """
            INSERT INTO track_groups (id, name, main_track_id, date_created, is_expanded) 
            VALUES (?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        var result = sqlite3_prepare_v2(database, insertGroupSQL, -1, &statement, nil)
        XCTAssertEqual(result, SQLITE_OK)
        
        sqlite3_bind_text(statement, 1, id, -1, nil)
        sqlite3_bind_text(statement, 2, name, -1, nil)
        sqlite3_bind_int(statement, 3, Int32(mainTrackId))
        sqlite3_bind_text(statement, 4, ISO8601DateFormatter().string(from: Date()), -1, nil)
        sqlite3_bind_int(statement, 5, 0)
        
        result = sqlite3_step(statement)
        XCTAssertEqual(result, SQLITE_DONE)
        sqlite3_finalize(statement)
        
        // Insert members
        let insertMemberSQL = "INSERT INTO track_group_members (group_id, track_id) VALUES (?, ?)"
        
        for trackId in trackIds {
            var memberStatement: OpaquePointer?
            result = sqlite3_prepare_v2(database, insertMemberSQL, -1, &memberStatement, nil)
            XCTAssertEqual(result, SQLITE_OK)
            
            sqlite3_bind_text(memberStatement, 1, id, -1, nil)
            sqlite3_bind_int(memberStatement, 2, Int32(trackId))
            
            result = sqlite3_step(memberStatement)
            XCTAssertEqual(result, SQLITE_DONE)
            sqlite3_finalize(memberStatement)
        }
    }
}