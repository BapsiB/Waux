import Foundation
import AVFoundation
import SwiftUI

class AlbumArtworkService: ObservableObject {
    static let shared = AlbumArtworkService()
    
    // Cache for artwork to avoid re-extracting the same files
    private var artworkCache: [String: Data] = [:]
    private let cacheQueue = DispatchQueue(label: "artwork.cache", attributes: .concurrent)
    
    private init() {}
    
    /// Extracts album artwork from a track's file
    /// - Parameters:
    ///   - track: The track to extract artwork from
    ///   - collectionService: The collection service to resolve paths
    /// - Returns: Album artwork data if found, nil otherwise
    func extractAlbumArtwork(from track: Track, collectionService: CollectionService? = nil) async -> Data? {
        // For URL tracks, we can't extract artwork from the file
        guard !track.isUrl else {
            return nil
        }
        
        // Resolve the path to absolute if we have a collection service
        let filePath: String
        if let collectionService = collectionService {
            filePath = collectionService.resolveTrackPathForWaveform(track)
        } else {
            filePath = track.path
        }
        
        // Check cache first
        if let cachedArtwork = getCachedArtwork(for: filePath) {
            return cachedArtwork
        }
        
        // Extract from file
        let artworkData = await extractAlbumArtworkFromFile(filePath)
        
        // Cache the result
        if let artworkData = artworkData {
            cacheArtwork(artworkData, for: filePath)
        }
        
        return artworkData
    }
    
    /// Extracts album artwork from an audio file path
    /// - Parameter filePath: Path to the audio file
    /// - Returns: Album artwork data if found, nil otherwise
    private func extractAlbumArtworkFromFile(_ filePath: String) async -> Data? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let url = URL(fileURLWithPath: filePath)
                    let asset = AVURLAsset(url: url)
                    
                    // Try to extract artwork from common metadata
                    let artworkData = self.extractArtworkFromMetadata(asset)
                    
                    if let artworkData = artworkData {
                        continuation.resume(returning: artworkData)
                        return
                    }
                    
                    // If no artwork found in metadata, try to extract from ID3 tags
                    let id3ArtworkData = self.extractArtworkFromID3(asset)
                    
                    continuation.resume(returning: id3ArtworkData)
                    
                } catch {
                    print("[AlbumArtworkService] Error extracting artwork: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Extracts artwork from common metadata formats
    private func extractArtworkFromMetadata(_ asset: AVURLAsset) -> Data? {
        // Try iTunes metadata first
        for item in asset.metadata(forFormat: .iTunesMetadata) {
            if item.commonKey?.rawValue == "artwork" {
                if let dataValue = item.dataValue {
                    return dataValue
                }
            }
        }
        
        // Try common metadata
        for item in asset.commonMetadata {
            if item.commonKey?.rawValue == "artwork" {
                if let dataValue = item.dataValue {
                    return dataValue
                }
            }
        }
        
        return nil
    }
    
    /// Extracts artwork from ID3 tags
    private func extractArtworkFromID3(_ asset: AVURLAsset) -> Data? {
        for item in asset.metadata(forFormat: .id3Metadata) {
            // Look for APIC (Attached Picture) frames
            if let identifier = item.identifier?.rawValue.lowercased(),
               identifier.contains("apic") || identifier.contains("picture") {
                if let dataValue = item.dataValue {
                    return dataValue
                }
            }
        }
        
        return nil
    }
    
    /// Creates a default album artwork image for tracks without artwork
    /// - Parameters:
    ///   - title: Track title
    ///   - artist: Track artist
    ///   - size: Size of the generated image
    /// - Returns: Default artwork image
    func createDefaultArtwork(title: String, artist: String, size: CGSize = CGSize(width: 200, height: 200)) -> NSImage {
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Create gradient background
        let gradient = NSGradient(colors: [
            NSColor.systemBlue.withAlphaComponent(0.8),
            NSColor.systemPurple.withAlphaComponent(0.8)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        
        // Add music note icon
        let iconSize: CGFloat = size.width * 0.4
        let iconRect = NSRect(
            x: (size.width - iconSize) / 2,
            y: (size.height - iconSize) / 2 + 10,
            width: iconSize,
            height: iconSize
        )
        
        if let musicIcon = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) {
            musicIcon.draw(in: iconRect)
        }
        
        // Add text
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size.width * 0.08, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        
        let titleString = NSAttributedString(string: title, attributes: textAttributes)
        let artistString = NSAttributedString(string: artist, attributes: textAttributes)
        
        let titleSize = titleString.size()
        let artistSize = artistString.size()
        
        // Draw title
        let titleRect = NSRect(
            x: (size.width - titleSize.width) / 2,
            y: iconRect.minY - titleSize.height - 10,
            width: titleSize.width,
            height: titleSize.height
        )
        titleString.draw(in: titleRect)
        
        // Draw artist
        let artistRect = NSRect(
            x: (size.width - artistSize.width) / 2,
            y: titleRect.minY - artistSize.height - 5,
            width: artistSize.width,
            height: artistSize.height
        )
        artistString.draw(in: artistRect)
        
        image.unlockFocus()
        
        return image
    }
    
    /// Converts NSImage to Data
    /// - Parameter image: The image to convert
    /// - Returns: Image data in PNG format
    func imageToData(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmapImage.representation(using: .png, properties: [:])
    }
    
    // MARK: - Caching
    
    private func getCachedArtwork(for path: String) -> Data? {
        return cacheQueue.sync {
            return artworkCache[path]
        }
    }
    
    private func cacheArtwork(_ artwork: Data, for path: String) {
        cacheQueue.async(flags: .barrier) {
            self.artworkCache[path] = artwork
        }
    }
    
    /// Clears the artwork cache
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.artworkCache.removeAll()
        }
    }
    
    /// Removes a specific track's artwork from cache
    func removeFromCache(path: String) {
        cacheQueue.async(flags: .barrier) {
            self.artworkCache.removeValue(forKey: path)
        }
    }
}
