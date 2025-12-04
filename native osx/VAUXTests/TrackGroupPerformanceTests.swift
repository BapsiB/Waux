import XCTest
import SQLite3
@testable import VAUX

class TrackGroupPerformanceTests: XCTestCase {
    
    // MARK: - Test Properties
    private var trackGroupService: TrackGroupService!
    private var trackDisplayService: TrackDisplayService!
    private var collectionService: CollectionService!
    private var database: OpaquePointer?
    private var testDatabasePath: String!
    
    // MARK: - Performance Test Configuration
    private let smallCollectionSize = 100
    private let mediumCollectionSize = 1000
    private let largeCollectionSize = 10000
    private let groupsPercentage = 0.3 // 30% of tracks will be in groups
    private let tracksPerGroup = 4 // Average tracks per group
    
    // MARK: - Test Setup and Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary database for testing
        testDatabasePath = NSTemporaryDirectory() + "test_performance_\(UUID().uuidString).db"
        
        // Initialize services
        collectionService = CollectionService()
        try collectionService.createNewLocalDatabase(at: testDatabasePath)
        
        // Open database for direct access
        let result = sqlite3_open(testDatabasePath, &database)
        XCTAssertEqual(result, SQLITE_OK, "Failed to open test database")
        
        // Initialize services
        trackGroupService = TrackGroupService()
        trackGroupService.setDatabase(database)
        trackDisplayService = TrackDisplayService(trackGroupService: trackGroupService)
        
        print("🚀 Performance test setup complete")
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
        
        trackGroupService = nil
        trackDisplayService = nil
        collectionService = nil
        database = nil
        testDatabasePath = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Performance Test Methods
    
    /// Tests performance of group membership lookups with small collection
    func testGroupMembershipLookupPerformance_SmallCollection() async throws {
        let tracks = try await createTestTracks(count: smallCollectionSize)
        let groups = try await createTestGroups(for: tracks)
        
        // Measure individual lookups
        measure {
            for track in tracks {
                guard let trackId = track.id else { continue }
                _ = trackGroupService.getGroupForTrack(trackId: trackId)
            }
        }
        
        print("✅ Small collection lookup test completed: \(tracks.count) tracks, \(groups.count) groups")
    }
    
    /// Tests performance of group membership lookups with medium collection
    func testGroupMembershipLookupPerformance_MediumCollection() async throws {
        let tracks = try await createTestTracks(count: mediumCollectionSize)
        let groups = try await createTestGroups(for: tracks)
        
        // Measure individual lookups
        measure {
            for track in tracks {
                guard let trackId = track.id else { continue }
                _ = trackGroupService.getGroupForTrack(trackId: trackId)
            }
        }
        
        print("✅ Medium collection lookup test completed: \(tracks.count) tracks, \(groups.count) groups")
    }
    
    /// Tests performance of group membership lookups with large collection
    func testGroupMembershipLookupPerformance_LargeCollection() async throws {
        let tracks = try await createTestTracks(count: largeCollectionSize)
        let groups = try await createTestGroups(for: tracks)
        
        // Measure individual lookups
        measure {
            for track in tracks {
                guard let trackId = track.id else { continue }
                _ = trackGroupService.getGroupForTrack(trackId: trackId)
            }
        }
        
        print("✅ Large collection lookup test completed: \(tracks.count) tracks, \(groups.count) groups")
    }
    
    /// Tests performance of batch group lookups vs individual lookups
    func testBatchVsIndividualLookupPerformance() async throws {
        let tracks = try await createTestTracks(count: mediumCollectionSize)
        let groups = try await createTestGroups(for: tracks)
        let trackIds = tracks.compactMap { $0.id }
        
        // Measure individual lookups
        let individualTime = measureTime {
            for trackId in trackIds {
                _ = trackGroupService.getGroupForTrack(trackId: trackId)
            }
        }
        
        // Measure batch lookup
        let batchTime = measureTime {
            _ = trackGroupService.getGroupsForTracks(trackIds)
        }
        
        print("📊 Lookup Performance Comparison:")
        print("   Individual lookups: \(String(format: "%.3f", individualTime))s")
        print("   Batch lookup: \(String(format: "%.3f", batchTime))s")
        print("   Speedup: \(String(format: "%.1f", individualTime / batchTime))x")
        
        // Batch should be significantly faster
        XCTAssertLessThan(batchTime, individualTime * 0.5, "Batch lookup should be at least 2x faster")
    }
    
