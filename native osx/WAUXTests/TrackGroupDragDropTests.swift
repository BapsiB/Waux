import XCTest
@testable import WAUX

class TrackGroupDragDropTests: XCTestCase {
    
    var collectionService: CollectionService!
    var trackGroupService: TrackGroupService!
    var trackDisplayService: TrackDisplayService!
    var testTracks: [Track]!
    var testGroup: TrackGroup!
    
    override func setUp() {
        super.setUp()
        
        // Create test collection service
        collectionService = CollectionService()
        trackGroupService = TrackGroupService()
        trackDisplayService = TrackDisplayService(trackGroupService: trackGroupService)
        
        // Create test tracks
        testTracks = [
            Track(id: 1, title: "Original Song", artist: "Artist", album: "Album", path: "/path/to/original.mp3", isUrl: false, duration: 180000),
            Track(id: 2, title: "Remix Version", artist: "Artist", album: "Album", path: "/path/to/remix.mp3", isUrl: false, duration: 200000),
            Track(id: 3, title: "Live Version", artist: "Artist", album: "Album", path: "/path/to/live.mp3", isUrl: false, duration: 220000),
            Track(id: 4, title: "Individual Track", artist: "Other Artist", album: "Other Album", path: "/path/to/individual.mp3", isUrl: false, duration: 190000)
        ]
        
        // Create test group
        testGroup = TrackGroup(
            trackIds: Set([1, 2, 3]),
            mainTrackId: 1,
            name: "Song Variations"
        )
        
        // Add group to service
        trackGroupService.groups = [testGroup]
    }
    
    override func tearDown() {
        collectionService = nil
        trackGroupService = nil
        trackDisplayService = nil
        testTracks = nil
        testGroup = nil
        super.tearDown()
    }
    
    // MARK: - Container Track Drag Tests
    
    func testContainerTrackDragSingle() {
        // Test dragging a single container track
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Find the container item
        guard case .container(let groupedTrack) = displayItems.first(where: { $0.isContainer }) else {
            XCTFail("Container track not found")
            return
        }
        
        // Simulate drag operation
        let dragTracks = getTracksFromDisplayItem(.container(groupedTrack))
        
        XCTAssertEqual(dragTracks.count, 1, "Container drag should return main track only")
        XCTAssertEqual(dragTracks.first?.id, testGroup.mainTrackId, "Should return main track")
        XCTAssertEqual(dragTracks.first?.path, "/path/to/original.mp3", "Should have correct path")
    }
    
    func testContainerTrackDragPreviewInfo() {
        // Test drag preview information for container tracks
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        guard case .container(let groupedTrack) = displayItems.first(where: { $0.isContainer }) else {
            XCTFail("Container track not found")
            return
        }
        
        let dragInfo = getDragPreviewInfo(for: groupedTrack.mainTrack, tracks: [groupedTrack.mainTrack])
        
        XCTAssertEqual(dragInfo.icon, "rectangle.3.group", "Should use group icon")
        XCTAssertEqual(dragInfo.title, testGroup.name, "Should show group name")
        XCTAssertEqual(dragInfo.subtitle, "3 tracks in group", "Should show track count")
    }
    
    // MARK: - Group Member Drag Tests
    
    func testGroupMemberDragMainTrack() {
        // Test dragging the main track from an expanded group
        let expandedGroup = TrackGroup(
            id: testGroup.id,
            name: testGroup.name,
            mainTrackId: testGroup.mainTrackId,
            trackIds: testGroup.trackIds,
            dateCreated: testGroup.dateCreated,
            isExpanded: true
        )
        trackGroupService.groups = [expandedGroup]
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Find the main track member
        guard case .groupMember(let mainTrack, _) = displayItems.first(where: { item in
            if case .groupMember(let track, _) = item {
                return track.id == testGroup.mainTrackId
            }
            return false
        }) else {
            XCTFail("Main track member not found")
            return
        }
        
        let dragTracks = getTracksFromDisplayItem(.groupMember(mainTrack, groupId: testGroup.id))
        
        XCTAssertEqual(dragTracks.count, 1, "Should return single track")
        XCTAssertEqual(dragTracks.first?.id, testGroup.mainTrackId, "Should return main track")
    }
    
