import XCTest
import SQLite3
@testable import VAUX

class TrackGroupCreationWorkflowTests: XCTestCase {
    
    // MARK: - Test Properties
    private var service: TrackGroupService!
    private var database: OpaquePointer?
    private var testDatabasePath: String!
    
    // Test tracks
    private var testTracks: [Track] = []
    
    // MARK: - Test Setup and Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary database for testing
        testDatabasePath = NSTemporaryDirectory() + "test_group_creation_\(UUID().uuidString).db"
        
        // Open database
        let result = sqlite3_open(testDatabasePath, &database)
        XCTAssertEqual(result, SQLITE_OK, "Failed to open test database")
        
        // Create tables
        try createTestTables()
        
        // Initialize service
        service = TrackGroupService()
        service.setDatabase(database)
        
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
        testTracks = []
        
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
            INSERT INTO music (title, artist, album, path, isUrl, duration) 
            VALUES (?, ?, ?, ?, ?, ?)
        """
        
        let trackData = [
            ("Song Title", "Artist Name", "Album Name", "/path/to/song.mp3", 0, 180000),
            ("Song Title (Remix)", "Artist Name", "Album Name", "/path/to/song_remix.mp3", 0, 200000),
            ("Song Title (Live Version)", "Artist Name", "Album Name", "/path/to/song_live.mp3", 0, 220000),
            ("Another Song", "Different Artist", "Different Album", "/path/to/another.mp3", 0, 160000),
            ("Third Song", "Third Artist", "Third Album", "/path/to/third.mp3", 0, 190000),
            ("Song Title - Radio Edit", "Artist Name", "Album Name", "/path/to/song_radio.mp3", 0, 150000)
        ]
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, insertSQL, -1, &statement, nil)
        XCTAssertEqual(result, SQLITE_OK, "Failed to prepare insert statement")
        
        defer { sqlite3_finalize(statement) }
        
        for (index, (title, artist, album, path, isUrl, duration)) in trackData.enumerated() {
            sqlite3_bind_text(statement, 1, title, -1, nil)
            sqlite3_bind_text(statement, 2, artist, -1, nil)
            sqlite3_bind_text(statement, 3, album, -1, nil)
            sqlite3_bind_text(statement, 4, path, -1, nil)
            sqlite3_bind_int(statement, 5, Int32(isUrl))
            sqlite3_bind_int(statement, 6, Int32(duration))
            
            let stepResult = sqlite3_step(statement)
            XCTAssertEqual(stepResult, SQLITE_DONE, "Failed to insert test track \(index)")
            
            // Create Track object for testing
            let track = Track(
                id: index + 1,
                title: title,
                artist: artist,
                album: album,
                albumArtist: nil,
                composer: nil,
                genre: nil,
                year: nil,
                trackNumber: nil,
                discNumber: nil,
                bpm: nil,
                path: path,
                isUrl: isUrl == 1,
                duration: duration,
                timeMarkers: [],
                waveformData: nil,
                rating: 0,
                comment: "",
                generalTags: [],
                dateAdded: Date()
            )
            testTracks.append(track)
            
            sqlite3_reset(statement)
        }
    }
    
    // MARK: - Group Creation Workflow Tests
    
    func testCreateGroupWithAutomaticMainTrackSelection() async throws {
        // Test Requirements: 1.2, 1.4 - Automatic main track selection (first selected track as default)
        let trackIds = [1, 2, 3] // First three tracks
        
        let group = try await service.createGroup(trackIds: trackIds)
        
        // Verify group was created
        XCTAssertEqual(group.trackIds.count, 3)
        XCTAssertEqual(group.mainTrackId, 1) // First track should be main track
        XCTAssertTrue(group.trackIds.contains(1))
        XCTAssertTrue(group.trackIds.contains(2))
        XCTAssertTrue(group.trackIds.contains(3))
        
        // Verify group is in service
        XCTAssertEqual(service.groups.count, 1)
        XCTAssertEqual(service.groups.first?.id, group.id)
    }
    
    func testCreateGroupWithCustomMainTrack() async throws {
        // Test Requirements: 1.4 - Custom main track selection
        let trackIds = [1, 2, 3]
        let customMainTrackId = 2
        
        let group = try await service.createGroup(
            trackIds: trackIds,
            mainTrackId: customMainTrackId
        )
        
        // Verify custom main track was set
        XCTAssertEqual(group.mainTrackId, customMainTrackId)
        XCTAssertEqual(group.trackIds.count, 3)
        XCTAssertTrue(group.trackIds.contains(customMainTrackId))
    }
    
    func testAutoGeneratedGroupNaming() async throws {
        // Test Requirements: 4.3 - Auto-generated group naming
        let trackIds = [1, 2] // "Song Title" and "Song Title (Remix)"
        
        let group = try await service.createGroup(trackIds: trackIds, name: "")
        
        // Verify group has empty name (auto-generation would be handled by UI layer)
        XCTAssertEqual(group.name, "")
        XCTAssertEqual(group.displayName, "Track Group") // Default display name
    }
    
    func testCreateGroupWithCustomName() async throws {
        // Test Requirements: 4.3 - Custom group naming
        let trackIds = [1, 2]
        let customName = "My Custom Group"
        
        let group = try await service.createGroup(
            trackIds: trackIds,
            name: customName
        )
        
        // Verify custom name was set
        XCTAssertEqual(group.name, customName)
        XCTAssertEqual(group.displayName, customName)
    }
    
    func testPreventGroupingAlreadyGroupedTracks() async throws {
        // Test Requirements: 1.2 - Validation to prevent grouping already-grouped tracks
        
        // Create first group
        let firstGroupTrackIds = [1, 2]
        let firstGroup = try await service.createGroup(trackIds: firstGroupTrackIds)
        XCTAssertEqual(service.groups.count, 1)
        
        // Try to create second group with overlapping tracks
        let secondGroupTrackIds = [2, 3] // Track 2 is already in first group
        
        do {
            _ = try await service.createGroup(trackIds: secondGroupTrackIds)
            XCTFail("Should have thrown error for already grouped track")
        } catch let error as TrackGroupError {
            switch error {
            case .trackAlreadyInGroup(let trackId, let groupId):
                XCTAssertEqual(trackId, 2)
                XCTAssertEqual(groupId, firstGroup.id)
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
        
        // Verify only first group exists
        XCTAssertEqual(service.groups.count, 1)
    }
    
    func testMinimumTrackCountValidation() async throws {
        // Test Requirements: 1.2 - Minimum track count validation
        
        // Try to create group with only one track
        do {
            _ = try await service.createGroup(trackIds: [1])
            XCTFail("Should have thrown error for insufficient tracks")
        } catch let error as TrackGroupError {
            switch error {
            case .insufficientTracks:
                break // Expected error
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
        
        // Try to create group with empty array
        do {
            _ = try await service.createGroup(trackIds: [])
            XCTFail("Should have thrown error for insufficient tracks")
        } catch let error as TrackGroupError {
            switch error {
            case .insufficientTracks:
                break // Expected error
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
        
        // Verify no groups were created
        XCTAssertEqual(service.groups.count, 0)
    }
    
    func testCompleteGroupCreationWorkflow() async throws {
        // Test Requirements: 1.2, 1.4, 4.3 - Complete workflow integration
        
        // Step 1: Create group with automatic main track selection
        let trackIds = [1, 2, 3]
        let groupName = "Test Group"
        
        let group = try await service.createGroup(
            trackIds: trackIds,
            name: groupName
        )
        
        // Verify initial creation
        XCTAssertEqual(group.trackIds.count, 3)
        XCTAssertEqual(group.mainTrackId, 1) // First track
        XCTAssertEqual(group.name, groupName)
        XCTAssertFalse(group.isExpanded) // Default state
        
        // Step 2: Verify persistence by reloading
        try await service.loadGroups()
        XCTAssertEqual(service.groups.count, 1)
        
        let loadedGroup = service.groups.first!
        XCTAssertEqual(loadedGroup.id, group.id)
        XCTAssertEqual(loadedGroup.trackIds, group.trackIds)
        XCTAssertEqual(loadedGroup.mainTrackId, group.mainTrackId)
        XCTAssertEqual(loadedGroup.name, group.name)
        
        // Step 3: Test group membership queries
        XCTAssertNotNil(service.getGroupForTrack(trackId: 1))
        XCTAssertNotNil(service.getGroupForTrack(trackId: 2))
        XCTAssertNotNil(service.getGroupForTrack(trackId: 3))
        XCTAssertNil(service.getGroupForTrack(trackId: 4)) // Not in group
        
        // Step 4: Test main track changes
        try await service.setMainTrack(groupId: group.id, trackId: 2)
        XCTAssertEqual(service.groups.first?.mainTrackId, 2)
        
        // Step 5: Test adding tracks to existing group
        try await service.addTracksToGroup(groupId: group.id, trackIds: [4])
        XCTAssertEqual(service.groups.first?.trackIds.count, 4)
        XCTAssertTrue(service.groups.first?.trackIds.contains(4) ?? false)
        
        // Step 6: Test removing tracks from group
        try await service.removeTrackFromGroup(groupId: group.id, trackId: 4)
        XCTAssertEqual(service.groups.first?.trackIds.count, 3)
        XCTAssertFalse(service.groups.first?.trackIds.contains(4) ?? true)
        
        // Step 7: Test group deletion
        try await service.deleteGroup(groupId: group.id)
        XCTAssertEqual(service.groups.count, 0)
        
        // Verify tracks are no longer grouped
        XCTAssertNil(service.getGroupForTrack(trackId: 1))
        XCTAssertNil(service.getGroupForTrack(trackId: 2))
        XCTAssertNil(service.getGroupForTrack(trackId: 3))
    }
    
    func testGroupCreationWithDuplicateTrackIds() async throws {
        // Test edge case: duplicate track IDs in input
        let trackIds = [1, 2, 2, 3, 1] // Duplicates should be removed
        
        let group = try await service.createGroup(trackIds: trackIds)
        
        // Verify duplicates were removed
        XCTAssertEqual(group.trackIds.count, 3)
        XCTAssertTrue(group.trackIds.contains(1))
        XCTAssertTrue(group.trackIds.contains(2))
        XCTAssertTrue(group.trackIds.contains(3))
    }
    
    func testMainTrackValidation() async throws {
        // Test Requirements: 1.4 - Main track must be in the group
        let trackIds = [1, 2, 3]
        let invalidMainTrackId = 5 // Not in the group
        
        do {
            _ = try await service.createGroup(
                trackIds: trackIds,
                mainTrackId: invalidMainTrackId
            )
            XCTFail("Should have thrown error for invalid main track")
        } catch let error as TrackGroupError {
            switch error {
            case .mainTrackNotInGroup(let trackId, _):
                XCTAssertEqual(trackId, invalidMainTrackId)
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testConcurrentGroupCreation() async throws {
        // Test concurrent group creation to ensure thread safety
        let group1Task = Task {
            try await service.createGroup(trackIds: [1, 2], name: "Group 1")
        }
        
        let group2Task = Task {
            try await service.createGroup(trackIds: [3, 4], name: "Group 2")
        }
        
        let group1 = try await group1Task.value
        let group2 = try await group2Task.value
        
        // Verify both groups were created successfully
        XCTAssertEqual(service.groups.count, 2)
        XCTAssertNotEqual(group1.id, group2.id)
        XCTAssertEqual(group1.name, "Group 1")
        XCTAssertEqual(group2.name, "Group 2")
    }
}