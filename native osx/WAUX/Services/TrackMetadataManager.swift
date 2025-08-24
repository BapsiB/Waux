import Foundation
import Combine
import SwiftUI

/// A unified metadata manager that provides a single source of truth for track updates
/// Eliminates race conditions and provides optimistic UI updates
@MainActor
class TrackMetadataManager: ObservableObject {
    // MARK: - Properties
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isUpdating = false
    
    private let collectionService: CollectionService
    private var cancellables = Set<AnyCancellable>()
    
    // Optimistic UI state for immediate feedback
    private var optimisticChanges: [Int: TrackChanges] = [:]
    
    // Debounced batch updates to prevent excessive database writes
    private var pendingUpdates: [Int: TrackChanges] = [:]
    private var updateTimer: Timer?
    private let updateDebounceInterval: TimeInterval = 0.5
    
    // MARK: - Initialization
    init(collectionService: CollectionService) {
        self.collectionService = collectionService
        setupBindings()
    }
    
    private func setupBindings() {
        // Single subscription to collection service tracks
        collectionService.$tracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTracks in
                self?.handleTracksUpdate(newTracks)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Track Access
    func getTrack(id: Int) -> Track? {
        let baseTrack = tracks.first { $0.id == id }
        guard let track = baseTrack else { return nil }
        
        // Apply optimistic changes if any
        if let changes = optimisticChanges[id] {
            return applyChanges(to: track, changes: changes)
        }
        
        return track
    }
    
    func getTracks(ids: [Int]) -> [Track] {
        return ids.compactMap { getTrack(id: $0) }
    }
    
    func getAllTracks() -> [Track] {
        return tracks.map { track in
            if let changes = optimisticChanges[track.id ?? -1] {
                return applyChanges(to: track, changes: changes)
            }
            return track
        }
    }
    
    // MARK: - Tag Operations
    func addTag(to trackIds: [Int], tag: String) {
        print("[TrackMetadataManager] Adding tag '\(tag)' to tracks: \(trackIds)")
        
        // Apply optimistic changes immediately for UI responsiveness
        for trackId in trackIds {
            var changes = optimisticChanges[trackId] ?? TrackChanges()
            changes.addedTags.insert(tag)
            changes.removedTags.remove(tag) // In case it was being removed
            optimisticChanges[trackId] = changes
            
            // Queue for batch update
            pendingUpdates[trackId] = changes
        }
        
        // Trigger UI update
        objectWillChange.send()
        
        // Schedule database update
        scheduleUpdate()
    }
    
    func removeTag(from trackIds: [Int], tag: String) {
        print("[TrackMetadataManager] Removing tag '\(tag)' from tracks: \(trackIds)")
        
        // Apply optimistic changes immediately
        for trackId in trackIds {
            var changes = optimisticChanges[trackId] ?? TrackChanges()
            changes.removedTags.insert(tag)
            changes.addedTags.remove(tag) // In case it was being added
            optimisticChanges[trackId] = changes
            
            // Queue for batch update
            pendingUpdates[trackId] = changes
        }
        
        // Trigger UI update
        objectWillChange.send()
        
        // Schedule database update
        scheduleUpdate()
    }
    
    func setTags(for trackId: Int, tags: [String]) {
        print("[TrackMetadataManager] Setting tags for track \(trackId): \(tags)")
        
        guard let currentTrack = tracks.first(where: { $0.id == trackId }) else {
            print("[TrackMetadataManager] Track \(trackId) not found")
            return
        }
        
        let currentTags = Set(currentTrack.generalTags)
        let newTags = Set(tags)
        
        var changes = TrackChanges()
        changes.addedTags = newTags.subtracting(currentTags)
        changes.removedTags = currentTags.subtracting(newTags)
        
        optimisticChanges[trackId] = changes
        pendingUpdates[trackId] = changes
        
        // Trigger UI update
        objectWillChange.send()
        
        // Schedule database update
        scheduleUpdate()
    }
    
    func updateRating(for trackId: Int, rating: Int) {
        print("[TrackMetadataManager] Updating rating for track \(trackId): \(rating)")
        
        var changes = optimisticChanges[trackId] ?? TrackChanges()
        changes.newRating = rating
        optimisticChanges[trackId] = changes
        pendingUpdates[trackId] = changes
        
        // Trigger UI update
        objectWillChange.send()
        
        // Schedule database update
        scheduleUpdate()
    }
    
    // MARK: - Private Methods
    private func handleTracksUpdate(_ newTracks: [Track]) {
        print("[TrackMetadataManager] Received tracks update: \(newTracks.count) tracks")
        
        // Update base tracks
        tracks = newTracks
        
        // Clear optimistic changes for tracks that have been successfully updated
        // This prevents stale optimistic state from persisting
        let updatedTrackIds = Set(newTracks.compactMap { $0.id })
        optimisticChanges = optimisticChanges.filter { !updatedTrackIds.contains($0.key) }
        
        // Trigger UI update
        objectWillChange.send()
    }
    
    private func scheduleUpdate() {
        // Cancel existing timer
        updateTimer?.invalidate()
        
        // Set new timer for debounced updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.executePendingUpdates()
            }
        }
    }
    
    private func executePendingUpdates() async {
        guard !pendingUpdates.isEmpty else { return }
        
        print("[TrackMetadataManager] Executing \(pendingUpdates.count) pending updates")
        isUpdating = true
        
        let updates = pendingUpdates
        pendingUpdates.removeAll()
        
        do {
            // Group updates by type for efficient batch processing
            var tagUpdates: [Int: [String]] = [:]
            var ratingUpdates: [Int: Int] = [:]
            
            for (trackId, changes) in updates {
                guard let track = tracks.first(where: { $0.id == trackId }) else { continue }
                
                // Calculate final tag state
                var finalTags = Set(track.generalTags)
                finalTags.formUnion(changes.addedTags)
                finalTags.subtract(changes.removedTags)
                tagUpdates[trackId] = Array(finalTags).sorted { $0.lowercased() < $1.lowercased() }
                
                // Rating updates
                if let newRating = changes.newRating {
                    ratingUpdates[trackId] = newRating
                }
            }
            
            // Execute batch updates
            for (trackId, tags) in tagUpdates {
                try await collectionService.setTagsForTrack(trackId: trackId, newTags: tags)
            }
            
            for (trackId, rating) in ratingUpdates {
                try await collectionService.updateTrackRating(trackId: trackId, newRating: rating)
            }
            
            print("[TrackMetadataManager] Successfully executed all updates")
            
        } catch {
            print("[TrackMetadataManager] Error executing updates: \(error)")
            
            // On error, clear optimistic changes to revert to actual state
            for trackId in updates.keys {
                optimisticChanges.removeValue(forKey: trackId)
            }
            objectWillChange.send()
        }
        
        isUpdating = false
    }
    
    private func applyChanges(to track: Track, changes: TrackChanges) -> Track {
        var newTags = Set(track.generalTags)
        newTags.formUnion(changes.addedTags)
        newTags.subtract(changes.removedTags)
        
        let finalTags = Array(newTags).sorted { $0.lowercased() < $1.lowercased() }
        let finalRating = changes.newRating ?? track.rating
        
        return Track(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            albumArtist: track.albumArtist,
            composer: track.composer,
            genre: track.genre,
            year: track.year,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            bpm: track.bpm,
            path: track.path,
            isUrl: track.isUrl,
            duration: track.duration,
            timeMarkers: track.timeMarkers,
            waveformData: track.waveformData,
            rating: finalRating,
            comment: track.comment,
            generalTags: finalTags
        )
    }
}

// MARK: - Supporting Types
private struct TrackChanges {
    var addedTags: Set<String> = []
    var removedTags: Set<String> = []
    var newRating: Int?
}
