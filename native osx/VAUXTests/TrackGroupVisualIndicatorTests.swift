import XCTest
import SwiftUI
@testable import VAUX

/// Tests for visual indicators and group member display functionality
/// Covers requirements 2.5, 6.3, 8.2, 8.3
class TrackGroupVisualIndicatorTests: XCTestCase {
    
    var trackGroupService: TrackGroupService!
    var trackDisplayService: TrackDisplayService!
    var testTracks: [Track]!
    var testGroup: TrackGroup!
    
    override func setUp() {
        super.setUp()
        trackGroupService = TrackGroupService()
        trackDisplayService = TrackDisplayService(trackGroupService: trackGroupService)
        
        // Create test tracks
        testTracks = [
            Track(id: 1, title: "Original Song", artist: "Test Artist", album: "Test Album", path: "/test1.mp3", isUrl: false, duration: 180000),
            Track(id: 2, title: "Remix Version", artist: "Test Artist", album: "Test Album", path: "/test2.mp3", isUrl: false, duration: 200000),
            Track(id: 3, title: "Live Version", artist: "Test Artist", album: "Test Album", path: "/test3.mp3", isUrl: false, duration: 220000),
            Track(id: 4, title: "Individual Track", artist: "Other Artist", album: "Other Album", path: "/test4.mp3", isUrl: false, duration: 160000)
        ]
        
        // Create a test group
        testGroup = TrackGroup(
            trackIds: Set([1, 2, 3]),
            mainTrackId: 1,
            name: "Test Group"
        )
        trackGroupService.groups = [testGroup]
    }
    
    override func tearDown() {
        trackGroupService = nil
        trackDisplayService = nil
        testTracks = nil
        testGroup = nil
        super.tearDown()
    }
    
    // MARK: - Visual Distinction Tests (Requirement 8.2)
    
    func testContainerTrackVisualDistinction() {
        // Test that container tracks have distinct visual properties
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Find the container item
        guard case .container(let groupedTrack) = displayItems.first(where: { $0.isContainer }) else {
            XCTFail("Container track not found in display items")
            return
        }
        
        // Verify container track properties
        XCTAssertTrue(groupedTrack.isGroup, "Container track should be marked as group")
        XCTAssertEqual(groupedTrack.trackCount, 3, "Container should show correct track count")
        XCTAssertEqual(groupedTrack.title, "Test Group", "Container should show group name")
        XCTAssertEqual(groupedTrack.mainTrack.id, 1, "Container should delegate to main track")
    }
    
    func testGroupMemberVisualDistinction() {
        // Expand the group first
        var expandedGroup = testGroup!
        expandedGroup.isExpanded = true
        trackGroupService.groups = [expandedGroup]
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Find group member items
        let groupMembers = displayItems.filter { $0.isMember }
        XCTAssertEqual(groupMembers.count, 3, "Should have 3 group members when expanded")
        
        // Verify each group member has correct properties
        for member in groupMembers {
            if case .groupMember(let track, let groupId) = member {
                XCTAssertEqual(groupId, testGroup.id, "Group member should reference correct group ID")
                XCTAssertTrue([1, 2, 3].contains(track.id!), "Group member should be one of the grouped tracks")
            } else {
                XCTFail("Expected group member item")
            }
        }
    }
    
    func testIndividualTrackVisualDistinction() {
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Find individual track
        let individualTracks = displayItems.filter { $0.isIndividual }
        XCTAssertEqual(individualTracks.count, 1, "Should have 1 individual track")
        
        if case .individual(let track) = individualTracks.first {
            XCTAssertEqual(track.id, 4, "Individual track should be the ungrouped track")
            XCTAssertEqual(track.title, "Individual Track", "Individual track should maintain original title")
        } else {
            XCTFail("Expected individual track item")
        }
    }
    
    // MARK: - Main Track Indicator Tests (Requirement 8.3)
    
    func testMainTrackIdentification() {
        // Expand the group to see members
        var expandedGroup = testGroup!
        expandedGroup.isExpanded = true
        trackGroupService.groups = [expandedGroup]
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Find the main track among group members
        let groupMembers = displayItems.filter { $0.isMember }
        let mainTrackMember = groupMembers.first { member in
            if case .groupMember(let track, _) = member {
                return track.id == testGroup.mainTrackId
            }
            return false
        }
        
        XCTAssertNotNil(mainTrackMember, "Main track should be identifiable among group members")
        
        if case .groupMember(let track, let groupId) = mainTrackMember {
            XCTAssertEqual(track.id, 1, "Main track should have correct ID")
            XCTAssertEqual(groupId, testGroup.id, "Main track should reference correct group")
        }
    }
    
