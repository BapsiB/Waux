import XCTest
@testable import VAUX

class TrackGroupTests: XCTestCase {
    
    // MARK: - Test Data
    private func createSampleTrack(id: Int, title: String, artist: String = "Test Artist") -> Track {
        return Track(
            id: id,
            title: title,
            artist: artist,
            album: "Test Album",
            path: "/test/path/\(id).mp3",
            isUrl: false,
            duration: 180000 // 3 minutes
        )
    }
    
    private func createSampleTracks() -> [Track] {
        return [
            createSampleTrack(id: 1, title: "Original Song"),
            createSampleTrack(id: 2, title: "Remix Version"),
            createSampleTrack(id: 3, title: "Live Version"),
            createSampleTrack(id: 4, title: "Acoustic Version")
        ]
    }
    
    // MARK: - TrackGroup Tests
    
    func testTrackGroupInitialization() {
        let trackIds: Set<Int> = [1, 2, 3]
        let mainTrackId = 1
        let name = "Test Group"
        
        let group = TrackGroup(trackIds: trackIds, mainTrackId: mainTrackId, name: name)
        
        XCTAssertFalse(group.id.isEmpty)
        XCTAssertEqual(group.name, name)
        XCTAssertEqual(group.mainTrackId, mainTrackId)
        XCTAssertEqual(group.trackIds, trackIds)
        XCTAssertEqual(group.trackCount, 3)
        XCTAssertFalse(group.isExpanded)
        XCTAssertEqual(group.displayName, name)
    }
    
    func testTrackGroupInitializationWithEmptyName() {
        let trackIds: Set<Int> = [1, 2]
        let group = TrackGroup(trackIds: trackIds, mainTrackId: 1)
        
        XCTAssertTrue(group.name.isEmpty)
        XCTAssertEqual(group.displayName, "Track Group")
    }
    
    func testTrackGroupAddTrack() {
        var group = TrackGroup(trackIds: [1, 2], mainTrackId: 1)
        
        group.addTrack(3)
        
        XCTAssertTrue(group.contains(3))
        XCTAssertEqual(group.trackCount, 3)
    }
    
    func testTrackGroupRemoveTrack() {
        var group = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        let success = group.removeTrack(3)
        
        XCTAssertTrue(success)
        XCTAssertFalse(group.contains(3))
        XCTAssertEqual(group.trackCount, 2)
    }
    
    func testTrackGroupRemoveTrackFailsWithTwoTracks() {
        var group = TrackGroup(trackIds: [1, 2], mainTrackId: 1)
        
        let success = group.removeTrack(2)
        
        XCTAssertFalse(success)
        XCTAssertTrue(group.contains(2))
        XCTAssertEqual(group.trackCount, 2)
    }
    
    func testTrackGroupRemoveMainTrackFails() {
        var group = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        let success = group.removeTrack(1)
        
        XCTAssertFalse(success)
        XCTAssertTrue(group.contains(1))
        XCTAssertEqual(group.mainTrackId, 1)
    }
    
    func testTrackGroupSetMainTrack() {
        var group = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        let success = group.setMainTrack(2)
        
        XCTAssertTrue(success)
        XCTAssertEqual(group.mainTrackId, 2)
    }
    
    func testTrackGroupSetMainTrackFailsWithInvalidId() {
        var group = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        
        let success = group.setMainTrack(99)
        
        XCTAssertFalse(success)
        XCTAssertEqual(group.mainTrackId, 1)
    }
    
    // MARK: - TrackGroup Serialization Tests
    
    func testTrackGroupSerialization() throws {
        let originalGroup = TrackGroup(
            trackIds: [1, 2, 3],
            mainTrackId: 2,
            name: "Test Serialization Group"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalGroup)
        
        let decoder = JSONDecoder()
        let decodedGroup = try decoder.decode(TrackGroup.self, from: data)
        
        XCTAssertEqual(originalGroup.id, decodedGroup.id)
        XCTAssertEqual(originalGroup.name, decodedGroup.name)
        XCTAssertEqual(originalGroup.mainTrackId, decodedGroup.mainTrackId)
        XCTAssertEqual(originalGroup.trackIds, decodedGroup.trackIds)
        XCTAssertEqual(originalGroup.isExpanded, decodedGroup.isExpanded)
        XCTAssertEqual(originalGroup.dateCreated.timeIntervalSince1970, 
                      decodedGroup.dateCreated.timeIntervalSince1970, accuracy: 1.0)
    }
    
    // MARK: - TrackDisplayItem Tests
    