    /// Tests performance of display item conversion with different collection sizes
    func testDisplayItemConversionPerformance() async throws {
        let testSizes = [smallCollectionSize, mediumCollectionSize]
        
        for size in testSizes {
            let tracks = try await createTestTracks(count: size)
            let groups = try await createTestGroups(for: tracks)
            
            let conversionTime = measureTime {
                _ = trackDisplayService.convertTracksToDisplayItems(tracks)
            }
            
            print("📊 Display Conversion Performance (\(size) tracks, \(groups.count) groups): \(String(format: "%.3f", conversionTime))s")
            
            // Performance expectations (adjust based on actual performance)
            let expectedMaxTime = size < 1000 ? 0.1 : 1.0
            XCTAssertLessThan(conversionTime, expectedMaxTime, "Conversion should complete within \(expectedMaxTime)s for \(size) tracks")
        }
    }
    
    /// Tests performance of cache effectiveness
    func testCacheEffectivenessPerformance() async throws {
        let tracks = try await createTestTracks(count: mediumCollectionSize)
        let groups = try await createTestGroups(for: tracks)
        
        // First conversion (cache miss)
        let firstConversionTime = measureTime {
            _ = trackDisplayService.convertTracksToDisplayItems(tracks)
        }
        
        // Second conversion (cache hit)
        let secondConversionTime = measureTime {
            _ = trackDisplayService.convertTracksToDisplayItems(tracks)
        }
        
        print("📊 Cache Performance:")
        print("   First conversion (cache miss): \(String(format: "%.3f", firstConversionTime))s")
        print("   Second conversion (cache hit): \(String(format: "%.3f", secondConversionTime))s")
        print("   Cache speedup: \(String(format: "%.1f", firstConversionTime / secondConversionTime))x")
        
        // Cache should provide significant speedup
        XCTAssertLessThan(secondConversionTime, firstConversionTime * 0.3, "Cache should provide at least 3x speedup")
    }
    
    /// Tests performance of group operations under load
    func testGroupOperationsPerformanceUnderLoad() async throws {
        let tracks = try await createTestTracks(count: mediumCollectionSize)
        
        // Measure group creation performance
        let creationTime = measureTime {
            Task {
                for i in stride(from: 0, to: tracks.count - tracksPerGroup, by: tracksPerGroup * 2) {
                    let groupTracks = Array(tracks[i..<min(i + tracksPerGroup, tracks.count)])
                    let trackIds = groupTracks.compactMap { $0.id }
                    
                    if trackIds.count >= 2 {
                        do {
                            _ = try await trackGroupService.createGroup(
                                trackIds: trackIds,
                                name: "Performance Test Group \(i / tracksPerGroup)"
                            )
                        } catch {
                            print("⚠️ Failed to create group: \(error)")
                        }
                    }
                }
            }
        }
        
        print("📊 Group Creation Performance: \(String(format: "%.3f", creationTime))s for \(trackGroupService.groups.count) groups")
        
        // Performance expectation
        XCTAssertLessThan(creationTime, 5.0, "Group creation should complete within 5 seconds")
    }
    
    /// Tests memory usage with large collections
    func testMemoryUsageWithLargeCollections() async throws {
        let tracks = try await createTestTracks(count: largeCollectionSize)
        
        // Measure memory before operations
        let memoryBefore = getCurrentMemoryUsage()
        
        // Perform memory-intensive operations
        let groups = try await createTestGroups(for: tracks)
        let displayItems = trackDisplayService.convertTracksToDisplayItems(tracks)
        
        // Measure memory after operations
        let memoryAfter = getCurrentMemoryUsage()
        let memoryIncrease = memoryAfter - memoryBefore
        
        print("📊 Memory Usage:")
        print("   Before: \(String(format: "%.1f", memoryBefore))MB")
        print("   After: \(String(format: "%.1f", memoryAfter))MB")
        print("   Increase: \(String(format: "%.1f", memoryIncrease))MB")
        print("   Per track: \(String(format: "%.3f", memoryIncrease * 1024 / Double(tracks.count)))KB")
        
        // Memory usage should be reasonable (adjust based on actual usage)
        let maxMemoryIncrease = Double(largeCollectionSize) * 0.01 // 10KB per track max
        XCTAssertLessThan(memoryIncrease, maxMemoryIncrease, "Memory usage should be reasonable")
        
        // Cleanup
        _ = displayItems.count // Use displayItems to prevent optimization
        _ = groups.count // Use groups to prevent optimization
    }
    
