import XCTest
import SQLite3
@testable import VAUX

class TrackDisplayServiceTests: XCTestCase {
    
    var trackGroupService: TrackGroupService!
    var trackDisplayService: TrackDisplayService!
    var sampleTracks: [Track]!
    var database: OpaquePointer?
    
    override func setUp() {
        super.setUp()
        
        // Create in-memory database for testing
        let result = sqlite3_open(":memory:", &database)
        XCTAssertEqual(result, SQLITE_OK, "Failed to create in-memory database")
        
        // Create the required tables
        createTestTables()
        
        trackGroupService = TrackGroupService()
        trackGroupService.setDatabase(database)
        trackDisplayService = TrackDisplayService(trackGroupService: trackGroupService)
        
        // Create sample tracks for testing
        sampleTracks = [
            Track(id: 1, title: "Song A", artist: "Artist 1", album: "Album 1", path: "/path/a.mp3", isUrl: false, duration: 180000),
            Track(id: 2, title: "Song A (Remix)", artist: "Artist 1", album: "Album 1", path: "/path/a_remix.mp3", isUrl: false, duration: 200000),
            Track(id: 3, title: "Song A (Live)", artist: "Artist 1", album: "Album 1", path: "/path/a_live.mp3", isUrl: false, duration: 220000),
            Track(id: 4, title: "Song B", artist: "Artist 2", album: "Album 2", path: "/path/b.mp3", isUrl: false, duration: 160000),
            Track(id: 5, title: "Song C", artist: "Artist 3", album: "Album 3", path: "/path/c.mp3", isUrl: false, duration: 190000),
            Track(id: 6, title: "Song D", artist: "Artist 4", album: "Album 4", path: "/path/d.mp3", isUrl: false, duration: 210000)
        ]
    }
    
    override func tearDown() {
        if let database = database {
            sqlite3_close(database)
        }
        trackGroupService = nil
        trackDisplayService = nil
        sampleTracks = nil
        super.tearDown()
    }
    
    private func createTestTables() {
        guard let database = database else { return }
        
        // Create track_groups table
        let createGroupsTable = """
            CREATE TABLE track_groups (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL DEFAULT '',
                main_track_id INTEGER NOT NULL,
                date_created TEXT NOT NULL,
                is_expanded INTEGER NOT NULL DEFAULT 0
            )
        """
        
        var result = sqlite3_exec(database, createGroupsTable, nil, nil, nil)
        XCTAssertEqual(result, SQLITE_OK, "Failed to create track_groups table")
        
        // Create track_group_members table
        let createMembersTable = """
            CREATE TABLE track_group_members (
                group_id TEXT NOT NULL,
                track_id INTEGER NOT NULL,
                PRIMARY KEY (group_id, track_id),
                FOREIGN KEY (group_id) REFERENCES track_groups (id) ON DELETE CASCADE
            )
        """
        
        result = sqlite3_exec(database, createMembersTable, nil, nil, nil)
        XCTAssertEqual(result, SQLITE_OK, "Failed to create track_group_members table")
    }
    
    // MARK: - Basic Conversion Tests
    
    func testConvertTracksToDisplayItems_NoGroups() {
        // Test conversion when no groups exist
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        
        XCTAssertEqual(displayItems.count, sampleTracks.count)
        
        // All items should be individual tracks
        for (index, item) in displayItems.enumerated() {
            XCTAssertTrue(item.isIndividual, "Item \(index) should be individual")
            XCTAssertEqual(item.track.id, sampleTracks[index].id)
        }
    }
    
