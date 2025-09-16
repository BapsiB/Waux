import Testing
import SQLite3
import Foundation
@testable import WAUX

struct TrackGroupDatabaseTests {
    
    // MARK: - Test Database Setup
    
    private func createTestDatabase() throws -> (OpaquePointer?, String) {
        let tempDir = NSTemporaryDirectory()
        let dbPath = "\(tempDir)test_track_groups_\(UUID().uuidString).db"
        
        var db: OpaquePointer?
        let result = sqlite3_open(dbPath, &db)
        
        if result != SQLITE_OK {
            throw TestError.databaseCreationFailed
        }
        
        // Enable foreign keys
        sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
        
        return (db, dbPath)
    }
    
    private func cleanupTestDatabase(_ db: OpaquePointer?, _ path: String) {
        if let db = db {
            sqlite3_close(db)
        }
        try? FileManager.default.removeItem(atPath: path)
    }
    
    private func createMusicTable(_ db: OpaquePointer) throws {
        let createMusicSQL = """
        CREATE TABLE music (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            artist TEXT,
            album TEXT,
            albumArtist TEXT,
            composer TEXT,
            genre TEXT,
            year INTEGER,
            trackNumber INTEGER,
            discNumber INTEGER,
            bpm INTEGER,
            path TEXT NOT NULL,
            isUrl INTEGER NOT NULL DEFAULT 0,
            duration INTEGER,
            timeMarkers TEXT,
            waveformData TEXT,
            rating INTEGER DEFAULT 0,
            comment TEXT,
            generalTags TEXT,
            dateAdded TEXT DEFAULT ''
        )
        """
        
        if sqlite3_exec(db, createMusicSQL, nil, nil, nil) != SQLITE_OK {
            throw TestError.tableCreationFailed
        }
    }
    
    private func insertTestTrack(_ db: OpaquePointer, id: Int, title: String, path: String) throws {
        let insertSQL = "INSERT INTO music (id, title, artist, path) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) != SQLITE_OK {
            throw TestError.insertFailed
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(id))
        sqlite3_bind_text(statement, 2, title, -1, nil)
        sqlite3_bind_text(statement, 3, "Test Artist", -1, nil)
        sqlite3_bind_text(statement, 4, path, -1, nil)
        