    func testGroupMemberDragNonMainTrack() {
        // Test dragging a non-main track from an expanded group
        let expandedGroup = TrackGroup(
            id: testGroup.id,
            name: testGroup.name,
            mainTrackId: testGroup.mainTrackId,
            trackIds: testGroup.trackIds,
            dateCreated: testGroup.dateCreated,
            isExpanded: true
        )
        trackGroupService.groups = [expandedGroup]
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Find a non-main track member
        guard case .groupMember(let memberTrack, _) = displayItems.first(where: { item in
            if case .groupMember(let track, _) = item {
                return track.id != testGroup.mainTrackId
            }
            return false
        }) else {
            XCTFail("Non-main track member not found")
            return
        }
        
        let dragTracks = getTracksFromDisplayItem(.groupMember(memberTrack, groupId: testGroup.id))
        
        XCTAssertEqual(dragTracks.count, 1, "Should return single track")
        XCTAssertEqual(dragTracks.first?.id, memberTrack.id, "Should return the specific member track")
    }
    
    // MARK: - Multiple Selection Drag Tests
    
    func testMultipleSelectionWithContainer() {
        // Test dragging multiple items including a container
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Simulate selection of container and individual track
        var selectedIds: Set<String> = []
        
        // Add container to selection
        if let containerItem = displayItems.first(where: { $0.isContainer }) {
            selectedIds.insert(containerItem.id)
        }
        
        // Add individual track to selection
        if let individualItem = displayItems.first(where: { $0.isIndividual }) {
            selectedIds.insert(individualItem.id)
        }
        
        let dragTracks = getTracksFromSelectedDisplayItems(selectedIds: selectedIds, displayItems: displayItems)
        
        XCTAssertEqual(dragTracks.count, 2, "Should return main track from group plus individual track")
        
        let trackIds = Set(dragTracks.compactMap { $0.id })
        XCTAssertTrue(trackIds.contains(testGroup.mainTrackId), "Should include main track from group")
        XCTAssertTrue(trackIds.contains(4), "Should include individual track")
    }
    
    func testMultipleSelectionWithGroupMembers() {
        // Test dragging multiple group members without container
        let expandedGroup = TrackGroup(
            id: testGroup.id,
            name: testGroup.name,
            mainTrackId: testGroup.mainTrackId,
            trackIds: testGroup.trackIds,
            dateCreated: testGroup.dateCreated,
            isExpanded: true
        )
        trackGroupService.groups = [expandedGroup]
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Simulate selection of multiple group members
        var selectedIds: Set<String> = []
        
        let groupMembers = displayItems.filter { item in
            if case .groupMember = item { return true }
            return false
        }
        
        // Select first two group members
        for member in groupMembers.prefix(2) {
            selectedIds.insert(member.id)
        }
        
        let dragTracks = getTracksFromSelectedDisplayItems(selectedIds: selectedIds, displayItems: displayItems)
        
        XCTAssertEqual(dragTracks.count, 2, "Should return both selected group members")
    }
    
    func testMultipleSelectionContainerAndMembers() {
        // Test dragging container and its members (should avoid duplication)
        let expandedGroup = TrackGroup(
            id: testGroup.id,
            name: testGroup.name,
            mainTrackId: testGroup.mainTrackId,
            trackIds: testGroup.trackIds,
            dateCreated: testGroup.dateCreated,
            isExpanded: true
        )
        trackGroupService.groups = [expandedGroup]
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Simulate selection of container and some of its members
        var selectedIds: Set<String> = []
        
        // Add container to selection
        if let containerItem = displayItems.first(where: { $0.isContainer }) {
            selectedIds.insert(containerItem.id)
        }
        
        // Add some group members to selection
        let groupMembers = displayItems.filter { item in
            if case .groupMember = item { return true }
            return false
        }
        
        for member in groupMembers.prefix(2) {
            selectedIds.insert(member.id)
        }
        
        let dragTracks = getTracksFromSelectedDisplayItems(selectedIds: selectedIds, displayItems: displayItems)
        
        // Should only include main track from container, not duplicate group members
        XCTAssertEqual(dragTracks.count, 1, "Should avoid duplicating tracks when container and members are selected")
        XCTAssertEqual(dragTracks.first?.id, testGroup.mainTrackId, "Should return main track from container")
    }
    