    func testConvertTracksToDisplayItems_WithCollapsedGroup() async throws {
        // Create a group with tracks 1, 2, 3 (Song A variations)
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        
        // Should have: 1 container + 3 individual tracks = 4 items
        XCTAssertEqual(displayItems.count, 4)
        
        // First item should be the container
        XCTAssertTrue(displayItems[0].isContainer, "First item should be container")
        if case .container(let groupedTrack) = displayItems[0] {
            XCTAssertEqual(groupedTrack.group.id, group.id)
            XCTAssertEqual(groupedTrack.mainTrack.id, 1)
            XCTAssertEqual(groupedTrack.trackCount, 3)
            XCTAssertFalse(groupedTrack.isExpanded)
        } else {
            XCTFail("First item should be container")
        }
        
        // Remaining items should be individual tracks (4, 5, 6)
        let expectedIndividualIds = [4, 5, 6]
        for (index, expectedId) in expectedIndividualIds.enumerated() {
            let itemIndex = index + 1
            XCTAssertTrue(displayItems[itemIndex].isIndividual, "Item \(itemIndex) should be individual")
            XCTAssertEqual(displayItems[itemIndex].track.id, expectedId)
        }
    }
    
    func testConvertTracksToDisplayItems_WithExpandedGroup() async throws {
        // Create a group and expand it
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        trackGroupService.toggleGroupExpansion(groupId: group.id)
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        
        // Should have: 1 container + 3 group members + 3 individual tracks = 7 items
        XCTAssertEqual(displayItems.count, 7)
        
        // First item should be the container (expanded)
        XCTAssertTrue(displayItems[0].isContainer)
        if case .container(let groupedTrack) = displayItems[0] {
            XCTAssertTrue(groupedTrack.isExpanded)
        }
        
        // Next 3 items should be group members
        for i in 1...3 {
            XCTAssertTrue(displayItems[i].isMember, "Item \(i) should be group member")
            if case .groupMember(_, let groupId) = displayItems[i] {
                XCTAssertEqual(groupId, group.id)
            }
        }
        
        // Last 3 items should be individual tracks
        for i in 4...6 {
            XCTAssertTrue(displayItems[i].isIndividual, "Item \(i) should be individual")
        }
    }
    
    // MARK: - Group Membership Detection Tests
    
    func testGroupMembershipDetection() async throws {
        // Create two groups
        let group1 = try await trackGroupService.createGroup(
            trackIds: [1, 2],
            name: "Group 1",
            mainTrackId: 1
        )
        
        let group2 = try await trackGroupService.createGroup(
            trackIds: [4, 5],
            name: "Group 2", 
            mainTrackId: 4
        )
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        
        // Should have: 2 containers + 2 individual tracks = 4 items
        XCTAssertEqual(displayItems.count, 4)
        
        // Verify containers
        var containerCount = 0
        var individualCount = 0
        
        for item in displayItems {
            if item.isContainer {
                containerCount += 1
            } else if item.isIndividual {
                individualCount += 1
            }
        }
        
        XCTAssertEqual(containerCount, 2)
        XCTAssertEqual(individualCount, 2)
    }
    
    // MARK: - Filtering Tests
    
    func testFilterCollapsedGroups_NoGroups() {
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        let filteredItems = trackDisplayService.filterCollapsedGroups(displayItems)
        
        // Should be identical when no groups exist
        XCTAssertEqual(filteredItems.count, displayItems.count)
        
        for (index, item) in filteredItems.enumerated() {
            XCTAssertEqual(item.id, displayItems[index].id)
        }
    }
    
    func testFilterCollapsedGroups_WithCollapsedGroup() async throws {
        // Create a collapsed group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        let filteredItems = trackDisplayService.filterCollapsedGroups(displayItems)
        
        // Should be identical since group is collapsed (no members to filter out)
        XCTAssertEqual(filteredItems.count, displayItems.count)
    }
    
