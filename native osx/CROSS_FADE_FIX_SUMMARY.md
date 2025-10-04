# Cross Fade Aggregation Fix

## Problem

The `aggregateFadesWithClips` function in `CueFileParsingService.swift` was not properly handling long chains of same-catalog events separated by cross fades.

### Example Issue

When processing a sequence like:
```
fade in
clip A (catalog X)
cross fade
clip A (catalog X)
cross fade
clip A (catalog X)
...
```

The old code would merge them in pairs (clip + cross + clip), creating multiple separate events instead of one continuous chain.

## Root Cause

The original logic:
1. Looked forward one step at a time
2. When it found a cross fade followed by same-catalog clip, it merged those three elements
3. Then jumped forward by 2 positions (`i += 2`)
4. The next iteration would start at the next cross fade, not realizing it should continue the chain

## Solution

Changed the forward-looking logic to use a **while loop** that continues merging as long as it finds cross fades followed by same-catalog events:

```swift
// Old: Single forward look
if i < channelEvents.count - 1 {
    let nextEvent = channelEvents[i + 1]
    // ... handle cross fade
    i += 2 // Skip and move on
}

// New: Loop until chain breaks
while nextIndex < channelEvents.count {
    let nextEvent = channelEvents[nextIndex]
    
    if afterCrossFade.catalogID == event.catalogID {
        // Merge and continue loop
        mergedEvent.endTime = afterCrossFade.endTime
        nextIndex += 2
        // Loop continues to check for more cross fades
    } else {
        break // Different catalog, stop
    }
}
```

## Test Results

Created comprehensive tests in `test_fade_aggregation.swift`:

### Test 1: Long Chain (28 events → 1 merged event)
- **Input**: Fade in + 13 clips of same catalog separated by cross fades
- **Expected**: 1 event from 01:00:08:01 to 01:00:57:03
- **Result**: ✅ PASS

### Test 2: Chain with Different Catalog (22 events → 3 merged events)
- **Input**: MISS_25FPS chain interrupted by OTHER_FILE, then back to MISS_25FPS
- **Expected**: 3 separate events with proper cross fade handling
- **Result**: ✅ PASS

### Test 3: Multiple Chains with Fade Out (10 events → 2 merged events)
- **Input**: Two separate chains (CAT_A and CAT_B) with fade in/out
- **Expected**: 2 events with proper fade handling
- **Result**: ✅ PASS

## Key Changes in Code

1. **Introduced `nextIndex` variable**: Tracks the next unprocessed event index
2. **While loop for forward merging**: Continues until hitting a different catalog or non-fade event
3. **Better fade out handling**: Properly breaks the chain after fade out
4. **Cleaner index management**: `i = nextIndex` at the end ensures we don't reprocess events

## Files Modified

- `WAUX/Services/CueFileParsingService.swift` - Fixed `aggregateFadesWithClips` method
- `test_fade_aggregation.swift` - New comprehensive test suite

## Running Tests

```bash
swiftc WAUX/Services/CueFileParsingService.swift test_fade_aggregation.swift -o test_fade_bin && ./test_fade_bin
```

All tests now pass successfully! ✅

## Update: Muted Clip Handling

### Additional Problem

When a muted clip sits between two unmuted clips with cross fades on either side:
- The muted clip gets filtered out in Layer 1
- The cross fades remain, creating potential for incorrect merging
- If both clips have the same catalog ID, they could be incorrectly merged across large time gaps

### Solution

Added logic in Layer 1 to handle muted clips:

1. **Convert adjacent cross fades**: When a muted clip is detected:
   - Cross fade BEFORE muted clip → convert to FADE_OUT
   - Cross fade AFTER muted clip → convert to FADE_IN

2. **Temporal adjacency checking**: In Layer 2, added checks to ensure fades are only merged with clips if they're temporally adjacent:
   - FADE_IN: Only merge if `fade.endTime == clip.startTime`
   - FADE_OUT: Only merge if `clip.endTime == fade.startTime`
   - Non-adjacent fades are skipped with a warning message

### Additional Tests

**Test 4**: Muted clip with different catalog IDs
- Verifies cross fades are properly converted and handled

**Test 5**: Muted clip with same catalog on both sides (CRITICAL)
- Tests the most problematic case where same-catalog clips could be incorrectly merged
- Ensures temporal gaps prevent incorrect merging
- Result: 2 separate events with correct durations (36 seconds total, not 5+ minutes)

All 5 tests pass! ✅

