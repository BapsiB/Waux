# Cue File Parsing - 4 Layer Architecture

## Overview

The `CueFileParsingService` has been reorganized into a clean 4-layer architecture for parsing cue files exported from DAWs. Each layer performs a specific transformation on the data.

## Data Structures

### ParsedName
```swift
struct ParsedName {
    let catalogID: String      // e.g., "UPM_MAT103_7"
    let title: String          // e.g., "Champions_Instrumental_Martin_8168"
    let fullName: String       // Original full name
}
```

### CueEvent
```swift
struct CueEvent {
    var channel: Int
    var eventID: Int
    var catalogID: String          // The catalog/ID prefix
    var title: String              // The descriptive title
    var originalClipName: String   // Full original clip name
    var startTime: String
    var endTime: String
    var duration: String
    var state: String
    var uniqueTitles: Set<String>  // Track unique titles when merging
    var composer: String
}
```

## Layer 1: Parse Raw File

**Function:** `parseRawFile(lines: [String]) -> [CueEvent]`

**Purpose:** Parse each line of the cue file into individual CueEvent objects.

**Process:**
1. Read each line and extract fields (channel, event ID, clip name, times, etc.)
2. Parse clip names into catalog ID and title using `parseName()`
3. Identify fade events as `FADE_IN`, `FADE_OUT`, or `CROSS_FADE`
4. Skip muted events
5. Create a CueEvent for each valid line

**Output:** Array of CueEvents, one per line (excluding muted events)

## Layer 2: Aggregate Fades with Clips

**Function:** `aggregateFadesWithClips(events: [CueEvent]) -> [CueEvent]`

**Purpose:** Merge fade events with adjacent clips according to specific rules.

**Process:**

### Fade In
- Merged with the **next** clip
- Use fade in's **start time** and clip's **end time**

### Fade Out
- Merged with the **previous** aggregated event
- Use clip's **start time** and fade out's **end time**

### Cross Fade
Two cases:

**Case 1: Different Catalog IDs**
```
Event A (catalog X) → Cross Fade → Event B (catalog Y)
```
- Cross fade is **counted twice**
- Event A gets extended: end time = cross fade end time
- Event B gets extended: start time = cross fade start time
- Both events include the cross fade duration

**Case 2: Same Catalog ID**
```
Event A (catalog X) → Cross Fade → Event B (catalog X)
```
- All three are **merged together** (cross fade counted once)
- Combined event: start time = Event A start, end time = Event B end
- Track both unique titles in `uniqueTitles` set

**Processing:** Done per channel, maintaining event order.

**Output:** Array of CueEvents with fades merged into clips

## Layer 3: Merge Across Channels

**Function:** `mergeAcrossChannels(events: [CueEvent]) -> [CueEvent]`

**Purpose:** Merge events from different channels that overlap in time and have the same catalog ID.

**Process:**
1. Group events by catalog ID
2. For each catalog ID, sort events by start time
3. Find overlapping events (event B overlaps event A if B.startTime ≤ A.endTime)
4. Merge overlapping events:
   - Use minimum start time
   - Use maximum end time
   - Combine unique titles
5. Recalculate duration

**Example:**
```
Channel 1: Event A (01:00:00 - 01:00:30) - catalog X
Channel 2: Event A (01:00:00 - 01:00:30) - catalog X
→ Merged: (01:00:00 - 01:00:30) - catalog X (counted once)
```

**Output:** Array of CueEvents merged across channels

## Layer 4: Final Aggregation

**Function:** `finalAggregation(events: [CueEvent]) -> [CueEvent]`

**Purpose:** Merge all events with the same catalog ID by calculating the total time span (min start to max end).

**Process:**
1. Group events by catalog ID
2. For each catalog ID:
   - Track minimum start time (earliest occurrence)
   - Track maximum end time (latest occurrence)
   - Calculate duration from min start to max end
   - Collect all unique titles into a set
3. Create one final event per catalog ID

**Important:** This layer **recalculates durations** using min/max times instead of summing duration fields. This ensures the duration represents the actual time span covered by all events with that catalog ID, regardless of gaps or overlaps.

**Example:**
```
Catalog X: Event at 01:00:00-01:00:30 (30s)
Catalog X: Event at 01:05:00-01:05:15 (15s)

❌ Summing durations: 30s + 15s = 45s
✅ Min/Max calculation: 01:00:00 to 01:05:15 = 5m 15s (315s)
```