    /// Tests database query performance with indexes
    func testDatabaseQueryPerformanceWithIndexes() async throws {
        let tracks = try await createTestTracks(count: mediumCollectionSize)
        let groups = try await createTestGroups(for: tracks)
        
        // Test group loading performance
        let loadTime = measureTime {
            Task {
                do {
                    try await trackGroupService.loadGroups()
                } catch {
                    XCTFail("Failed to load groups: \(error)")
                }
            }
        }
        
        print("📊 Database Query Performance:")
        print("   Load \(groups.count) groups: \(String(format: "%.3f", loadTime))s")
        
        // Performance expectation
        XCTAssertLessThan(loadTime, 1.0, "Loading groups should complete within 1 second")
    }
    
    // MARK: - Helper Methods
    
    /// Creates test tracks in the database
    private func createTestTracks(count: Int) async throws -> [Track] {
        guard let database = database else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
        }
        
        var tracks: [Track] = []
        
        let insertSQL = """
            INSERT INTO music (title, artist, album, path, isUrl, duration)
            VALUES (?, ?, ?, ?, 0, ?)
        """
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, insertSQL, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare insert statement"])
        }
        
        defer { sqlite3_finalize(statement) }
        
        for i in 1...count {
            sqlite3_bind_text(statement, 1, "Track \(i)", -1, nil)
            sqlite3_bind_text(statement, 2, "Artist \(i % 100)", -1, nil)
            sqlite3_bind_text(statement, 3, "Album \(i % 50)", -1, nil)
            sqlite3_bind_text(statement, 4, "/path/track\(i).mp3", -1, nil)
            sqlite3_bind_int(statement, 5, Int32(180000 + (i % 120) * 1000)) // 3-5 minutes
            
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                let trackId = Int(sqlite3_last_insert_rowid(database))
                let track = Track(
                    id: trackId,
                    title: "Track \(i)",
                    artist: "Artist \(i % 100)",
                    album: "Album \(i % 50)",
                    path: "/path/track\(i).mp3",
                    isUrl: false,
                    duration: 180000 + (i % 120) * 1000
                )
                tracks.append(track)
            } else {
                print("⚠️ Failed to insert track \(i)")
            }
            
            sqlite3_reset(statement)
        }
        
        print("✅ Created \(tracks.count) test tracks")
        return tracks
    }
    
    /// Creates test groups for a portion of the tracks
    private func createTestGroups(for tracks: [Track]) async throws -> [TrackGroup] {
        let tracksToGroup = Int(Double(tracks.count) * groupsPercentage)
        var groups: [TrackGroup] = []
        
        for i in stride(from: 0, to: tracksToGroup, by: tracksPerGroup) {
            let endIndex = min(i + tracksPerGroup, tracks.count)
            let groupTracks = Array(tracks[i..<endIndex])
            let trackIds = groupTracks.compactMap { $0.id }
            
            if trackIds.count >= 2 {
                do {
                    let group = try await trackGroupService.createGroup(
                        trackIds: trackIds,
                        name: "Test Group \(groups.count + 1)"
                    )
                    groups.append(group)
                } catch {
                    print("⚠️ Failed to create test group: \(error)")
                }
            }
        }
        
        print("✅ Created \(groups.count) test groups")
        return groups
    }
    
    /// Measures execution time of a block
    private func measureTime(_ block: () -> Void) -> TimeInterval {
        let startTime = CFAbsoluteTimeGetCurrent()
        block()
        let endTime = CFAbsoluteTimeGetCurrent()
        return endTime - startTime
    }
    
    /// Gets current memory usage in MB
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / (1024 * 1024) // Convert to MB
        } else {
            return 0.0
        }
    }
}