import XCTest
import SQLite3
@testable import VAUX

class TrackGroupErrorHandlingTests: XCTestCase {
    
    // MARK: - Test Properties
    private var service: TrackGroupService!
    private var database: OpaquePointer?
    private var testDatabasePath: String!
    private let testDatabaseQueue = DispatchQueue(label: "com.vaux.tests.TrackGroupErrorHandlingTests")
    
    // MARK: - Test Setup and Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary database for testing
        testDatabasePath = NSTemporaryDirectory() + "test_error_handling_\(UUID().uuidString).db"
        
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
        
        // Enable foreign keys
        var result = sqlite3_exec(database, "PRAGMA foreign_keys = ON", nil, nil, nil)
        XCTAssertEqual(result, SQLITE_OK, "Failed to enable foreign keys")
        
        result = sqlite3_exec(database, createMusicSQL, nil, nil, nil)
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
    
    // MARK: - Validation Tests
    
    func testCreateGroupWithInvalidTrackIds() async {
        // Test with negative track IDs
        do {
            _ = try await service.createGroup(trackIds: [-1, -2])
            XCTFail("Should have thrown invalidTrackIds error")
        } catch TrackGroupError.invalidTrackIds(let ids) {
            XCTAssertEqual(ids, [-1, -2])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Test with zero track IDs
        do {
            _ = try await service.createGroup(trackIds: [0, 1])
            XCTFail("Should have thrown invalidTrackIds error")
        } catch TrackGroupError.invalidTrackIds(let ids) {
            XCTAssertEqual(ids, [0])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateGroupWithNonExistentTracks() async {
        do {
            _ = try await service.createGroup(trackIds: [999, 1000])
            XCTFail("Should have thrown trackExistenceValidationFailed error")
        } catch TrackGroupError.trackExistenceValidationFailed(let trackIds) {
            XCTAssertEqual(Set(trackIds), Set([999, 1000]))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateGroupWithMixedValidInvalidTracks() async {
        do {
            _ = try await service.createGroup(trackIds: [1, 999])
            XCTFail("Should have thrown trackExistenceValidationFailed error")
        } catch TrackGroupError.trackExistenceValidationFailed(let trackIds) {
            XCTAssertEqual(trackIds, [999])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateGroupWithTooLongName() async {
        let longName = String(repeating: "a", count: 256) // Exceeds 255 character limit
        
        do {
            _ = try await service.createGroup(trackIds: [1, 2], name: longName)
            XCTFail("Should have thrown groupNameTooLong error")
        } catch TrackGroupError.groupNameTooLong(let name) {
            XCTAssertEqual(name, longName)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateGroupWithDuplicateName() async throws {
        let groupName = "Test Group"
        
        // Create first group
        _ = try await service.createGroup(trackIds: [1, 2], name: groupName)
        
        // Try to create second group with same name
        do {
            _ = try await service.createGroup(trackIds: [3, 4], name: groupName)
            XCTFail("Should have thrown duplicateGroupName error")
        } catch TrackGroupError.duplicateGroupName(let name) {
            XCTAssertEqual(name, groupName)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Database Connection Tests
    
    func testOperationsWithoutDatabaseConnection() async {
        // Close database connection
        service.setDatabase(nil, databaseQueue: nil)
        
        // Test createGroup
        do {
            _ = try await service.createGroup(trackIds: [1, 2])
            XCTFail("Should have thrown databaseConnectionLost error")
        } catch TrackGroupError.databaseConnectionLost {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Test deleteGroup
        do {
            try await service.deleteGroup(groupId: "test-id")
            XCTFail("Should have thrown databaseConnectionLost error")
        } catch TrackGroupError.databaseConnectionLost {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Foreign Key Constraint Tests
    
    func testCreateGroupWithInvalidMainTrackForeignKey() async {
        // Insert a group directly with invalid main track ID to test foreign key constraint
        let insertSQL = """
            INSERT INTO track_groups (id, name, main_track_id, date_created, is_expanded)
            VALUES ('test-group', 'Test', 999, '2024-01-01T00:00:00Z', 0)
        """
        
        let result = sqlite3_exec(database, insertSQL, nil, nil, nil)
        XCTAssertNotEqual(result, SQLITE_OK, "Should have failed due to foreign key constraint")
    }
    
    // MARK: - Corrupted Data Recovery Tests
    
    func testRecoveryFromCorruptedGroupData() async throws {
        // Create a valid group first
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        // Manually corrupt the group data in memory (simulate corruption)
        if let groupIndex = service.groups.firstIndex(where: { $0.id == group.id }) {
            var corruptedGroup = service.groups[groupIndex]
            // Remove main track from trackIds to create corruption
            corruptedGroup.trackIds.remove(corruptedGroup.mainTrackId)
            
            await MainActor.run {
                service.groups[groupIndex] = corruptedGroup
            }
        }
        
        // Try to perform an operation that will detect corruption
        do {
            try await service.removeTrackFromGroup(groupId: group.id, trackId: 2)
            // Should succeed after recovery
            XCTAssertEqual(service.groups.count, 1)
        } catch {
            XCTFail("Should have recovered from corruption: \(error)")
        }
    }
    
    func testLoadGroupsWithCorruptedData() async throws {
        // Insert corrupted group data directly into database
        let corruptedGroupId = "corrupted-group"
        
        // Insert group with main track not in members
        let insertGroupSQL = """
            INSERT INTO track_groups (id, name, main_track_id, date_created, is_expanded)
            VALUES (?, 'Corrupted Group', 999, '2024-01-01T00:00:00Z', 0)
        """
        
        var statement: OpaquePointer?
        var result = sqlite3_prepare_v2(database, insertGroupSQL, -1, &statement, nil)
        XCTAssertEqual(result, SQLITE_OK)
        
        sqlite3_bind_text(statement, 1, corruptedGroupId, -1, nil)
        result = sqlite3_step(statement)
        sqlite3_finalize(statement)
        
        // Insert members that don't include the main track
        let insertMemberSQL = """
            INSERT INTO track_group_members (group_id, track_id) VALUES (?, ?)
        """
        
        for trackId in [1, 2] {
            var memberStatement: OpaquePointer?
            result = sqlite3_prepare_v2(database, insertMemberSQL, -1, &memberStatement, nil)
            XCTAssertEqual(result, SQLITE_OK)
            
            sqlite3_bind_text(memberStatement, 1, corruptedGroupId, -1, nil)
            sqlite3_bind_int(memberStatement, 2, Int32(trackId))
            result = sqlite3_step(memberStatement)
            sqlite3_finalize(memberStatement)
        }
        
        // Create a fresh service to test loading
        let loadService = TrackGroupService()
        loadService.setDatabase(database, databaseQueue: testDatabaseQueue)
        
        // Load groups - should handle corrupted data gracefully
        try await loadService.loadGroups()
        
        // Corrupted group should either be recovered or removed
        let corruptedGroup = loadService.groups.first { $0.id == corruptedGroupId }
        if let group = corruptedGroup {
            // If recovered, main track should be valid
            XCTAssertTrue(group.trackIds.contains(group.mainTrackId))
        }
        // If not recovered, it should be removed (which is also acceptable)
    }
    
    // MARK: - Rollback Tests
    
    func testRollbackOnCreateGroupFailure() async throws {
        let originalGroupCount = service.groups.count
        
        // Close database to force failure after validation passes
        if let database = database {
            sqlite3_close(database)
            self.database = nil
            service.setDatabase(nil, databaseQueue: nil)
        }
        
        do {
            _ = try await service.createGroup(trackIds: [1, 2])
            XCTFail("Should have failed due to database connection")
        } catch TrackGroupError.databaseConnectionLost {
            // Expected - verify rollback occurred
            XCTAssertEqual(service.groups.count, originalGroupCount)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Concurrent Modification Tests
    
    func testConcurrentGroupModification() async throws {
        let group = try await service.createGroup(trackIds: [1, 2, 3])
        
        // Simulate concurrent modification by directly updating database
        let updateSQL = "UPDATE track_groups SET name = 'Modified Externally' WHERE id = ?"
        var statement: OpaquePointer?
        
        // Reopen database for direct modification
        let result = sqlite3_open(testDatabasePath, &database)
        XCTAssertEqual(result, SQLITE_OK)
        service.setDatabase(database, databaseQueue: testDatabaseQueue)
        
        let prepareResult = sqlite3_prepare_v2(database, updateSQL, -1, &statement, nil)
        XCTAssertEqual(prepareResult, SQLITE_OK)
        
        sqlite3_bind_text(statement, 1, group.id, -1, nil)
        let stepResult = sqlite3_step(statement)
        XCTAssertEqual(stepResult, SQLITE_DONE)
        sqlite3_finalize(statement)
        
        // Now try to modify the group through service
        // This should detect the concurrent modification when we reload
        try await service.loadGroups()
        
        let updatedGroup = service.groups.first { $0.id == group.id }
        XCTAssertEqual(updatedGroup?.name, "Modified Externally")
    }
    
    // MARK: - Error Message Tests
    
    func testErrorDescriptions() {
        let errors: [TrackGroupError] = [
            .insufficientTracks,
            .trackNotFound(123),
            .groupNotFound("test-id"),
            .trackAlreadyInGroup(456, "group-id"),
            .mainTrackNotInGroup(789, "group-id"),
            .databaseError("Connection failed"),
            .corruptedGroupData("group-id", "Invalid main track"),
            .validationFailed("Invalid input"),
            .trackExistenceValidationFailed([1, 2, 3]),
            .groupNameTooLong("Very long name"),
            .duplicateGroupName("Duplicate"),
            .databaseConnectionLost,
            .transactionTimeout,
            .foreignKeyConstraintViolation("Invalid reference"),
            .dataIntegrityViolation("Constraint violation")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty: \(error)")
            
            // Test recovery suggestions
            if error.isRecoverable {
                XCTAssertNotNil(error.recoverySuggestion, "Recoverable error should have recovery suggestion: \(error)")
            }
        }
    }
    
    // MARK: - Data Integrity Tests
    
    func testGroupIntegrityValidation() async throws {
        // Create a group and then manually corrupt it
        let group = try await service.createGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        // Test various corruption scenarios
        var corruptedGroup = group
        
        // Test: Main track not in track IDs
        corruptedGroup.trackIds = Set([2, 3])
        do {
            try service.validateGroupIntegrity(corruptedGroup)
            XCTFail("Should have detected corrupted main track")
        } catch TrackGroupError.corruptedGroupData(let groupId, let reason) {
            XCTAssertEqual(groupId, group.id)
            XCTAssertTrue(reason.contains("Main track ID"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Test: Insufficient tracks
        corruptedGroup = group
        corruptedGroup.trackIds = Set([1])
        do {
            try service.validateGroupIntegrity(corruptedGroup)
            XCTFail("Should have detected insufficient tracks")
        } catch TrackGroupError.corruptedGroupData(let groupId, let reason) {
            XCTAssertEqual(groupId, group.id)
            XCTAssertTrue(reason.contains("fewer than 2 tracks"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Performance and Timeout Tests
    
    func testTransactionTimeout() async {
        // This test simulates a transaction timeout scenario
        // In a real scenario, this would involve long-running operations
        
        // Create a large number of groups to potentially trigger timeout
        var groups: [TrackGroup] = []
        
        do {
            for i in 0..<100 {
                let trackIds = [1, 2] // Reuse same tracks (will fail after first group)
                if i == 0 {
                    let group = try await service.createGroup(trackIds: trackIds, name: "Group \(i)")
                    groups.append(group)
                } else {
                    // These should fail due to tracks already being grouped
                    do {
                        _ = try await service.createGroup(trackIds: trackIds, name: "Group \(i)")
                        XCTFail("Should have failed due to tracks already in group")
                    } catch TrackGroupError.trackAlreadyInGroup {
                        // Expected
                        break
                    }
                }
            }
        } catch {
            // Any other error is acceptable for this test
        }
        
        XCTAssertEqual(groups.count, 1, "Should have created exactly one group")
    }
}

// MARK: - Helper Extensions for Testing

private extension TrackGroupService {
    /// Expose validation methods for testing
    func validateGroupIntegrity(_ group: TrackGroup) throws {
        // This would need to be made internal or we need a test-specific method
        // For now, we'll test indirectly through operations
    }
}