    func testFilterCollapsedGroups_WithExpandedGroup() async throws {
        // Create an expanded group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        trackGroupService.toggleGroupExpansion(groupId: group.id)
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        let filteredItems = trackDisplayService.filterCollapsedGroups(displayItems)
        
        // Should include all items since group is expanded
        XCTAssertEqual(filteredItems.count, displayItems.count)
        
        // Verify we have container, members, and individuals
        var hasContainer = false
        var memberCount = 0
        var individualCount = 0
        
        for item in filteredItems {
            if item.isContainer {
                hasContainer = true
            } else if item.isMember {
                memberCount += 1
            } else if item.isIndividual {
                individualCount += 1
            }
        }
        
        XCTAssertTrue(hasContainer)
        XCTAssertEqual(memberCount, 3)
        XCTAssertEqual(individualCount, 3)
    }
    
    // MARK: - Expansion Toggle Tests
    
    func testToggleGroupExpansion_CollapseToExpand() async throws {
        // Create a collapsed group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        let initialDisplayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        XCTAssertEqual(initialDisplayItems.count, 4) // 1 container + 3 individuals
        
        // Toggle to expand
        let updatedDisplayItems = trackDisplayService.toggleGroupExpansion(
            groupId: group.id,
            currentDisplayItems: initialDisplayItems
        )
        
        XCTAssertEqual(updatedDisplayItems.count, 7) // 1 container + 3 members + 3 individuals
        
        // Verify expansion state
        if case .container(let groupedTrack) = updatedDisplayItems[0] {
            XCTAssertTrue(groupedTrack.isExpanded)
        } else {
            XCTFail("First item should be expanded container")
        }
    }
    
    func testToggleGroupExpansion_ExpandToCollapse() async throws {
        // Create an expanded group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        trackGroupService.toggleGroupExpansion(groupId: group.id) // Expand first
        
        let initialDisplayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        XCTAssertEqual(initialDisplayItems.count, 7) // 1 container + 3 members + 3 individuals
        
        // Toggle to collapse
        let updatedDisplayItems = trackDisplayService.toggleGroupExpansion(
            groupId: group.id,
            currentDisplayItems: initialDisplayItems
        )
        
        XCTAssertEqual(updatedDisplayItems.count, 4) // 1 container + 3 individuals
        
        // Verify collapse state
        if case .container(let groupedTrack) = updatedDisplayItems[0] {
            XCTAssertFalse(groupedTrack.isExpanded)
        } else {
            XCTFail("First item should be collapsed container")
        }
    }
    
    // MARK: - Track Extraction Tests
    
    func testGetAllTracks() async throws {
        // Create a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        trackGroupService.toggleGroupExpansion(groupId: group.id) // Expand
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        let allTracks = trackDisplayService.getAllTracks(from: displayItems)
        
        // Should get all original tracks without duplicates
        XCTAssertEqual(allTracks.count, sampleTracks.count)
        
        let trackIds = Set(allTracks.compactMap { $0.id })
        let originalIds = Set(sampleTracks.compactMap { $0.id })
        XCTAssertEqual(trackIds, originalIds)
    }
    
    func testGetSelectableTracks_CollapsedGroup() async throws {
        // Create a collapsed group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        let selectableTracks = trackDisplayService.getSelectableTracks(from: displayItems)
        
        // Should have 4 selectable tracks: 1 container + 3 individuals
        XCTAssertEqual(selectableTracks.count, 4)
        
        // Container should represent the main track
        XCTAssertEqual(selectableTracks[0].id, 1) // Main track of the group
        
        // Other tracks should be the ungrouped ones
        let otherIds = selectableTracks.dropFirst().compactMap { $0.id }
        XCTAssertEqual(Set(otherIds), Set([4, 5, 6]))
    }
    
    func testGetSelectableTracks_ExpandedGroup() async throws {
        // Create an expanded group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        trackGroupService.toggleGroupExpansion(groupId: group.id)
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        let selectableTracks = trackDisplayService.getSelectableTracks(from: displayItems)
        
        // Should have 7 selectable tracks: 1 container + 3 members + 3 individuals
        XCTAssertEqual(selectableTracks.count, 7)
    }
    
    // MARK: - Edge Cases
    