    func testTrackDisplayItemIndividual() {
        let track = createSampleTrack(id: 1, title: "Test Track")
        let displayItem = TrackDisplayItem.individual(track)
        
        XCTAssertEqual(displayItem.id, "track_1")
        XCTAssertEqual(displayItem.track.id, 1)
        XCTAssertFalse(displayItem.isGroup)
        XCTAssertFalse(displayItem.isGroupMember)
        XCTAssertNil(displayItem.groupId)
    }
    
    func testTrackDisplayItemContainer() {
        let tracks = createSampleTracks()
        let group = TrackGroup(trackIds: [1, 2], mainTrackId: 1, name: "Test Group")
        let groupedTrack = GroupedTrack(
            group: group,
            mainTrack: tracks[0],
            allTracks: Array(tracks[0...1])
        )
        let displayItem = TrackDisplayItem.container(groupedTrack)
        
        XCTAssertEqual(displayItem.id, "group_\(group.id)")
        XCTAssertEqual(displayItem.track.id, 1)
        XCTAssertTrue(displayItem.isGroup)
        XCTAssertFalse(displayItem.isGroupMember)
        XCTAssertEqual(displayItem.groupId, group.id)
    }
    
    func testTrackDisplayItemGroupMember() {
        let track = createSampleTrack(id: 2, title: "Member Track")
        let groupId = "test-group-id"
        let displayItem = TrackDisplayItem.groupMember(track, groupId: groupId)
        
        XCTAssertEqual(displayItem.id, "member_\(groupId)_2")
        XCTAssertEqual(displayItem.track.id, 2)
        XCTAssertFalse(displayItem.isGroup)
        XCTAssertTrue(displayItem.isGroupMember)
        XCTAssertEqual(displayItem.groupId, groupId)
    }
    
    // MARK: - GroupedTrack Tests
    
    func testGroupedTrackInitialization() {
        let tracks = createSampleTracks()
        let group = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 2, name: "Test Group")
        let groupedTrack = GroupedTrack(
            group: group,
            mainTrack: tracks[1], // id: 2
            allTracks: Array(tracks[0...2])
        )
        
