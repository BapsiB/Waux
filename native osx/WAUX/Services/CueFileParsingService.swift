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
    
    // Simplified name processing similar to the C++ version
    func getSimplifiedName(_ clipName: String) -> String {
        var trimmedName = clipName
        
        // Step 1: Remove everything after the last parenthesis
        if let lastParenIndex = clipName.lastIndex(of: ")") {
            trimmedName = String(clipName[...lastParenIndex])
        }
        
        // Step 2: Remove the "_UPRIGHT_" prefix
        if trimmedName.hasPrefix("_UPRIGHT_") {
            trimmedName = String(trimmedName.dropFirst(9))
            
            // Step 3: Transform the name
            let parts = trimmedName.components(separatedBy: "_")
            if parts.count >= 3 {
                let part0 = parts[0]
                let part1 = parts[1]
                let part2 = parts[2]
                let prefix = "\(part0) \(part1)/\(part2)"
                
                // Extract the remaining part
                if let range = trimmedName.range(of: "_\(part2)") {
                    var rest = String(trimmedName[range.upperBound...])
                    if rest.hasPrefix("_") {
                        rest = String(rest.dropFirst())
                    }
                    
                    // Replace underscores with spaces
                    rest = rest.replacingOccurrences(of: "_", with: " ")
                    
                    // Remove everything within parentheses
                    rest = rest.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
                    
                    return rest.trimmingCharacters(in: .whitespaces) + " " + prefix
                }
            }
        }
        
        // Step 4: Trim everything after the last '-' if the name ends with ".L" or ".R"
        if trimmedName.hasSuffix(".L") || trimmedName.hasSuffix(".R") {
            if let lastDashIndex = trimmedName.lastIndex(of: "-") {
                trimmedName = String(trimmedName[..<lastDashIndex])
            }
        }
        
        return trimmedName
    }
    
    // Parse old duration format (HH:MM:SS:FF)
    private func parseOldDuration(_ durationStr: String) -> Int {
        let withoutFrames = String(durationStr.dropLast(3))
        let parts = withoutFrames.components(separatedBy: ":")
        
        guard parts.count >= 3 else { return 0 }
        
        let hours = Int(parts[0]) ?? 0
        let minutes = Int(parts[1]) ?? 0
        let seconds = Int(parts[2]) ?? 0
        
        return hours * 3600 + minutes * 60 + seconds
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
    
    // Aggregate events from parsed lines
    func aggregateEvents(from lines: [String]) -> [CueEvent] {
        var aggregatedEvents: [String: CueEvent] = [:]
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Only process lines starting with "1"
            guard trimmedLine.hasPrefix("1") else { continue }
            
            let fields = trimmedLine.components(separatedBy: "\t")
            
            guard fields.count >= 6 else { continue }
            
            let clipName = fields[2]
            let simplifiedName = getSimplifiedName(clipName)
            let durationSeconds = parseOldDuration(fields[5])
            let state = fields.count > 6 ? fields[6] : ""
            
            // Skip muted events
            guard state != "Muted" else { continue }
            
            if var existingEvent = aggregatedEvents[simplifiedName] {
                // Add to existing event
                let currentDuration = parseNewDuration(existingEvent.duration)
                let newTotalDuration = currentDuration + durationSeconds
                existingEvent.duration = formatDuration(newTotalDuration)
                existingEvent.allNames += ", \(clipName)\n"
                aggregatedEvents[simplifiedName] = existingEvent
            } else {
                // Create new event
                let event = CueEvent(
                    channel: Int(fields[0]) ?? 0,
                    eventID: Int(fields[1]) ?? 0,
                    clipName: simplifiedName,
                    startTime: fields[3],
                    endTime: fields[4],
                    duration: formatDuration(durationSeconds),
                    state: state,
                    allNames: clipName + "\n",
                    composer: ""
                )
                aggregatedEvents[simplifiedName] = event
            }
        }
        
        return Array(aggregatedEvents.values).sorted { $0.clipName < $1.clipName }
    }
}
