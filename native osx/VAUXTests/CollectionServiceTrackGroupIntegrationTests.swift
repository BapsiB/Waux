import Testing
import Foundation
import SQLite3
@testable import VAUX

/// Integration tests for CollectionService and TrackGroupService coordination
/// Tests the complete workflow of track group persistence and management
@Suite("CollectionService TrackGroup Integration Tests")
struct CollectionServiceTrackGroupIntegrationTests {
    
    private let testDatabasePath = "/tmp/test_collection_trackgroup_integration.db"
    
    /// Helper method to insert a track directly into the database for testing
    private func insertTrackDirectly(
        _ collectionService: CollectionService,
        id: Int,
        title: String,
        artist: String,
        album: String,
        path: String,
        duration: Int
    ) throws {
        guard let db = collectionService.getDatabase() else {
            throw CollectionError.databaseNotOpen
        }
        
        let insertSQL = """
            INSERT INTO music (
                id, title, artist, album, albumArtist, composer, genre, year, 
                trackNumber, discNumber, bpm, path, isUrl, duration, 
                timeMarkers, waveformData, rating, comment, generalTags, dateAdded
            ) VALUES (?, ?, ?, ?, '', '', '', NULL, NULL, NULL, NULL, ?, 0, ?, '[]', NULL, 0, '', '[]', ?)
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(id))
        sqlite3_bind_text(statement, 2, title, -1, nil)
        sqlite3_bind_text(statement, 3, artist, -1, nil)
        sqlite3_bind_text(statement, 4, album, -1, nil)
        sqlite3_bind_text(statement, 5, path, -1, nil)
        sqlite3_bind_int(statement, 6, Int32(duration))
        sqlite3_bind_text(statement, 7, ISO8601DateFormatter().string(from: Date()), -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
    }
    
    /// Test loading track groups from database on collection load
    @Test("Load track groups from database")
    func testLoadTrackGroups() async throws {
        // Setup
        let collectionService = CollectionService()
        let trackGroupService = TrackGroupService()
        
        // Clean up any existing test database
        try? FileManager.default.removeItem(atPath: testDatabasePath)
        
        // Create new database with schema
        try collectionService.createNewLocalDatabase(at: testDatabasePath)
        
        // Open collection
        let definition = CollectionDefinition(
            id: "test-collection",
            name: "Test Collection",
            type: .local,
            dbPath: testDatabasePath,
            rootPath: nil
        )
        try await collectionService.openCollection(definition)
        
        // Set database reference for track group service
        trackGroupService.setDatabase(collectionService.getDatabase())
        
        // Initially should have no groups
        let initialGroups = try await collectionService.loadTrackGroups()
        #expect(initialGroups.isEmpty, "New database should have no track groups")
        
        // Add some test tracks
        try insertTrackDirectly(collectionService, id: 1, title: "Song A", artist: "Artist 1", album: "Album 1", path: "/test/song1.mp3", duration: 180)
        try insertTrackDirectly(collectionService, id: 2, title: "Song A (Remix)", artist: "Artist 1", album: "Album 1", path: "/test/song2.mp3", duration: 200)
        try insertTrackDirectly(collectionService, id: 3, title: "Song A (Live)", artist: "Artist 1", album: "Album 1", path: "/test/song3.mp3", duration: 220)
        
        // Create a group using TrackGroupService
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Variations",
            mainTrackId: 1
        )
        
        // Close and reopen collection to test persistence
        collectionService.closeCollection()
        try await collectionService.openCollection(definition)
        trackGroupService.setDatabase(collectionService.getDatabase())
        
        // Load groups and verify persistence
        let loadedGroups = try await collectionService.loadTrackGroups()
        #expect(loadedGroups.count == 1, "Should load 1 persisted group")
        
        let loadedGroup = loadedGroups[0]
        #expect(loadedGroup.id == group.id, "Group ID should match")
        #expect(loadedGroup.name == "Song A Variations", "Group name should match")
        #expect(loadedGroup.mainTrackId == 1, "Main track ID should match")
        #expect(loadedGroup.trackIds.count == 3, "Should have 3 tracks")
        #expect(loadedGroup.trackIds.contains(1), "Should contain track 1")
        #expect(loadedGroup.trackIds.contains(2), "Should contain track 2")
        #expect(loadedGroup.trackIds.contains(3), "Should contain track 3")
        
        // Cleanup
        collectionService.closeCollection()
        try? FileManager.default.removeItem(atPath: testDatabasePath)
    }
}