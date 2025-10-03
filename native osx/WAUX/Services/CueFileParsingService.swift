//
//  CueFileParsingService.swift
//  WAUX
//
//  Created by AI Assistant on 03/10/2025.
//

import Foundation

struct CueEvent: Identifiable {
    let id = UUID()
    var channel: Int
    var eventID: Int
    var clipName: String
    var startTime: String
    var endTime: String
    var duration: String
    var state: String
    var allNames: String
    var composer: String
}

class CueFileParsingService {
    
    // Simplified name processing - extracts catalog/ID prefix from clip names
    func getSimplifiedName(_ clipName: String) -> String {
        var trimmedName = clipName
        
        // Step 1: Remove common suffixes (.L, .R, .A1, track numbers, etc.)
        // First remove channel suffixes like -03.L, .L, .R, .A1
        if let suffixMatch = trimmedName.range(of: "[-.]\\w+\\.(L|R|A\\d+)$", options: .regularExpression) {
            trimmedName = String(trimmedName[..<suffixMatch.lowerBound])
        } else if let suffixMatch = trimmedName.range(of: "\\.(L|R|A\\d+)$", options: .regularExpression) {
            trimmedName = String(trimmedName[..<suffixMatch.lowerBound])
        }
        
        // Remove remaining track/take numbers like .1, .2, etc.
        if let suffixMatch = trimmedName.range(of: "\\.\\d+$", options: .regularExpression) {
            trimmedName = String(trimmedName[..<suffixMatch.lowerBound])
        }
        
        // Step 2: Try to extract the catalog/ID prefix
        // Pattern: Letters/symbols followed by numbers, before the descriptive title
        // Example: "UPM_LQC71_15_Mogadishu..." -> "UPM_LQC71_15"
        // Example: "_UPRIGHT_GMPM_197_041_Storyteller..." -> "_UPRIGHT_GMPM_197_041"
        
        // Find sequences of digits in the string
        let digitPattern = "\\d+"
        let regex = try? NSRegularExpression(pattern: digitPattern, options: [])
        let nsString = trimmedName as NSString
        let matches = regex?.matches(in: trimmedName, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        // If we found digit sequences, look for the pattern
        if !matches.isEmpty {
            // Find the last digit sequence that's followed by an underscore and a letter (likely the title start)
            for (index, match) in matches.enumerated() {
                let matchEnd = match.range.location + match.range.length
                
                // Check if there's more content after this number
                if matchEnd < trimmedName.count {
                    let afterNumberIndex = trimmedName.index(trimmedName.startIndex, offsetBy: matchEnd)
                    let remainingString = String(trimmedName[afterNumberIndex...])
                    
                    // Check if the remaining part starts with underscore/separator followed by a letter (title part)
                    // Also check if this isn't the last number sequence (to avoid cutting off version numbers)
                    if remainingString.range(of: "^[_-][A-Za-z]", options: .regularExpression) != nil {
                        // This looks like the boundary between catalog and title
                        // Check if there are more digit sequences after this one
                        let hasMoreDigits = index < matches.count - 1
                        
                        if !hasMoreDigits {
                            // This is the last digit sequence before the title
                            trimmedName = String(trimmedName[..<afterNumberIndex])
                            break
                        }
                    }
                }
            }
        }
        
        return trimmedName
    }
    
    // Test helper function
    func testSimplification() {
        let testCases = [
            ("UPM_LQC71_15_Mogadishu_Drone_Instrumental_Huntley_McNeil-Poly.L", "UPM_LQC71_15"),
            ("_UPRIGHT_GMPM_197_041_Storyteller_(Strings_Only)-13.A1", "_UPRIGHT_GMPM_197_041"),
            ("Baptiste Bohelay - Don't Look Back 2-01.L", "Baptiste Bohelay - Don't Look Back 2"),
            ("TEST_ABC123_456_Some_Title.R", "TEST_ABC123_456"),
            ("Simple Name.L", "Simple Name"),
            ("No_Numbers_Here.A1", "No_Numbers_Here"),
            ("ICON_74_2_Follower_Butler_Drones.1-03.L", "ICON_74_2"),
            ("ICON_74_2_Follower_Butler_Drones-22.L", "ICON_74_2")
        ]
        
        print("\n🧪 Testing getSimplifiedName:")
        for (input, expected) in testCases {
            let result = getSimplifiedName(input)
            let passed = result == expected
            let icon = passed ? "✅" : "❌"
            print("\(icon) Input: '\(input)'")
            print("   Expected: '\(expected)'")
            print("   Got:      '\(result)'")
            if !passed {
                print("   ⚠️ MISMATCH!")
            }
        }
    }
    
    // Parse timecode format (HH:MM:SS:FF) to total seconds
    private func parseTimecode(_ timecode: String) -> Int {
        let withoutFrames = String(timecode.dropLast(3))
        let parts = withoutFrames.components(separatedBy: ":")
        
        guard parts.count >= 3 else { return 0 }
        
        let hours = Int(parts[0]) ?? 0
        let minutes = Int(parts[1]) ?? 0
        let seconds = Int(parts[2]) ?? 0
        
        return hours * 3600 + minutes * 60 + seconds
    }
    
    // Calculate duration between two timecodes
    private func calculateDuration(from startTime: String, to endTime: String) -> Int {
        let startSeconds = parseTimecode(startTime)
        let endSeconds = parseTimecode(endTime)
        return endSeconds - startSeconds
    }
    
    // Parse old duration format (HH:MM:SS:FF) - kept for compatibility
    private func parseOldDuration(_ durationStr: String) -> Int {
        return parseTimecode(durationStr)
    }
    
    // Parse new duration format (MM:SS or HH:MM:SS)
    private func parseNewDuration(_ durationStr: String) -> Int {
        let parts = durationStr.components(separatedBy: ":")
        
        guard parts.count >= 2 else { return 0 }
        
        var hours = 0
        var minutes = 0
        var seconds = 0
        
        if parts.count == 2 {
            minutes = Int(parts[0]) ?? 0
            seconds = Int(parts[1]) ?? 0
        } else if parts.count >= 3 {
            hours = Int(parts[0]) ?? 0
            minutes = Int(parts[1]) ?? 0
            seconds = Int(parts[2]) ?? 0
        }
        
        return hours * 3600 + minutes * 60 + seconds
    }
    
    // Format duration as MM:SS
    private func formatDuration(_ totalSeconds: Int) -> String {
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // Check if a clip name is a fade event
    private func isFadeEvent(_ clipName: String) -> Bool {
        let trimmed = clipName.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.contains("(fade in)") || 
               trimmed.contains("(fade out)") || 
               trimmed.contains("(cross fade)")
    }
    
    // Aggregate events from parsed lines
    func aggregateEvents(from lines: [String]) -> [CueEvent] {
        var aggregatedEvents: [String: CueEvent] = [:]
        
        // First pass: parse all events into a temporary array
        var parsedEvents: [(clipName: String, simplifiedName: String, startTime: String, endTime: String, duration: Int, state: String, channel: Int, eventID: Int)] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Only process lines starting with "1"
            guard trimmedLine.hasPrefix("1") else { continue }
            
            let fields = trimmedLine.components(separatedBy: "\t")
            
            guard fields.count >= 6 else { continue }
            
            let clipName = fields[2].trimmingCharacters(in: .whitespaces)
            let simplifiedName = getSimplifiedName(clipName)
            let durationSeconds = parseOldDuration(fields[5])
            let state = fields.count > 6 ? fields[6].trimmingCharacters(in: .whitespaces) : ""
            
            // Debug logging
            if !isFadeEvent(clipName) {
                print("📋 [Parse] Original: '\(clipName)'")
                print("   Simplified: '\(simplifiedName)'")
            }
            
            // Skip muted events
            guard state != "Muted" else { continue }
            
            parsedEvents.append((
                clipName: clipName,
                simplifiedName: simplifiedName,
                startTime: fields[3],
                endTime: fields[4],
                duration: durationSeconds,
                state: state,
                channel: Int(fields[0]) ?? 0,
                eventID: Int(fields[1]) ?? 0
            ))
        }
        
        // Second pass: merge fade events with adjacent clips
        var i = 0
        while i < parsedEvents.count {
            let event = parsedEvents[i]
            
            // Skip fade events (they'll be handled by adjacent clips)
            if isFadeEvent(event.clipName) {
                i += 1
                continue
            }
            
            print("🔍 [Process] Event \(event.eventID): '\(event.simplifiedName)'")
            
            // Start with the current event's data
            var startTime = event.startTime
            var endTime = event.endTime
            var allNames = event.clipName + "\n"
            
            // Look backwards for fade in or cross fade
            if i > 0 {
                let prevEvent = parsedEvents[i - 1]
                if isFadeEvent(prevEvent.clipName) {
                    if prevEvent.clipName.lowercased().contains("fade in") {
                        print("   ⬅️ Found fade in before")
                        // Include fade in - use its start time
                        startTime = prevEvent.startTime
                        allNames = prevEvent.clipName + ", " + allNames
                    } else if prevEvent.clipName.lowercased().contains("cross fade") {
                        print("   ⬅️ Found cross fade before")
                        // Include cross fade - use its start time (this clip fades in during the cross fade)
                        startTime = prevEvent.startTime
                        allNames = prevEvent.clipName + ", " + allNames
                    }
                }
            }
            
            // Look forwards for fade out or cross fade
            if i < parsedEvents.count - 1 {
                let nextEvent = parsedEvents[i + 1]
                if isFadeEvent(nextEvent.clipName) {
                    if nextEvent.clipName.lowercased().contains("fade out") || nextEvent.clipName.lowercased().contains("cross fade") {
                        print("   ➡️ Found \(nextEvent.clipName) after")
                        // Include fade out/cross fade - use its end time
                        endTime = nextEvent.endTime
                        allNames += ", " + nextEvent.clipName + "\n"
                    }
                }
            }
            
            // Calculate duration from the final start and end times
            let totalDuration = calculateDuration(from: startTime, to: endTime)
            
            print("   📊 Start: \(startTime), End: \(endTime), Duration: \(formatDuration(totalDuration))")
            
            // Check if we already have this clip (by simplified name)
            if var existingEvent = aggregatedEvents[event.simplifiedName] {
                // Add to existing event
                print("   ♻️ Merging with existing entry for '\(event.simplifiedName)'")
                let currentDuration = parseNewDuration(existingEvent.duration)
                let newTotalDuration = currentDuration + totalDuration
                existingEvent.duration = formatDuration(newTotalDuration)
                existingEvent.allNames += allNames
                aggregatedEvents[event.simplifiedName] = existingEvent
                print("   ✅ New total duration: \(existingEvent.duration)")
            } else {
                // Create new event
                print("   ✨ Creating new entry for '\(event.simplifiedName)'")
                let cueEvent = CueEvent(
                    channel: event.channel,
                    eventID: event.eventID,
                    clipName: event.simplifiedName,
                    startTime: startTime,
                    endTime: endTime,
                    duration: formatDuration(totalDuration),
                    state: event.state,
                    allNames: allNames,
                    composer: ""
                )
                aggregatedEvents[event.simplifiedName] = cueEvent
            }
            
            i += 1
        }
        
        let results = Array(aggregatedEvents.values).sorted { $0.clipName < $1.clipName }
        
        print("\n📦 Final aggregated events: \(results.count) unique clips")
        for event in results {
            print("   - '\(event.clipName)' → \(event.duration)")
        }
        
        return results
    }
}
