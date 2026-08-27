import XCTest
@testable import VAUX

class ContainerTrackBehaviorTests: XCTestCase {
    
    // MARK: - Test Data
    private func createSampleTrack(id: Int, title: String, artist: String = "Test Artist", path: String? = nil) -> Track {
        return Track(
            id: id,
            title: title,
            artist: artist,
            album: "Test Album",
            albumArtist: "Test Album Artist",
            composer: "Test Composer",
            genre: "Rock",
            year: 2023,
            trackNumber: id,
            discNumber: 1,
            bpm: 120,
            path: path ?? "/test/path/\(id).mp3",
            isUrl: false,
            duration: 180000, // 3 minutes
            rating: id % 5 + 1, // Rating 1-5
            comment: "Test comment for track \(id)",
            generalTags: ["tag\(id)", "test"]
        )
    }
    
    private func createSampleTracks() -> [Track] {
        return [
            createSampleTrack(id: 1, title: "Original Song", path: "/main/original.mp3"),
            createSampleTrack(id: 2, title: "Remix Version", path: "/main/remix.mp3"),
            createSampleTrack(id: 3, title: "Live Version", path: "/main/live.mp3"),
            createSampleTrack(id: 4, title: "Acoustic Version", path: "/main/acoustic.mp3")
        ]
    }
    
    private func createGroupedTrack(mainTrackId: Int = 1, groupName: String = "Test Group") -> GroupedTrack {
        let tracks = createSampleTracks()
        let group = TrackGroup(
            trackIds: [1, 2, 3],
            mainTrackId: mainTrackId,
            name: groupName
        )
        let mainTrack = tracks.first { $0.id == mainTrackId }!
        let allTracks = tracks.filter { group.trackIds.contains($0.id!) }
        
        return GroupedTrack(
            group: group,
            mainTrack: mainTrack,
            allTracks: allTracks
        )
    }
    
    // MARK: - Property Delegation Tests
    
    func testGroupedTrackDelegatesAllTrackProperties() {
        let groupedTrack = createGroupedTrack(mainTrackId: 2) // Use track 2 as main
        let mainTrack = createSampleTrack(id: 2, title: "Remix Version", path: "/main/remix.mp3")
        
        // Test basic properties
        XCTAssertEqual(groupedTrack.id, mainTrack.id)
        XCTAssertEqual(groupedTrack.artist, mainTrack.artist)
        XCTAssertEqual(groupedTrack.album, mainTrack.album)
        XCTAssertEqual(groupedTrack.path, mainTrack.path)
        XCTAssertEqual(groupedTrack.isUrl, mainTrack.isUrl)
        XCTAssertEqual(groupedTrack.duration, mainTrack.duration)
        XCTAssertEqual(groupedTrack.rating, mainTrack.rating)
        XCTAssertEqual(groupedTrack.comment, mainTrack.comment)
        XCTAssertEqual(groupedTrack.generalTags, mainTrack.generalTags)
        
        // Test metadata properties
        XCTAssertEqual(groupedTrack.albumArtist, mainTrack.albumArtist)
        XCTAssertEqual(groupedTrack.composer, mainTrack.composer)
        XCTAssertEqual(groupedTrack.genre, mainTrack.genre)
        XCTAssertEqual(groupedTrack.year, mainTrack.year)
        XCTAssertEqual(groupedTrack.trackNumber, mainTrack.trackNumber)
        XCTAssertEqual(groupedTrack.discNumber, mainTrack.discNumber)
        XCTAssertEqual(groupedTrack.bpm, mainTrack.bpm)
        
        // Test computed properties
        XCTAssertEqual(groupedTrack.sourceType, mainTrack.sourceType)
        XCTAssertEqual(groupedTrack.formattedDuration, mainTrack.formattedDuration)
        XCTAssertEqual(groupedTrack.displayTitle, mainTrack.displayTitle)
        
        // Test sort helpers
        XCTAssertEqual(groupedTrack.idSortValue, mainTrack.idSortValue)
        XCTAssertEqual(groupedTrack.albumArtistText, mainTrack.albumArtistText)
        XCTAssertEqual(groupedTrack.composerText, mainTrack.composerText)
        XCTAssertEqual(groupedTrack.genreText, mainTrack.genreText)
        XCTAssertEqual(groupedTrack.yearSortValue, mainTrack.yearSortValue)
        XCTAssertEqual(groupedTrack.trackNumberSortValue, mainTrack.trackNumberSortValue)
        XCTAssertEqual(groupedTrack.discNumberSortValue, mainTrack.discNumberSortValue)
        XCTAssertEqual(groupedTrack.bpmSortValue, mainTrack.bpmSortValue)
        XCTAssertEqual(groupedTrack.isUrlSortValue, mainTrack.isUrlSortValue)
        XCTAssertEqual(groupedTrack.generalTagsText, mainTrack.generalTagsText)
        XCTAssertEqual(groupedTrack.dateAddedSortValue, mainTrack.dateAddedSortValue)
        XCTAssertEqual(groupedTrack.formattedDateAdded, mainTrack.formattedDateAdded)
    }
    