The min/max approach correctly captures that this catalog ID covers a 5-minute 15-second span in the timeline, even though there's a gap in between.

**Output:** Array of CueEvents, one per unique catalog ID, with calculated duration and all unique titles

## Main Entry Point

**Function:** `aggregateEvents(from lines: [String]) -> [CueEvent]`

**Purpose:** Process cue file through all 4 layers in sequence.

**Process:**
```swift
let layer1 = parseRawFile(lines: lines)
let layer2 = aggregateFadesWithClips(events: layer1)
let layer3 = mergeAcrossChannels(events: layer2)
let layer4 = finalAggregation(events: layer3)
return layer4
```

## Name Parsing Algorithm

The `parseName()` function splits clip names into catalog ID and title:

**Algorithm:**
1. Check if it's a fade event → return appropriate FADE_* catalog ID
2. Remove channel suffixes (.L, .R, .A1, etc.)
3. Remove track/take numbers (.1, .2, etc.)
4. Find digit sequences in the string
5. Look for the last digit sequence followed by underscore/dash and a letter
6. Split at that boundary:
   - Before = catalog ID (e.g., "UPM_MAT103_7")
   - After = title (e.g., "Champions_Instrumental_Martin_8168")

**Examples:**
```
Input:  "UPM_MAT103_7_Champions_Instrumental_Martin_8168-04.L"
Output: catalogID: "UPM_MAT103_7"
        title: "Champions_Instrumental_Martin_8168"

Input:  "MISS_25FPS_MX_DCP_STEREO_WIP_250721-96.L"
Output: catalogID: "MISS_25FPS_MX_DCP_STEREO_WIP_250721"
        title: "96" (or could be enhanced to handle this case)

Input:  "(fade in)"
Output: catalogID: "FADE_IN"
        title: ""
```

## Debugging

Each layer prints detailed debug information:
- 📄 Layer 1: Parse progress
- 🔀 Layer 2: Fade merging operations
- 📡 Layer 3: Channel merging operations
- 📊 Layer 4: Final aggregation

Look for these emojis in the console output to track processing.

## Usage Example

### Basic Usage (Final Result Only)
```swift
let parsingService = CueFileParsingService()
let content = try String(contentsOf: cueFileURL, encoding: .utf8)
let lines = content.components(separatedBy: .newlines)
let events = parsingService.aggregateEvents(from: lines)

// events now contains one entry per unique catalog ID
// with total duration and all unique titles tracked
```

### Debug Usage (All Layers)
```swift
let parsingService = CueFileParsingService()
let content = try String(contentsOf: cueFileURL, encoding: .utf8)
let lines = content.components(separatedBy: .newlines)
let result = parsingService.parseWithAllLayers(from: lines)

// Access each layer for debugging
let layer1Events = result.layer1  // Raw parsed events
let layer2Events = result.layer2  // Fades merged with clips
let layer3Events = result.layer3  // Merged across channels
let layer4Events = result.layer4  // Final aggregation
```

## Debug Visualization in CueFileHelperView

The UI includes a **segmented control** to switch between viewing different parsing layers:

- **Layer 1: Raw Parse** - Shows every line parsed into a CueEvent
- **Layer 2: Fades Merged** - Shows events after fades are aggregated with clips
- **Layer 3: Channels Merged** - Shows events after merging across channels
- **Layer 4: Final** - Shows the final aggregated result (one per catalog ID)

### Text Filter

A **search/filter field** allows you to filter the table by:
- **Catalog ID** (e.g., "UPM_MAT103")
- **Title** (e.g., "Champions")

The filter works across all layers and updates the table in real-time. The status bar shows the filtered count vs total count (e.g., "15 / 47 filtered events in Layer 1: Raw Parse").

### Features

This allows you to:
- Debug parsing issues at each stage
- Understand how fades are being merged
- Verify channel merging is working correctly
- Filter events to track specific catalog IDs through all layers
- Export CSV at any layer (filtered or unfiltered) for external analysis

**Notes:**
- Composer fetching only works on Layer 4, as it requires the final aggregated catalog IDs
- Filter persists when switching between layers, making it easy to track specific events through the pipeline
- Click the X button in the filter field to quickly clear the filter

