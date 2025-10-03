//
//  ComposerFetchingService.swift
//  WAUX
//
//  Created by AI Assistant on 03/10/2025.
//

import Foundation
import AVFoundation

class ComposerFetchingService {
    private var lastSearchDirectory: URL?
    
    // Save last directory to UserDefaults
    private func saveLastDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: "CueFileHelper_LastSearchDirectory")
    }
    
    // Load last directory from UserDefaults
    private func loadLastDirectory() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: "CueFileHelper_LastSearchDirectory") else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
    
    // Extract composer from audio file metadata
    private func extractComposer(from fileURL: URL) -> String? {
        let asset = AVAsset(url: fileURL)
        
        // Try to get composer from metadata
        for item in asset.commonMetadata {
            if item.commonKey == .commonKeyCreator || item.identifier?.rawValue.contains("composer") == true {
                if let stringValue = item.stringValue {
                    return stringValue
                }
            }
        }
        
        // Also check ID3 metadata for MP3 files
        let id3Metadata = asset.metadata(forFormat: .id3Metadata)
        for item in id3Metadata {
            if item.identifier?.rawValue.contains("TCOM") == true || 
               item.commonKey == .commonKeyCreator {
                if let stringValue = item.stringValue {
                    return stringValue
                }
            }
        }
        
        return nil
    }
    
    // Find audio files matching the clip name in a directory
    private func findMatchingFiles(in directory: URL, matching clipName: String) -> [URL] {
        let fileManager = FileManager.default
        var matchingFiles: [URL] = []
        
        // Prepare clip name for comparison
        var searchName = clipName
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        // Remove .L or .R suffix if present
        if searchName.hasSuffix(".L") || searchName.hasSuffix(".R") {
            if let lastDashIndex = searchName.lastIndex(of: "-") {
                searchName = String(searchName[..<lastDashIndex])
            }
        }
        
        // Get all files in directory and subdirectories
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        let audioExtensions = ["mp3", "wav", "aiff", "aif", "m4a", "flac"]
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            let fileExtension = fileURL.pathExtension.lowercased()
            guard audioExtensions.contains(fileExtension) else { continue }
            
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            
            // Check if filename contains the search name (case insensitive)
            if searchName.range(of: fileName, options: .caseInsensitive) != nil {
                matchingFiles.append(fileURL)
            }
        }
        
        // If no matches with underscore, try replacing underscores with spaces
        if matchingFiles.isEmpty {
            let searchNameWithSpaces = searchName.replacingOccurrences(of: "_", with: " ")
            
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            
            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      resourceValues.isRegularFile == true else {
                    continue
                }
                
                let fileExtension = fileURL.pathExtension.lowercased()
                guard audioExtensions.contains(fileExtension) else { continue }
                
                let fileName = fileURL.deletingPathExtension().lastPathComponent
                
                if searchNameWithSpaces.range(of: fileName, options: .caseInsensitive) != nil {
                    matchingFiles.append(fileURL)
                }
            }
        }
        
        return matchingFiles
    }
    
    // Get composer for a clip name from a directory
    func getComposer(for clipName: String, in directory: URL?) -> String {
        var searchDirectory = directory ?? lastSearchDirectory
        
        // If no directory is set, prompt user
        if searchDirectory == nil {
            searchDirectory = loadLastDirectory()
        }
        
        guard let searchDirectory = searchDirectory else {
            return ""
        }
        
        lastSearchDirectory = searchDirectory
        saveLastDirectory(searchDirectory)
        
        // Extract just the first name if there are multiple
        let nameToFind = clipName.components(separatedBy: ",").first ?? clipName
        
        // Find matching files
        let matchingFiles = findMatchingFiles(in: searchDirectory, matching: nameToFind)
        
        // Try to extract composer from the first matching file
        for file in matchingFiles {
            if let composer = extractComposer(from: file), !composer.isEmpty {
                return composer
            }
        }
        
        return ""
    }
    
    // Batch process events to fetch composers
    func fetchComposers(for events: [CueEvent], in directory: URL?, progressHandler: @escaping (Int, Int) -> Void) -> [CueEvent] {
        var updatedEvents = events
        
        for (index, var event) in updatedEvents.enumerated() {
            event.composer = getComposer(for: event.allNames, in: directory)
            updatedEvents[index] = event
            progressHandler(index + 1, updatedEvents.count)
        }
        
        return updatedEvents
    }
}