    func testGroupedTrackTitleUsesGroupNameWhenProvided() {
        let groupedTrack = createGroupedTrack(groupName: "Custom Group Name")
        XCTAssertEqual(groupedTrack.title, "Custom Group Name")
    }
    
    func testGroupedTrackTitleUsesMainTrackTitleWhenGroupNameEmpty() {
        let groupedTrack = createGroupedTrack(groupName: "")
        let mainTrack = createSampleTrack(id: 1, title: "Original Song")
        XCTAssertEqual(groupedTrack.title, mainTrack.title)
    }
    
    func testGroupedTrackPathDelegation() {
        let groupedTrack = createGroupedTrack(mainTrackId: 3) // Live version
        XCTAssertEqual(groupedTrack.path, "/main/live.mp3")
    }
    
    // MARK: - TrackDisplayItem Behavior Tests
    
    func testTrackDisplayItemContainerDelegatesToMainTrack() {
        let groupedTrack = createGroupedTrack(mainTrackId: 2)
        let displayItem = TrackDisplayItem.container(groupedTrack)
        
        // The .track property should return the main track
        XCTAssertEqual(displayItem.track.id, 2)
        XCTAssertEqual(displayItem.track.title, "Remix Version")
        XCTAssertEqual(displayItem.track.path, "/main/remix.mp3")
    }
    
    func testTrackDisplayItemIndividualReturnsOriginalTrack() {
        let track = createSampleTrack(id: 1, title: "Individual Track")
        let displayItem = TrackDisplayItem.individual(track)
        
        XCTAssertEqual(displayItem.track.id, 1)
        XCTAssertEqual(displayItem.track.title, "Individual Track")
    }
    
    func testTrackDisplayItemGroupMemberReturnsOriginalTrack() {
        let track = createSampleTrack(id: 2, title: "Member Track")
        let displayItem = TrackDisplayItem.groupMember(track, groupId: "test-group")
        
        XCTAssertEqual(displayItem.track.id, 2)
        XCTAssertEqual(displayItem.track.title, "Member Track")
    }
    
    // MARK: - Interaction Behavior Tests
    
    func testDoubleClickBehaviorOnContainerTrack() {
        // This test verifies that double-clicking a container track
        // should play the main track (via displayItem.track)
        let groupedTrack = createGroupedTrack(mainTrackId: 3) // Live version as main
        let displayItem = TrackDisplayItem.container(groupedTrack)
        
        // Simulate double-click behavior - should get main track
        let trackToPlay = displayItem.track
        
        XCTAssertEqual(trackToPlay.id, 3)
        XCTAssertEqual(trackToPlay.title, "Live Version")
        XCTAssertEqual(trackToPlay.path, "/main/live.mp3")
    }
    
    func testDragBehaviorOnContainerTrack() {
        // This test verifies that dragging a container track
        // should use the main track's path
        let groupedTrack = createGroupedTrack(mainTrackId: 2) // Remix as main
        let displayItem = TrackDisplayItem.container(groupedTrack)
        
        // Simulate drag behavior - should get main track path
        let trackForDrag = displayItem.track
        
        XCTAssertEqual(trackForDrag.path, "/main/remix.mp3")
        XCTAssertEqual(trackForDrag.id, 2)
    }
    
    func testKeyboardShortcutBehaviorOnContainerTrack() {
        // This test verifies that keyboard shortcuts on a container track
        // should operate on the main track
        let groupedTrack = createGroupedTrack(mainTrackId: 1) // Original as main
        let displayItem = TrackDisplayItem.container(groupedTrack)
        
        // Simulate keyboard shortcut behavior - should get main track
        let trackForShortcut = displayItem.track
        
        XCTAssertEqual(trackForShortcut.id, 1)
        XCTAssertEqual(trackForShortcut.title, "Original Song")
        XCTAssertEqual(trackForShortcut.path, "/main/original.mp3")
    }
    
