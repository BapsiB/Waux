# Migration Guide: Unified Track Metadata Manager

This guide explains how to implement the new TrackMetadataManager to fix the tag removal issue and create a robust, race-condition-free track update system.

## Problem Summary

The current system has race conditions where:
1. Multiple views update the same track simultaneously
2. TagEditorView has competing change listeners that overwrite local state
3. Track objects become stale due to immutable struct nature
4. No single source of truth for track metadata

## Solution Architecture

The new `TrackMetadataManager` provides:
- ✅ Single source of truth for all track updates
- ✅ Optimistic UI updates for immediate feedback
- ✅ Debounced batch database updates to prevent conflicts
- ✅ Automatic conflict resolution
- ✅ Real-time UI synchronization across all views

## Implementation Steps

### Step 1: Add TrackMetadataManager

Copy `TrackMetadataManager.swift` to your project and add it to the Xcode project.

### Step 2: Update Your Main App/ContentView

```swift
// OLD - Direct CollectionService usage
@StateObject private var collectionService = CollectionService()

// NEW - Add TrackMetadataManager
@StateObject private var collectionService = CollectionService()
@StateObject private var metadataManager: TrackMetadataManager

init() {
    let collectionService = CollectionService()
    let metadataManager = TrackMetadataManager(collectionService: collectionService)
    
    _collectionService = StateObject(wrappedValue: collectionService)
    _metadataManager = StateObject(wrappedValue: metadataManager)
}
```

### Step 3: Update TrackListView

```swift
// OLD - Use collectionService.tracks directly
private var tracks: [Track] {
    collectionService.tracks
}

// NEW - Use metadataManager for track data
@ObservedObject var metadataManager: TrackMetadataManager

private var tracks: [Track] {
    metadataManager.getAllTracks()
}
```

### Step 4: Replace InteractiveTagsView

```swift
// OLD - Direct collectionService calls
InteractiveTagsView(
    track: track,
    onUpdate: { tags in
        Task {
            try await collectionService.setTagsForTrack(trackId: track.id ?? 0, newTags: tags)
        }
    }
)

// NEW - Use metadata manager
if let trackId = track.id {
    InteractiveTagsView_New(
        trackId: trackId,
        metadataManager: metadataManager
    )
}
```

### Step 5: Replace InteractiveStarRating

```swift
// OLD - Direct collectionService calls
InteractiveStarRating(track: track) { newRating in
    Task {
        try await collectionService.updateTrackRating(trackId: track.id ?? 0, newRating: newRating)
    }
}

// NEW - Use metadata manager
if let trackId = track.id {
    InteractiveStarRating_New(
        trackId: trackId,
        metadataManager: metadataManager
    )
}
```

### Step 6: Replace TagEditorView

```swift
// OLD - Complex state management with race conditions
TagEditorView(collectionService: collectionService, tracks: selectedTracks)

// NEW - Clean interface with metadata manager
TagEditorView_New(
    metadataManager: metadataManager,
    collectionService: collectionService,
    trackIds: selectedTrackIds
)
```

## Key Benefits

### 1. No More Race Conditions
- Single update pathway through TrackMetadataManager
- Debounced batch updates prevent database conflicts
- Optimistic UI updates provide immediate feedback

### 2. Simplified State Management
- No more complex onChange/onReceive listeners in TagEditorView
- No more manual track synchronization
- Automatic UI updates across all views

### 3. Better Performance
- Batch database updates reduce DB load
- Optimistic updates eliminate UI lag
- Efficient change propagation

### 4. Easier Debugging
- Centralized logging in TrackMetadataManager
- Clear separation of UI and data concerns
- Predictable update flow

## Testing the Fix

1. **Tag Addition**: Add tags in TagEditorView - they should persist immediately
2. **Concurrent Updates**: Edit tags in both TagEditorView and table inline editor
3. **Multiple Tracks**: Edit tags for multiple selected tracks
4. **Fast Interactions**: Rapidly add/remove tags to test debouncing

## Migration Timeline

### Phase 1: Parallel Implementation
- Add new components alongside existing ones
- Test thoroughly with new system
- Keep old system as fallback

### Phase 2: Gradual Replacement
- Replace TagEditorView first (highest impact)
- Replace InteractiveTagsView in table
- Replace rating components

### Phase 3: Cleanup
- Remove old TagEditorView.swift
- Remove old InteractiveTagsView.swift
- Clean up unused collection service methods

## Rollback Plan

If issues arise:
1. Keep old files as `_Original.swift`
2. Switch back to old components in ContentView
3. Remove TrackMetadataManager temporarily
4. Debug and fix issues before re-attempting

## Notes

- The CollectionService remains unchanged for database operations
- Global tags management stays in CollectionService
- Only track updates go through TrackMetadataManager
- All existing database structure and APIs are preserved
