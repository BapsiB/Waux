import XCTest
@testable import WAUX

class GroupNamingTests: XCTestCase {
    
    // MARK: - Test Properties
    private var trackGroupService: TrackGroupService!
    
    // MARK: - Test Setup and Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        trackGroupService = TrackGroupService()
    }
    
    override func tearDown() async throws {
        trackGroupService = nil
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods (Simulating TrackListView logic)
    
    /// Simulates the generateGroupName method from TrackListView
    private func generateGroupName(for track: Track?) -> String {
        guard let track = track else {
            return "Track Group"
        }
        
        // Use track title as base, with fallback patterns
        let baseTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if baseTitle.isEmpty {
            return "Track Group"
        }
        
        // Remove common version indicators to create a cleaner group name
        let cleanTitle = baseTitle
            .replacingOccurrences(of: #"\s*\([^)]*remix[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*\([^)]*version[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*\([^)]*edit[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*\([^)]*live[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*-\s*(remix|version|edit|live).*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let finalTitle = cleanTitle.isEmpty ? baseTitle : cleanTitle
        
        // Check if a group with this name already exists and add a number suffix if needed
        return ensureUniqueGroupName(finalTitle)
    }
    
    /// Simulates the ensureUniqueGroupName method from TrackListView
    private func ensureUniqueGroupName(_ baseName: String) -> String {
        let existingNames = Set(trackGroupService.groups.map { $0.name })
        
        if !existingNames.contains(baseName) {
            return baseName
        }
        
        // Find the next available number suffix
        var counter = 2
        while existingNames.contains("\(baseName) \(counter)") {
            counter += 1
        }
        
        return "\(baseName) \(counter)"
    }
    
    // MARK: - Group Naming Tests
    
    func testBasicGroupNameGeneration() {
        // Test Requirements: 4.3 - Auto-generated group naming
        let track = createTestTrack(title: "Song Title")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Song Title")
    }
    
    func testGroupNameGenerationWithRemixRemoval() {
        // Test Requirements: 4.3 - Clean group names by removing version indicators
        let track = createTestTrack(title: "Song Title (Remix)")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Song Title")
    }
    
    func testGroupNameGenerationWithVersionRemoval() {
        let track = createTestTrack(title: "Song Title (Live Version)")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Song Title")
    }
    
    func testGroupNameGenerationWithEditRemoval() {
        let track = createTestTrack(title: "Song Title (Radio Edit)")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Song Title")
    }
    
    func testGroupNameGenerationWithDashSeparatedVersion() {
        let track = createTestTrack(title: "Song Title - Remix")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Song Title")
    }
    
    func testGroupNameGenerationWithComplexVersionString() {
        let track = createTestTrack(title: "Song Title - Extended Remix Version")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Song Title")
    }
    
    func testGroupNameGenerationWithMultipleVersionIndicators() {
        let track = createTestTrack(title: "Song Title (Live) - Extended Version")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Song Title")
    }
    
    func testGroupNameGenerationWithEmptyTitle() {
        let track = createTestTrack(title: "")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Track Group")
    }
    
    func testGroupNameGenerationWithWhitespaceTitle() {
        let track = createTestTrack(title: "   \n\t   ")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Track Group")
    }
    
    func testGroupNameGenerationWithNilTrack() {
        let groupName = generateGroupName(for: nil)
        
        XCTAssertEqual(groupName, "Track Group")
    }
    
    func testGroupNameGenerationPreservesNonVersionText() {
        let track = createTestTrack(title: "Song Title (Featuring Artist)")
        let groupName = generateGroupName(for: track)
        
        // Should preserve featuring info since it's not a version indicator
        XCTAssertEqual(groupName, "Song Title (Featuring Artist)")
    }
    
    func testUniqueGroupNameGeneration() {
        // Test Requirements: 4.3 - Unique group names with number suffixes
        
        // Add existing groups to service
        let existingGroup1 = TrackGroup(trackIds: [1, 2], mainTrackId: 1, name: "Song Title")
        let existingGroup2 = TrackGroup(trackIds: [3, 4], mainTrackId: 3, name: "Song Title 2")
        
        trackGroupService.groups = [existingGroup1, existingGroup2]
        
        // Test generating name for new group
        let track = createTestTrack(title: "Song Title")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Song Title 3")
    }
    
    func testUniqueGroupNameGenerationWithGaps() {
        // Test that it finds the next available number, not necessarily sequential
        
        let existingGroup1 = TrackGroup(trackIds: [1, 2], mainTrackId: 1, name: "Song Title")
        let existingGroup2 = TrackGroup(trackIds: [3, 4], mainTrackId: 3, name: "Song Title 3")
        
        trackGroupService.groups = [existingGroup1, existingGroup2]
        
        let track = createTestTrack(title: "Song Title")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Song Title 2") // Should fill the gap
    }
    
    func testUniqueGroupNameGenerationWithNoConflict() {
        // Test that no suffix is added when there's no conflict
        
        let existingGroup = TrackGroup(trackIds: [1, 2], mainTrackId: 1, name: "Different Song")
        trackGroupService.groups = [existingGroup]
        
        let track = createTestTrack(title: "Song Title")
        let groupName = generateGroupName(for: track)
        
        XCTAssertEqual(groupName, "Song Title") // No suffix needed
    }
    
    func testCaseInsensitiveVersionRemoval() {
        let testCases = [
            ("Song Title (REMIX)", "Song Title"),
            ("Song Title (Live VERSION)", "Song Title"),
            ("Song Title (radio EDIT)", "Song Title"),
            ("Song Title - REMIX", "Song Title")
        ]
        
        for (input, expected) in testCases {
            let track = createTestTrack(title: input)
            let groupName = generateGroupName(for: track)
            XCTAssertEqual(groupName, expected, "Failed for input: \(input)")
        }
    }
    
    func testComplexTitleCleaning() {
        let testCases = [
            ("Amazing Song (Club Remix) (Extended Version)", "Amazing Song"),
            ("Great Track - Live at Venue", "Great Track"),
            ("Cool Song (Acoustic Version) - Radio Edit", "Cool Song"),
            ("Best Song (Original Mix)", "Best Song"),
            ("New Track (Instrumental Edit)", "New Track")
        ]
        
        for (input, expected) in testCases {
            let track = createTestTrack(title: input)
            let groupName = generateGroupName(for: track)
            XCTAssertEqual(groupName, expected, "Failed for input: \(input)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestTrack(title: String) -> Track {
        return Track(
            id: 1,
            title: title,
            artist: "Test Artist",
            album: "Test Album",
            albumArtist: nil,
            composer: nil,
            genre: nil,
            year: nil,
            trackNumber: nil,
            discNumber: nil,
            bpm: nil,
            path: "/test/path.mp3",
            isUrl: false,
            duration: 180000,
            timeMarkers: [],
            waveformData: nil,
            rating: 0,
            comment: "",
            generalTags: [],
            dateAdded: Date()
        )
    }
}