    // MARK: - Main Track Change Tests
    
    func testMainTrackChangeUpdatesContainerBehavior() {
        let tracks = createSampleTracks()
        var group = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 1, name: "Test Group")
        
        // Initially main track is 1
        let initialGroupedTrack = GroupedTrack(
            group: group,
            mainTrack: tracks[0],
            allTracks: Array(tracks[0...2])
        )
        let initialDisplayItem = TrackDisplayItem.container(initialGroupedTrack)
        
        XCTAssertEqual(initialDisplayItem.track.id, 1)
        XCTAssertEqual(initialDisplayItem.track.path, "/main/original.mp3")
        
        // Change main track to 2
        _ = group.setMainTrack(2)
        let updatedGroupedTrack = GroupedTrack(
            group: group,
            mainTrack: tracks[1],
            allTracks: Array(tracks[0...2])
        )
        let updatedDisplayItem = TrackDisplayItem.container(updatedGroupedTrack)
        
        XCTAssertEqual(updatedDisplayItem.track.id, 2)
        XCTAssertEqual(updatedDisplayItem.track.path, "/main/remix.mp3")
    }
    
    // MARK: - Edge Cases
    
    func testContainerTrackWithUrlMainTrack() {
        let urlTrack = Track(
            id: 1,
            title: "YouTube Track",
            artist: "Online Artist",
            album: "Online Album",
            path: "https://youtube.com/watch?v=test",
            isUrl: true,
            duration: 200000
        )
        
        let group = TrackGroup(trackIds: [1, 2], mainTrackId: 1, name: "URL Group")
        let groupedTrack = GroupedTrack(
            group: group,
            mainTrack: urlTrack,
            allTracks: [urlTrack, createSampleTrack(id: 2, title: "Local Track")]
        )
        
        XCTAssertTrue(groupedTrack.isUrl)
        XCTAssertEqual(groupedTrack.sourceType, .youtube)
        XCTAssertEqual(groupedTrack.path, "https://youtube.com/watch?v=test")
    }
    
    func testContainerTrackWithValidMainTrack() {
        // This test ensures proper handling when main track is valid
        let tracks = createSampleTracks()
        let group = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 2, name: "Valid Group") // Valid main track ID
        
        // Verify that the group has a valid main track ID
        XCTAssertTrue(group.trackIds.contains(group.mainTrackId), "Group should have valid main track ID")
        XCTAssertEqual(group.mainTrackId, 2, "Main track ID should be valid")
        
        // Create GroupedTrack to verify it works correctly
        let mainTrack = tracks.first { $0.id == group.mainTrackId }!
        let allTracks = tracks.filter { group.trackIds.contains($0.id!) }
        let groupedTrack = GroupedTrack(group: group, mainTrack: mainTrack, allTracks: allTracks)
        
        XCTAssertEqual(groupedTrack.id, 2, "GroupedTrack should delegate to main track ID")
        XCTAssertEqual(groupedTrack.path, "/main/remix.mp3", "GroupedTrack should delegate to main track path")
    }
    
    // MARK: - Performance Tests
    
    func testPropertyDelegationPerformance() {
        let groupedTrack = createGroupedTrack()
        
        // Test that property access is fast (should be O(1))
        measure {
            for _ in 0..<1000 {
                _ = groupedTrack.title
                _ = groupedTrack.artist
                _ = groupedTrack.path
                _ = groupedTrack.duration
                _ = groupedTrack.formattedDuration
                _ = groupedTrack.sourceType
                _ = groupedTrack.rating
            }
        }
    }
    
    // MARK: - Integration Tests
    
    func testContainerTrackInDisplayItemArray() {
        let tracks = createSampleTracks()
        let group = TrackGroup(trackIds: [1, 2], mainTrackId: 2, name: "Integration Test Group")
        let groupedTrack = GroupedTrack(
            group: group,
            mainTrack: tracks[1],
            allTracks: Array(tracks[0...1])
        )
        
        let displayItems: [TrackDisplayItem] = [
            .individual(tracks[2]),
            .container(groupedTrack),
            .individual(tracks[3])
        ]
        
        // Test that we can extract tracks for operations
        let tracksForOperation = displayItems.map { $0.track }
        
        XCTAssertEqual(tracksForOperation.count, 3)
        XCTAssertEqual(tracksForOperation[0].id, 3) // Individual track
        XCTAssertEqual(tracksForOperation[1].id, 2) // Container -> main track
        XCTAssertEqual(tracksForOperation[2].id, 4) // Individual track
    }
}