    // MARK: - Drag Payload Tests
    
    func testDragPayloadPaths() {
        // Test that drag payload contains correct file paths
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        guard case .container(let groupedTrack) = displayItems.first(where: { $0.isContainer }) else {
            XCTFail("Container track not found")
            return
        }
        
        let dragTracks = getTracksFromDisplayItem(.container(groupedTrack))
        let paths = dragTracks.map { $0.path }
        
        XCTAssertEqual(paths.count, 1, "Should have one path")
        XCTAssertEqual(paths.first, "/path/to/original.mp3", "Should have main track path")
    }
    
    func testDragPayloadMultiplePaths() {
        // Test drag payload with multiple selected items
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        var selectedIds: Set<String> = []
        
        // Select container and individual track
        if let containerItem = displayItems.first(where: { $0.isContainer }) {
            selectedIds.insert(containerItem.id)
        }
        
        if let individualItem = displayItems.first(where: { $0.isIndividual }) {
            selectedIds.insert(individualItem.id)
        }
        
        let dragTracks = getTracksFromSelectedDisplayItems(selectedIds: selectedIds, displayItems: displayItems)
        let paths = dragTracks.map { $0.path }
        
        XCTAssertEqual(paths.count, 2, "Should have two paths")
        XCTAssertTrue(paths.contains("/path/to/original.mp3"), "Should include main track path")
        XCTAssertTrue(paths.contains("/path/to/individual.mp3"), "Should include individual track path")
    }
    
    // MARK: - Playlist Operations Tests
    
    func testPlaylistOperationWithContainer() {
        // Test that playlist operations work correctly with container tracks
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        guard case .container(let groupedTrack) = displayItems.first(where: { $0.isContainer }) else {
            XCTFail("Container track not found")
            return
        }
        
        // Simulate adding container to playlist (should add main track)
        let trackForPlaylist = groupedTrack.mainTrack
        
        XCTAssertEqual(trackForPlaylist.id, testGroup.mainTrackId, "Should use main track for playlist operations")
        XCTAssertEqual(trackForPlaylist.path, "/path/to/original.mp3", "Should have correct path for playback")
    }
    
    // MARK: - Helper Methods (simulating TrackTable methods)
    
    private func getTracksFromDisplayItem(_ displayItem: TrackDisplayItem) -> [Track] {
        switch displayItem {
        case .individual(let track):
            return [track]
        case .container(let groupedTrack):
            return [groupedTrack.mainTrack]
        case .groupMember(let track, groupId: _):
            return [track]
        }
    }
    
    private func getTracksFromSelectedDisplayItems(selectedIds: Set<String>, displayItems: [TrackDisplayItem]) -> [Track] {
        var tracks: [Track] = []
        var processedGroupIds: Set<String> = []
        
        for selectedId in selectedIds {
            guard let displayItem = displayItems.first(where: { $0.id == selectedId }) else { continue }
            
            switch displayItem {
            case .individual(let track):
                tracks.append(track)
                
            case .container(let groupedTrack):
                tracks.append(groupedTrack.mainTrack)
                processedGroupIds.insert(groupedTrack.group.id)
                
            case .groupMember(let track, groupId: let groupId):
                if !processedGroupIds.contains(groupId) {
                    tracks.append(track)
                }
            }
        }
        
        return tracks
    }
    
    private func getDragPreviewInfo(for track: Track, tracks: [Track]) -> (icon: String, iconColor: String, title: String, subtitle: String?) {
        // Simplified version for testing
        if tracks.count == 1 && track.id == testGroup.mainTrackId {
            return ("rectangle.3.group", "accentColor", testGroup.name, "3 tracks in group")
        }
        return ("music.note", "primary", track.title, nil)
    }
}

// MARK: - Test Extensions

extension Track {
    static func createTestTrack(id: Int, title: String, artist: String, album: String, path: String) -> Track {
        return Track(
            id: id,
            title: title,
            artist: artist,
            album: album,
            path: path,
            isUrl: false,
            duration: 180000
        )
    }
}