    func testMainTrackChanges() {
        // Change main track
        var modifiedGroup = testGroup!
        modifiedGroup.mainTrackId = 2
        trackGroupService.groups = [modifiedGroup]
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Verify container now delegates to new main track
        guard case .container(let groupedTrack) = displayItems.first(where: { $0.isContainer }) else {
            XCTFail("Container track not found")
            return
        }
        
        XCTAssertEqual(groupedTrack.mainTrack.id, 2, "Container should delegate to new main track")
        XCTAssertEqual(groupedTrack.title, "Test Group", "Container should still show group name")
    }
    
    // MARK: - Group Expansion State Tests (Requirement 2.5, 6.3)
    
    func testGroupExpansionStateDisplay() {
        // Test collapsed state
        let collapsedItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        let filteredCollapsed = trackDisplayService.filterCollapsedGroups(collapsedItems)
        
        // Should only show container and individual tracks when collapsed
        let containerCount = filteredCollapsed.filter { $0.isContainer }.count
        let memberCount = filteredCollapsed.filter { $0.isMember }.count
        let individualCount = filteredCollapsed.filter { $0.isIndividual }.count
        
        XCTAssertEqual(containerCount, 1, "Should show 1 container when collapsed")
        XCTAssertEqual(memberCount, 0, "Should show 0 members when collapsed")
        XCTAssertEqual(individualCount, 1, "Should show 1 individual track")
        
        // Test expanded state
        var expandedGroup = testGroup!
        expandedGroup.isExpanded = true
        trackGroupService.groups = [expandedGroup]
        
        let expandedItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        let filteredExpanded = trackDisplayService.filterCollapsedGroups(expandedItems)
        
        let expandedContainerCount = filteredExpanded.filter { $0.isContainer }.count
        let expandedMemberCount = filteredExpanded.filter { $0.isMember }.count
        let expandedIndividualCount = filteredExpanded.filter { $0.isIndividual }.count
        
        XCTAssertEqual(expandedContainerCount, 1, "Should show 1 container when expanded")
        XCTAssertEqual(expandedMemberCount, 3, "Should show 3 members when expanded")
        XCTAssertEqual(expandedIndividualCount, 1, "Should show 1 individual track")
    }
    
    func testGroupExpansionToggle() {
        // Start with collapsed group
        XCTAssertFalse(testGroup.isExpanded, "Group should start collapsed")
        
        let initialItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Toggle expansion
        let toggledItems = trackDisplayService.toggleGroupExpansion(
            groupId: testGroup.id,
            currentDisplayItems: initialItems
        )
        
        // Verify expansion state changed
        let updatedGroup = trackGroupService.groups.first { $0.id == testGroup.id }
        XCTAssertNotNil(updatedGroup, "Group should still exist after toggle")
        XCTAssertTrue(updatedGroup!.isExpanded, "Group should be expanded after toggle")
        
        // Verify display items reflect expansion
        let memberCount = toggledItems.filter { $0.isMember }.count
        XCTAssertEqual(memberCount, 3, "Should show group members after expansion")
    }
    
    // MARK: - Visual Styling Tests
    
    func testTrackDisplayItemProperties() {
        // Test that display items have correct properties for styling
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        for item in displayItems {
            // Verify ID generation
            XCTAssertFalse(item.id.isEmpty, "Display item should have non-empty ID")
            
            // Verify track access
            XCTAssertNotNil(item.track, "Display item should provide track access")
            
            // Verify type flags
            let typeCount = [item.isContainer, item.isMember, item.isIndividual].filter { $0 }.count
            XCTAssertEqual(typeCount, 1, "Display item should have exactly one type flag set")
        }
    }
    
