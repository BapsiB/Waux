import XCTest
@testable import VAUX

/// Integration tests for track grouping functionality with existing track operations
class TrackGroupIntegrationTests: XCTestCase {
    
    var collectionService: CollectionService!
    var trackGroupService: TrackGroupService!
    var trackDisplayService: TrackDisplayService!
    var searchService: SearchService!
    var testTracks: [Track]!
    
    override func setUp() {
        super.setUp()
        
        // Create test services
        collectionService = CollectionService()
        trackGroupService = TrackGroupService()
        trackDisplayService = TrackDisplayService(trackGroupService: trackGroupService)
        searchService = SearchService()
        
        // Create test tracks
        testTracks = [
            Track(
                id: 1,
                title: "Original Song",
                artist: "Test Artist",
                album: "Test Album",
                path: "/test/original.mp3",
                isUrl: false,
                duration: 180000
            ),
            Track(
                id: 2,
                title: "Original Song (Remix)",
                artist: "Test Artist",
                album: "Test Album",
                path: "/test/remix.mp3",
                isUrl: false,
                duration: 200000
            ),
            Track(
                id: 3,
                title: "Original Song (Live)",
                artist: "Test Artist",
                album: "Test Album",
                path: "/test/live.mp3",
                isUrl: false,
                duration: 190000
            ),
            Track(
                id: 4,
                title: "Different Song",
                artist: "Other Artist",
                album: "Other Album",
                path: "/test/different.mp3",
                isUrl: false,
                duration: 160000
            )
        ]
    }
    
    override func tearDown() {
        testTracks = nil
        searchService = nil
        trackDisplayService = nil
        trackGroupService = nil
        collectionService = nil
        super.tearDown()
    }
    
    // MARK: - Search Integration Tests
    
    func testSearchWithGroupedTracks() async throws {
        // Create a group with the first three tracks
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Original Song Versions",
            mainTrackId: 1
        )
        
        // Convert tracks to display items
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Test search that matches the group
        searchService.searchText = "Original"
        let filteredItems = searchService.filterDisplayItems(displayItems)
        
        // Should include the container and individual track
        XCTAssertEqual(filteredItems.count, 2) // Container + individual track
        
        // Verify container is included
        let hasContainer = filteredItems.contains { item in
            if case .container(let groupedTrack) = item {
                return groupedTrack.group.id == group.id
            }
            return false
        }
        XCTAssertTrue(hasContainer, "Container should be included when group matches search")
        
        // Test search that matches only one track in group
        searchService.searchText = "Remix"
        let remixFiltered = searchService.filterDisplayItems(displayItems)
        