        XCTAssertEqual(groupedTrack.id, 2)
        XCTAssertEqual(groupedTrack.title, "Test Group")
        XCTAssertEqual(groupedTrack.artist, "Test Artist")
        XCTAssertTrue(groupedTrack.isGroup)
        XCTAssertEqual(groupedTrack.trackCount, 3)
        XCTAssertFalse(groupedTrack.isExpanded)
    }
    
    func testGroupedTrackPropertyDelegation() {
        let mainTrack = Track(
            id: 1,
            title: "Main Track",
            artist: "Main Artist",
            album: "Main Album",
            albumArtist: "Main Album Artist",
            composer: "Main Composer",
            genre: "Rock",
            year: 2023,
            trackNumber: 5,
            discNumber: 1,
            bpm: 120,
            path: "/main/track.mp3",
            isUrl: false,
            duration: 240000,
            rating: 4,
            comment: "Great track",
            generalTags: ["rock", "favorite"]
        )
        
        let group = TrackGroup(trackIds: [1, 2], mainTrackId: 1, name: "")
        let groupedTrack = GroupedTrack(
            group: group,
            mainTrack: mainTrack,
            allTracks: [mainTrack, createSampleTrack(id: 2, title: "Other")]
        )
        
        // Test property delegation
        XCTAssertEqual(groupedTrack.id, 1)
        XCTAssertEqual(groupedTrack.title, mainTrack.title) // Empty group name, uses main track title
        XCTAssertEqual(groupedTrack.artist, "Main Artist")
        XCTAssertEqual(groupedTrack.album, "Main Album")
        XCTAssertEqual(groupedTrack.albumArtist, "Main Album Artist")
        XCTAssertEqual(groupedTrack.composer, "Main Composer")
        XCTAssertEqual(groupedTrack.genre, "Rock")
        XCTAssertEqual(groupedTrack.year, 2023)
        XCTAssertEqual(groupedTrack.trackNumber, 5)
        XCTAssertEqual(groupedTrack.discNumber, 1)
        XCTAssertEqual(groupedTrack.bpm, 120)
        XCTAssertEqual(groupedTrack.path, "/main/track.mp3")
        XCTAssertFalse(groupedTrack.isUrl)
        XCTAssertEqual(groupedTrack.duration, 240000)
        XCTAssertEqual(groupedTrack.rating, 4)
        XCTAssertEqual(groupedTrack.comment, "Great track")
        XCTAssertEqual(groupedTrack.generalTags, ["rock", "favorite"])
        
        // Test computed properties
        XCTAssertEqual(groupedTrack.formattedDuration, "4:00")
        XCTAssertEqual(groupedTrack.sourceType, .local)
        XCTAssertEqual(groupedTrack.displayTitle, "Main Track - Main Artist")
    }
    
    func testGroupedTrackWithGroupName() {
        let mainTrack = createSampleTrack(id: 1, title: "Original")
        let group = TrackGroup(trackIds: [1, 2], mainTrackId: 1, name: "Custom Group Name")
        let groupedTrack = GroupedTrack(
            group: group,
            mainTrack: mainTrack,
            allTracks: [mainTrack, createSampleTrack(id: 2, title: "Remix")]
        )
        
        XCTAssertEqual(groupedTrack.title, "Custom Group Name")
    }
    
    func testGroupedTrackWithUpdates() {
        let mainTrack = createSampleTrack(id: 1, title: "Original")
        let group = TrackGroup(trackIds: [1, 2], mainTrackId: 1)
        let groupedTrack = GroupedTrack(
            group: group,
            mainTrack: mainTrack,
            allTracks: [mainTrack, createSampleTrack(id: 2, title: "Remix")]
        )
        
        let updates: [String: Any] = ["title": "Updated Title", "rating": 5]
        let updatedGroupedTrack = groupedTrack.withUpdates(updates)
        
        XCTAssertEqual(updatedGroupedTrack.mainTrack.title, "Updated Title")
        XCTAssertEqual(updatedGroupedTrack.mainTrack.rating, 5)
        XCTAssertEqual(updatedGroupedTrack.group.id, group.id) // Group unchanged
    }
    
    func testGroupedTrackGetTrackById() {
        let tracks = createSampleTracks()
        let group = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 1)
        let groupedTrack = GroupedTrack(
            group: group,
            mainTrack: tracks[0],
            allTracks: Array(tracks[0...2])
        )
        
        let foundTrack = groupedTrack.getTrackById(2)
        XCTAssertNotNil(foundTrack)
        XCTAssertEqual(foundTrack?.id, 2)
        XCTAssertEqual(foundTrack?.title, "Remix Version")
        
        let notFoundTrack = groupedTrack.getTrackById(99)
        XCTAssertNil(notFoundTrack)
    }
    
    func testGroupedTrackIsMainTrack() {
        let tracks = createSampleTracks()
        let group = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 2)
        let groupedTrack = GroupedTrack(
            group: group,
            mainTrack: tracks[1],
            allTracks: Array(tracks[0...2])
        )
        
        XCTAssertFalse(groupedTrack.isMainTrack(tracks[0])) // id: 1
        XCTAssertTrue(groupedTrack.isMainTrack(tracks[1]))  // id: 2 (main)
        XCTAssertFalse(groupedTrack.isMainTrack(tracks[2])) // id: 3
    }
    
    // MARK: - Edge Cases and Validation Tests
    
    func testTrackGroupEquality() {
        let group1 = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 1, name: "Group A")
        let group2 = TrackGroup(trackIds: [1, 2, 3], mainTrackId: 1, name: "Group A")
        let group3 = TrackGroup(trackIds: [1, 2, 4], mainTrackId: 1, name: "Group A")
        
        // Different IDs but same content should not be equal
        XCTAssertNotEqual(group1, group2)
        
        // Same group should be equal to itself
        XCTAssertEqual(group1, group1)
        
        // Different track IDs should not be equal
        XCTAssertNotEqual(group1, group3)
    }
    
    func testGroupedTrackEquality() {
        let tracks = createSampleTracks()
        let group1 = TrackGroup(trackIds: [1, 2], mainTrackId: 1, name: "Group A")
        let group2 = TrackGroup(trackIds: [1, 2], mainTrackId: 1, name: "Group A")
        
        let groupedTrack1 = GroupedTrack(
            group: group1,
            mainTrack: tracks[0],
            allTracks: Array(tracks[0...1])
        )
        let groupedTrack2 = GroupedTrack(
            group: group2,
            mainTrack: tracks[0],
            allTracks: Array(tracks[0...1])
        )
        let groupedTrack3 = GroupedTrack(
            group: group1,
            mainTrack: tracks[0],
            allTracks: Array(tracks[0...1])
        )
        
        // Different groups should not be equal
        XCTAssertNotEqual(groupedTrack1, groupedTrack2)
        
        // Same group should be equal to itself
        XCTAssertEqual(groupedTrack1, groupedTrack3)
    }
}