import Foundation
import AVFoundation
import CoreMedia

/// Service for managing audio metadata in the database
/// Note: File metadata writing has been removed - only database operations are supported
@MainActor
class AudioMetadataWriter: ObservableObject {
    
    // MARK: - Properties
    @Published private(set) var isWriting = false
    @Published private(set) var lastError: String?
    
    // MARK: - Public Methods
    
    /// Updates metadata in the database for a track
    /// - Parameters:
    ///   - trackId: The track ID to update
    ///   - metadata: Dictionary of metadata to update
    /// - Returns: Success status
    func updateMetadata(for trackId: String, metadata: [String: Any]) async -> Bool {
        isWriting = true
        lastError = nil
        
        defer { isWriting = false }
        
        // TODO: Implement database update logic here
        // For now, we'll just return success since we're only updating the database
        print("[AudioMetadataWriter] Updating metadata in database for track: \(trackId)")
        print("[AudioMetadataWriter] Metadata: \(metadata)")
        
        return true
    }
    
    /// Updates metadata in the database for multiple tracks
    /// - Parameters:
    ///   - trackIds: Array of track IDs to update
    ///   - metadata: Dictionary of metadata to update for all tracks
    /// - Returns: Dictionary mapping track IDs to success status
    func updateMetadataForMultipleTracks(trackIds: [String], metadata: [String: Any]) async -> [String: Bool] {
        var results: [String: Bool] = [:]
        
        for trackId in trackIds {
            let success = await updateMetadata(for: trackId, metadata: metadata)
            results[trackId] = success
        }
        
        return results
    }
    
    /// Validates metadata before updating
    /// - Parameter metadata: Dictionary of metadata to validate
    /// - Returns: Validation result with any errors
    func validateMetadata(_ metadata: [String: Any]) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Validate title
        if let title = metadata["title"] as? String, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Title cannot be empty")
        }
        
        // Validate artist
        if let artist = metadata["artist"] as? String, artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Artist cannot be empty")
        }
        
        // Validate year if present
        if let yearString = metadata["year"] as? String {
            if let year = Int(yearString) {
                if year < 1900 || year > Calendar.current.component(.year, from: Date()) + 1 {
                    errors.append("Year must be between 1900 and next year")
                }
            } else {
                errors.append("Year must be a valid number")
            }
        }
        
        // Validate track number if present
        if let trackNumberString = metadata["tracknumber"] as? String {
            if let trackNumber = Int(trackNumberString) {
                if trackNumber < 1 {
                    errors.append("Track number must be greater than 0")
                }
            } else {
                errors.append("Track number must be a valid number")
            }
        }
        
        return (errors.isEmpty, errors)
    }
}