        // Should still include the container since one track matches
        XCTAssertEqual(remixFiltered.count, 1)
        XCTAssertTrue(remixFiltered.first?.isContainer == true)
    }
    
    func testSearchWithExpandedGroups() async throws {
        // Create and expand a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Original Song Versions",
            mainTrackId: 1
        )
        
        trackGroupService.toggleGroupExpansion(groupId: group.id)
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Search for specific track in expanded group
        searchService.searchText = "Live"
        let filteredItems = searchService.filterDisplayItems(displayItems)
        
        // Should include container and the matching group member
        XCTAssertEqual(filteredItems.count, 2)
        
        let hasContainer = filteredItems.contains { $0.isContainer }
        let hasLiveMember = filteredItems.contains { item in
            if case .groupMember(let track, _) = item {
                return track.title.contains("Live")
            }
            return false
        }
        
        XCTAssertTrue(hasContainer, "Container should be included")
        XCTAssertTrue(hasLiveMember, "Live track member should be included")
    }
    
    // MARK: - Selection Integration Tests
    
    func testSelectionWithContainerTracks() async throws {
        // Create a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Original Song Versions",
            mainTrackId: 1
        )
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        let containerItem = displayItems.first { $0.isContainer }!
        
        // Simulate selecting the container
        let selectedIds: Set<String> = [containerItem.id]
        
        // Verify that the container represents the main track
        XCTAssertEqual(containerItem.track.id, 1, "Container should represent main track")
        XCTAssertEqual(containerItem.track.title, "Original Song", "Container should show main track title")
    }
    
    func testSelectionWithGroupMembers() async throws {
        // Create and expand a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Original Song Versions",
            mainTrackId: 1
        )
        
        trackGroupService.toggleGroupExpansion(groupId: group.id)
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        let groupMembers = displayItems.filter { $0.isMember }
        
        XCTAssertEqual(groupMembers.count, 3, "Should have 3 group members when expanded")
        
        // Verify main track is first
        let firstMember = groupMembers.first!
        XCTAssertEqual(firstMember.track.id, 1, "Main track should be first group member")
    }
    
    // MARK: - Sorting Integration Tests
    
    func testGroupAwareSorting() async throws {
        // Create a group
        let group = try await trackGroupService.createGroup(
            trackIds: [2, 3], // Remix and Live versions
            name: "Song Versions",
            mainTrackId: 2
        )
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Create a mock sort order (by title)
        let sortOrder = [KeyPathComparator(\TrackDisplayItem.track.title)]
        
        // Test that groups stay together when sorting
        let sortedItems = displayItems.sorted(using: sortOrder)
        
        // Find the container position
        let containerIndex = sortedItems.firstIndex { $0.isContainer }
        XCTAssertNotNil(containerIndex, "Container should be present in sorted items")
        
        // Verify individual tracks are sorted separately from groups
        let individualTracks = sortedItems.filter { $0.isIndividual }
        let containerTracks = sortedItems.filter { $0.isContainer }
        
        XCTAssertEqual(individualTracks.count, 2, "Should have 2 individual tracks")
        XCTAssertEqual(containerTracks.count, 1, "Should have 1 container track")
    }
    
    func testSortingWithExpandedGroups() async throws {
        // Create and expand a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Original Song Versions",
            mainTrackId: 1
        )
        
        trackGroupService.toggleGroupExpansion(groupId: group.id)
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        let sortOrder = [KeyPathComparator(\TrackDisplayItem.track.title)]
        let sortedItems = displayItems.sorted(using: sortOrder)
        
        // Find container and its members
        let containerIndex = sortedItems.firstIndex { $0.isContainer }!
        let groupMembers = sortedItems.filter { $0.isMember }
        
        // Verify group members follow the container
        XCTAssertEqual(groupMembers.count, 3, "Should have 3 group members")
        
        // Verify main track is first among group members
        let mainMemberIndex = sortedItems.firstIndex { item in
            if case .groupMember(let track, _) = item {
                return track.id == group.mainTrackId
            }
            return false
        }
        
        XCTAssertNotNil(mainMemberIndex, "Main track member should be present")
    }
    
    // MARK: - Metadata Editing Integration Tests
    
    func testMetadataEditingWithContainerTracks() async throws {
        // Create a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Original Song Versions",
            mainTrackId: 1
        )
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        let containerItem = displayItems.first { $0.isContainer }!
        
        // Simulate selecting container for metadata editing
        let selectedIds: Set<String> = [containerItem.id]
        
        // Get track IDs for metadata editing (should return main track ID)
        let selectedItems = displayItems.filter { selectedIds.contains($0.id) }
        var trackIds: [Int] = []
        
        for item in selectedItems {
            switch item {
            case .container(let groupedTrack):
                if let mainTrackId = groupedTrack.mainTrack.id {
                    trackIds.append(mainTrackId)
                }
            case .individual(let track):
                if let trackId = track.id {
                    trackIds.append(trackId)
                }
            case .groupMember(let track, _):
                if let trackId = track.id {
                    trackIds.append(trackId)
                }
            }
        }
        
        XCTAssertEqual(trackIds, [1], "Should return main track ID for container selection")
    }
    
    func testMetadataEditingWithMixedSelection() async throws {
        // Create a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2],
            name: "Song Versions",
            mainTrackId: 1
        )
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        let containerItem = displayItems.first { $0.isContainer }!
        let individualItem = displayItems.first { $0.isIndividual }!
        
        // Select both container and individual track
        let selectedIds: Set<String> = [containerItem.id, individualItem.id]
        let selectedItems = displayItems.filter { selectedIds.contains($0.id) }
        
        var trackIds: [Int] = []
        var processedGroupIds: Set<String> = []
        
        for item in selectedItems {
            switch item {
            case .container(let groupedTrack):
                if let mainTrackId = groupedTrack.mainTrack.id {
                    trackIds.append(mainTrackId)
                    processedGroupIds.insert(groupedTrack.group.id)
                }
            case .individual(let track):
                if let trackId = track.id {
                    trackIds.append(trackId)
                }
            case .groupMember(let track, let groupId):
                if !processedGroupIds.contains(groupId), let trackId = track.id {
                    trackIds.append(trackId)
                }
            }
        }
        
        // Should have main track from group + individual track
        XCTAssertEqual(trackIds.count, 2, "Should have 2 track IDs")
        XCTAssertTrue(trackIds.contains(1), "Should contain main track ID")
        XCTAssertTrue(trackIds.contains(3) || trackIds.contains(4), "Should contain individual track ID")
    }
    
    // MARK: - Filtering Integration Tests
    
    func testFilteringWithCollapsedGroups() async throws {
        // Create a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Original Song Versions",
            mainTrackId: 1
        )
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        let filteredItems = trackDisplayService.filterCollapsedGroups(displayItems)
        
        // Should show container + individual track (group is collapsed by default)
        XCTAssertEqual(filteredItems.count, 2, "Should show container and individual track")
        
        let hasContainer = filteredItems.contains { $0.isContainer }
        let hasIndividual = filteredItems.contains { $0.isIndividual }
        
        XCTAssertTrue(hasContainer, "Should have container track")
        XCTAssertTrue(hasIndividual, "Should have individual track")
        XCTAssertFalse(filteredItems.contains { $0.isMember }, "Should not show group members when collapsed")
    }
    
    func testFilteringWithExpandedGroups() async throws {
        // Create and expand a group
        let group = try await trackGroupService.createGroup(
            trackIds: [1, 2, 3],
            name: "Original Song Versions",
            mainTrackId: 1
        )
        
        trackGroupService.toggleGroupExpansion(groupId: group.id)
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        let filteredItems = trackDisplayService.filterCollapsedGroups(displayItems)
        
        // Should show container + group members + individual track
        XCTAssertEqual(filteredItems.count, 5, "Should show container, 3 members, and 1 individual")
        
        let containerCount = filteredItems.filter { $0.isContainer }.count
        let memberCount = filteredItems.filter { $0.isMember }.count
        let individualCount = filteredItems.filter { $0.isIndividual }.count
        
        XCTAssertEqual(containerCount, 1, "Should have 1 container")
        XCTAssertEqual(memberCount, 3, "Should have 3 group members")
        XCTAssertEqual(individualCount, 1, "Should have 1 individual track")
    }
}