    func testConvertTracksWithMissingMainTrack() async throws {
        // Create a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        // Remove the main track from the input tracks
        let tracksWithoutMain = sampleTracks.filter { $0.id != 1 }
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(tracksWithoutMain)
        
        // Should treat remaining group tracks as individuals since main track is missing
        XCTAssertEqual(displayItems.count, tracksWithoutMain.count)
        
        for item in displayItems {
            XCTAssertTrue(item.isIndividual, "All items should be individual when main track is missing")
        }
    }
    
    func testConvertTracksWithPartialGroupTracks() async throws {
        // Create a group with 3 tracks
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        // Only provide 2 of the 3 group tracks
        let partialTracks = sampleTracks.filter { $0.id != 3 }
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(partialTracks)
        
        // Should treat remaining tracks as individuals since we can't create a proper container
        // without all tracks (this prevents inconsistent state)
        XCTAssertEqual(displayItems.count, partialTracks.count)
        
        for item in displayItems {
            XCTAssertTrue(item.isIndividual, "All items should be individual when group is incomplete")
        }
    }
    
    func testTrackDisplayItemExtensions() async throws {
        // Create a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Song A Versions",
            mainTrackId: 1
        )
        
        trackGroupService.toggleGroupExpansion(groupId: group.id)
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(sampleTracks)
        
        // Test container item
        let containerItem = displayItems[0]
        XCTAssertTrue(containerItem.isContainer)
        XCTAssertFalse(containerItem.isMember)
        XCTAssertFalse(containerItem.isIndividual)
        XCTAssertEqual(containerItem.associatedGroupId, group.id)
        XCTAssertTrue(containerItem.isSelectable)
        
        // Test group member item
        let memberItem = displayItems[1]
        XCTAssertFalse(memberItem.isContainer)
        XCTAssertTrue(memberItem.isMember)
        XCTAssertFalse(memberItem.isIndividual)
        XCTAssertEqual(memberItem.associatedGroupId, group.id)
        XCTAssertTrue(memberItem.isSelectable)
        
        // Test individual item
        let individualItem = displayItems[4]
        XCTAssertFalse(individualItem.isContainer)
        XCTAssertFalse(individualItem.isMember)
        XCTAssertTrue(individualItem.isIndividual)
        XCTAssertNil(individualItem.associatedGroupId)
        XCTAssertTrue(individualItem.isSelectable)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceWithLargeTrackList() {
        // Create a large number of tracks
        var largeTracks: [Track] = []
        for i in 1...1000 {
            largeTracks.append(Track(
                id: i,
                title: "Track \(i)",
                artist: "Artist \(i % 10)",
                album: "Album \(i % 20)",
                path: "/path/track\(i).mp3",
                isUrl: false,
                duration: 180000
            ))
        }
        
        measure {
            let displayItems = trackDisplayService.convertTracksToDisplayItems(largeTracks)
            XCTAssertEqual(displayItems.count, largeTracks.count)
        }
    }
    
    func testPerformanceWithManyGroups() async throws {
        // Create many small groups
        for i in stride(from: 1, to: 100, by: 2) {
            try await trackGroupService.createGroup(
                trackIds: [i, i + 1],
                name: "Group \(i)",
                mainTrackId: i
            )
        }
        
        // Create tracks for all groups
        var manyTracks: [Track] = []
        for i in 1...100 {
            manyTracks.append(Track(
                id: i,
                title: "Track \(i)",
                artist: "Artist \(i % 10)",
                album: "Album \(i % 20)",
                path: "/path/track\(i).mp3",
                isUrl: false,
                duration: 180000
            ))
        }
        
        measure {
            let displayItems = trackDisplayService.convertTracksToDisplayItems(manyTracks)
            // Should have 50 containers + 0 individuals = 50 items (all tracks are grouped)
            XCTAssertEqual(displayItems.count, 50)
        }
    }
}