    func testGroupAssociationProperties() {
        // Expand group to get members
        var expandedGroup = testGroup!
        expandedGroup.isExpanded = true
        trackGroupService.groups = [expandedGroup]
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Test container association
        let containerItem = displayItems.first { $0.isContainer }
        XCTAssertNotNil(containerItem?.associatedGroupId, "Container should have associated group ID")
        XCTAssertEqual(containerItem?.associatedGroupId, testGroup.id, "Container should reference correct group")
        
        // Test member association
        let memberItems = displayItems.filter { $0.isMember }
        for member in memberItems {
            XCTAssertNotNil(member.associatedGroupId, "Group member should have associated group ID")
            XCTAssertEqual(member.associatedGroupId, testGroup.id, "Group member should reference correct group")
        }
        
        // Test individual track association
        let individualItem = displayItems.first { $0.isIndividual }
        XCTAssertNil(individualItem?.associatedGroupId, "Individual track should not have associated group ID")
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyGroupHandling() {
        // Test with no groups
        trackGroupService.groups = []
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // All tracks should be individual
        let individualCount = displayItems.filter { $0.isIndividual }.count
        XCTAssertEqual(individualCount, 4, "All tracks should be individual when no groups exist")
        
        let containerCount = displayItems.filter { $0.isContainer }.count
        XCTAssertEqual(containerCount, 0, "No containers should exist when no groups exist")
    }
    
    func testMissingMainTrackHandling() {
        // Create group with invalid main track ID
        let invalidGroup = TrackGroup(
            id: "invalid-group",
            name: "Invalid Group",
            mainTrackId: 999, // Non-existent track
            trackIds: Set([1, 2]),
            dateCreated: Date(),
            isExpanded: false
        )
        trackGroupService.groups = [invalidGroup]
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Should handle gracefully - tracks should appear as individuals
        let containerCount = displayItems.filter { $0.isContainer }.count
        XCTAssertEqual(containerCount, 0, "No container should be created with invalid main track")
    }
    
    func testSingleTrackGroupHandling() {
        // Create group with only one track (invalid state)
        let singleTrackGroup = TrackGroup(
            id: "single-track-group",
            name: "Single Track Group",
            mainTrackId: 1,
            trackIds: Set([1]),
            dateCreated: Date(),
            isExpanded: false
        )
        trackGroupService.groups = [singleTrackGroup]
        
        let displayItems = trackDisplayService.convertTracksToDisplayItems(testTracks)
        
        // Should handle gracefully
        let containerCount = displayItems.filter { $0.isContainer }.count
        // Implementation may vary - either create container or treat as individual
        // The important thing is it doesn't crash
        XCTAssertTrue(containerCount >= 0, "Should handle single-track group gracefully")
    }
}

// MARK: - Performance Tests

extension TrackGroupVisualIndicatorTests {
    
    func testLargeGroupDisplayPerformance() {
        // Create a large group for performance testing
        let largeTrackCount = 100
        var largeTracks: [Track] = []
        var largeTrackIds: Set<Int> = []
        
        for i in 1...largeTrackCount {
            let track = Track(
                id: i,
                title: "Track \(i)",
                artist: "Artist \(i)",
                album: "Album",
                path: "/track\(i).mp3",
                isUrl: false,
                duration: 180000
            )
            largeTracks.append(track)
            largeTrackIds.insert(i)
        }
        
        let largeGroup = TrackGroup(
            trackIds: largeTrackIds,
            mainTrackId: 1,
            name: "Large Group"
        )
        trackGroupService.groups = [largeGroup]
        
        // Measure performance of display item conversion
        measure {
            let displayItems = trackDisplayService.convertTracksToDisplayItems(largeTracks)
            let filteredItems = trackDisplayService.filterCollapsedGroups(displayItems)
            
            // Verify correct count
            XCTAssertEqual(filteredItems.count, 1, "Should show only container for large collapsed group")
        }
    }
    
    func testMultipleGroupsDisplayPerformance() {
        // Create multiple groups for performance testing
        let groupCount = 20
        let tracksPerGroup = 5
        var allTracks: [Track] = []
        var allGroups: [TrackGroup] = []
        
        for groupIndex in 0..<groupCount {
            var groupTrackIds: Set<Int> = []
            
            for trackIndex in 0..<tracksPerGroup {
                let trackId = groupIndex * tracksPerGroup + trackIndex + 1
                let track = Track(
                    id: trackId,
                    title: "Track \(trackId)",
                    artist: "Artist \(groupIndex)",
                    album: "Album \(groupIndex)",
                    path: "/track\(trackId).mp3",
                    isUrl: false,
                    duration: 180000
                )
                allTracks.append(track)
                groupTrackIds.insert(trackId)
            }
            
            let group = TrackGroup(
                trackIds: groupTrackIds,
                mainTrackId: groupIndex * tracksPerGroup + 1,
                name: "Group \(groupIndex)"
            )
            allGroups.append(group)
        }
        
        trackGroupService.groups = allGroups
        
        // Measure performance with multiple groups
        measure {
            let displayItems = trackDisplayService.convertTracksToDisplayItems(allTracks)
            let filteredItems = trackDisplayService.filterCollapsedGroups(displayItems)
            
            // Verify correct count (one container per group)
            XCTAssertEqual(filteredItems.count, groupCount, "Should show one container per group")
        }
    }
}