        if sqlite3_step(statement) != SQLITE_DONE {
            throw TestError.insertFailed
        }
    }
    
    // MARK: - Schema Creation Tests
    
    @Test func testTrackGroupsTableCreation() throws {
        let (db, path) = try createTestDatabase()
        defer { cleanupTestDatabase(db, path) }
        
        guard let database = db else {
            throw TestError.databaseCreationFailed
        }
        
        // Create track_groups table
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
        
        let result = sqlite3_exec(database, createTrackGroupsSQL, nil, nil, nil)
        #expect(result == SQLITE_OK, "track_groups table should be created successfully")
        
        // Verify table exists
        let checkTableSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='track_groups'"
        var statement: OpaquePointer?
        
        #expect(sqlite3_prepare_v2(database, checkTableSQL, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        
        #expect(sqlite3_step(statement) == SQLITE_ROW, "track_groups table should exist")
        
        let tableName = String(cString: sqlite3_column_text(statement, 0))
        #expect(tableName == "track_groups")
    }
    
    @Test func testTrackGroupMembersTableCreation() throws {
        let (db, path) = try createTestDatabase()
        defer { cleanupTestDatabase(db, path) }
        
        guard let database = db else {
            throw TestError.databaseCreationFailed
        }
        
        // Create track_group_members table
        let createTrackGroupMembersSQL = """
        CREATE TABLE track_group_members (
            group_id TEXT NOT NULL,
            track_id INTEGER NOT NULL,
            PRIMARY KEY (group_id, track_id),
            FOREIGN KEY (group_id) REFERENCES track_groups (id) ON DELETE CASCADE,
            FOREIGN KEY (track_id) REFERENCES music (id) ON DELETE CASCADE
        )
        """
        
        let result = sqlite3_exec(database, createTrackGroupMembersSQL, nil, nil, nil)
        #expect(result == SQLITE_OK, "track_group_members table should be created successfully")
        
        // Verify table exists
        let checkTableSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='track_group_members'"
        var statement: OpaquePointer?
        
        #expect(sqlite3_prepare_v2(database, checkTableSQL, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        
        #expect(sqlite3_step(statement) == SQLITE_ROW, "track_group_members table should exist")
        
        let tableName = String(cString: sqlite3_column_text(statement, 0))
        #expect(tableName == "track_group_members")
    }
    
    // MARK: - Foreign Key Constraint Tests
    
    @Test func testForeignKeyConstraintEnforcement() throws {
        let (db, path) = try createTestDatabase()
        defer { cleanupTestDatabase(db, path) }
        
        guard let database = db else {
            throw TestError.databaseCreationFailed
        }
        
        // Create all necessary tables
        try createMusicTable(database)
        
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
        
        #expect(sqlite3_exec(database, createTrackGroupsSQL, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, createTrackGroupMembersSQL, nil, nil, nil) == SQLITE_OK)
        
        // Insert test tracks
        try insertTestTrack(database, id: 1, title: "Track 1", path: "/path/to/track1.mp3")
        try insertTestTrack(database, id: 2, title: "Track 2", path: "/path/to/track2.mp3")
        
        // Insert valid track group
        let insertGroupSQL = """
        INSERT INTO track_groups (id, name, main_track_id, date_created, is_expanded)
        VALUES ('group1', 'Test Group', 1, '2024-01-01T00:00:00Z', 0)
        """
        #expect(sqlite3_exec(database, insertGroupSQL, nil, nil, nil) == SQLITE_OK)
        
        // Insert valid group members
        let insertMember1SQL = "INSERT INTO track_group_members (group_id, track_id) VALUES ('group1', 1)"
        let insertMember2SQL = "INSERT INTO track_group_members (group_id, track_id) VALUES ('group1', 2)"
        #expect(sqlite3_exec(database, insertMember1SQL, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, insertMember2SQL, nil, nil, nil) == SQLITE_OK)
        
        // Test foreign key constraint violation - invalid main_track_id
        let insertInvalidGroupSQL = """
        INSERT INTO track_groups (id, name, main_track_id, date_created, is_expanded)
        VALUES ('group2', 'Invalid Group', 999, '2024-01-01T00:00:00Z', 0)
        """
        #expect(sqlite3_exec(database, insertInvalidGroupSQL, nil, nil, nil) != SQLITE_OK, "Should fail due to foreign key constraint")
        
        // Test foreign key constraint violation - invalid group_id in members
        let insertInvalidMemberSQL = "INSERT INTO track_group_members (group_id, track_id) VALUES ('nonexistent', 1)"
        #expect(sqlite3_exec(database, insertInvalidMemberSQL, nil, nil, nil) != SQLITE_OK, "Should fail due to foreign key constraint")
        
        // Test foreign key constraint violation - invalid track_id in members
        let insertInvalidTrackMemberSQL = "INSERT INTO track_group_members (group_id, track_id) VALUES ('group1', 999)"
        #expect(sqlite3_exec(database, insertInvalidTrackMemberSQL, nil, nil, nil) != SQLITE_OK, "Should fail due to foreign key constraint")
    }
    
    // MARK: - Cascade Deletion Tests
    
    @Test func testCascadeDeletionOnTrackRemoval() throws {
        let (db, path) = try createTestDatabase()
        defer { cleanupTestDatabase(db, path) }
        
        guard let database = db else {
            throw TestError.databaseCreationFailed
        }
        
        // Setup tables and data
        try createMusicTable(database)
        
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
        
        #expect(sqlite3_exec(database, createTrackGroupsSQL, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, createTrackGroupMembersSQL, nil, nil, nil) == SQLITE_OK)
        
        // Insert test data
        try insertTestTrack(database, id: 1, title: "Track 1", path: "/path/to/track1.mp3")
        try insertTestTrack(database, id: 2, title: "Track 2", path: "/path/to/track2.mp3")
        try insertTestTrack(database, id: 3, title: "Track 3", path: "/path/to/track3.mp3")
        
        let insertGroupSQL = """
        INSERT INTO track_groups (id, name, main_track_id, date_created, is_expanded)
        VALUES ('group1', 'Test Group', 1, '2024-01-01T00:00:00Z', 0)
        """
        #expect(sqlite3_exec(database, insertGroupSQL, nil, nil, nil) == SQLITE_OK)
        
        let insertMember1SQL = "INSERT INTO track_group_members (group_id, track_id) VALUES ('group1', 1)"
        let insertMember2SQL = "INSERT INTO track_group_members (group_id, track_id) VALUES ('group1', 2)"
        #expect(sqlite3_exec(database, insertMember1SQL, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, insertMember2SQL, nil, nil, nil) == SQLITE_OK)
        
        // Verify data exists
        var statement: OpaquePointer?
        let countGroupsSQL = "SELECT COUNT(*) FROM track_groups WHERE id = 'group1'"
        #expect(sqlite3_prepare_v2(database, countGroupsSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 1, "Group should exist before deletion")
        sqlite3_finalize(statement)
        
        let countMembersSQL = "SELECT COUNT(*) FROM track_group_members WHERE group_id = 'group1'"
        #expect(sqlite3_prepare_v2(database, countMembersSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 2, "Should have 2 members before deletion")
        sqlite3_finalize(statement)
        
        // Delete the main track (should cascade delete the group)
        let deleteTrackSQL = "DELETE FROM music WHERE id = 1"
        #expect(sqlite3_exec(database, deleteTrackSQL, nil, nil, nil) == SQLITE_OK)
        
        // Verify cascade deletion worked
        #expect(sqlite3_prepare_v2(database, countGroupsSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 0, "Group should be deleted due to cascade")
        sqlite3_finalize(statement)
        
        #expect(sqlite3_prepare_v2(database, countMembersSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 0, "Members should be deleted due to cascade")
        sqlite3_finalize(statement)
    }
    
    @Test func testCascadeDeletionOnGroupRemoval() throws {
        let (db, path) = try createTestDatabase()
        defer { cleanupTestDatabase(db, path) }
        
        guard let database = db else {
            throw TestError.databaseCreationFailed
        }
        
        // Setup tables and data
        try createMusicTable(database)
        
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
        
        #expect(sqlite3_exec(database, createTrackGroupsSQL, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, createTrackGroupMembersSQL, nil, nil, nil) == SQLITE_OK)
        
        // Insert test data
        try insertTestTrack(database, id: 1, title: "Track 1", path: "/path/to/track1.mp3")
        try insertTestTrack(database, id: 2, title: "Track 2", path: "/path/to/track2.mp3")
        
        let insertGroupSQL = """
        INSERT INTO track_groups (id, name, main_track_id, date_created, is_expanded)
        VALUES ('group1', 'Test Group', 1, '2024-01-01T00:00:00Z', 0)
        """
        #expect(sqlite3_exec(database, insertGroupSQL, nil, nil, nil) == SQLITE_OK)
        
        let insertMember1SQL = "INSERT INTO track_group_members (group_id, track_id) VALUES ('group1', 1)"
        let insertMember2SQL = "INSERT INTO track_group_members (group_id, track_id) VALUES ('group1', 2)"
        #expect(sqlite3_exec(database, insertMember1SQL, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, insertMember2SQL, nil, nil, nil) == SQLITE_OK)
        
        // Verify members exist
        var statement: OpaquePointer?
        let countMembersSQL = "SELECT COUNT(*) FROM track_group_members WHERE group_id = 'group1'"
        #expect(sqlite3_prepare_v2(database, countMembersSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 2, "Should have 2 members before group deletion")
        sqlite3_finalize(statement)
        
        // Delete the group (should cascade delete members)
        let deleteGroupSQL = "DELETE FROM track_groups WHERE id = 'group1'"
        #expect(sqlite3_exec(database, deleteGroupSQL, nil, nil, nil) == SQLITE_OK)
        
        // Verify cascade deletion worked
        #expect(sqlite3_prepare_v2(database, countMembersSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 0, "Members should be deleted due to cascade")
        sqlite3_finalize(statement)
        
        // Verify tracks still exist (should not be affected)
        let countTracksSQL = "SELECT COUNT(*) FROM music"
        #expect(sqlite3_prepare_v2(database, countTracksSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 2, "Tracks should still exist after group deletion")
        sqlite3_finalize(statement)
    }
    
    // MARK: - Migration Tests
    
    @Test func testMigrationFromExistingDatabase() throws {
        let (db, path) = try createTestDatabase()
        defer { cleanupTestDatabase(db, path) }
        
        guard let database = db else {
            throw TestError.databaseCreationFailed
        }
        
        // Create existing database structure (without track groups)
        try createMusicTable(database)
        
        // Insert some test tracks
        try insertTestTrack(database, id: 1, title: "Track 1", path: "/path/to/track1.mp3")
        try insertTestTrack(database, id: 2, title: "Track 2", path: "/path/to/track2.mp3")
        
        // Verify track groups tables don't exist
        let checkTrackGroupsSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='track_groups'"
        var statement: OpaquePointer?
        
        #expect(sqlite3_prepare_v2(database, checkTrackGroupsSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) != SQLITE_ROW, "track_groups table should not exist initially")
        sqlite3_finalize(statement)
        
        // Simulate migration by creating track groups tables
        let createTrackGroupsSQL = """
        CREATE TABLE IF NOT EXISTS track_groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL DEFAULT '',
            main_track_id INTEGER NOT NULL,
            date_created TEXT NOT NULL,
            is_expanded INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (main_track_id) REFERENCES music (id) ON DELETE CASCADE
        )
        """
        
        let createTrackGroupMembersSQL = """
        CREATE TABLE IF NOT EXISTS track_group_members (
            group_id TEXT NOT NULL,
            track_id INTEGER NOT NULL,
            PRIMARY KEY (group_id, track_id),
            FOREIGN KEY (group_id) REFERENCES track_groups (id) ON DELETE CASCADE,
            FOREIGN KEY (track_id) REFERENCES music (id) ON DELETE CASCADE
        )
        """
        
        #expect(sqlite3_exec(database, createTrackGroupsSQL, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, createTrackGroupMembersSQL, nil, nil, nil) == SQLITE_OK)
        
        // Verify tables now exist
        #expect(sqlite3_prepare_v2(database, checkTrackGroupsSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW, "track_groups table should exist after migration")
        sqlite3_finalize(statement)
        
        let checkMembersSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='track_group_members'"
        #expect(sqlite3_prepare_v2(database, checkMembersSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW, "track_group_members table should exist after migration")
        sqlite3_finalize(statement)
        
        // Verify existing data is intact
        let countTracksSQL = "SELECT COUNT(*) FROM music"
        #expect(sqlite3_prepare_v2(database, countTracksSQL, -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 2, "Existing tracks should be preserved after migration")
        sqlite3_finalize(statement)
    }
    
    // MARK: - Integration Tests with CollectionService
    
    @Test func testCollectionServiceMigration() async throws {
        let tempDir = NSTemporaryDirectory()
        let dbPath = "\(tempDir)test_collection_migration_\(UUID().uuidString).db"
        
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
        }
        
        // Create a CollectionService and test database creation
        let collectionService = CollectionService()
        
        // Create new database with track groups schema
        try collectionService.createNewLocalDatabase(at: dbPath)
        
        // Verify the database was created with track groups tables
        #expect(collectionService.testDatabaseConnection(path: dbPath), "Database connection should work")
        
        // Open the database to verify schema
        let definition = CollectionDefinition(
            id: UUID().uuidString,
            name: "Test Collection",
            type: .local,
            dbPath: dbPath,
            rootPath: nil
        )
        
        try await collectionService.openCollection(definition)
        
        // Verify we can load track groups (should be empty initially)
        let groups = try await collectionService.loadTrackGroups()
        #expect(groups.isEmpty, "New database should have no track groups")
        
        collectionService.closeCollection()
    }
}

// MARK: - Test Errors

enum TestError: Error {
    case databaseCreationFailed
    case tableCreationFailed
    case insertFailed
}