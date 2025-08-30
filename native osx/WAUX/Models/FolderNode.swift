import Foundation
import SwiftUI

// MARK: - Folder Node
struct FolderNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isExpanded: Bool
    let children: [FolderNode]
    let tracks: [Track]
    let level: Int
    
    init(name: String, path: String, isExpanded: Bool = false, children: [FolderNode] = [], tracks: [Track] = [], level: Int = 0) {
        self.name = name
        self.path = path
        self.isExpanded = isExpanded
        self.children = children
        self.tracks = tracks
        self.level = level
    }
    
    var hasChildren: Bool {
        return !children.isEmpty || !tracks.isEmpty
    }
    
    var allTracks: [Track] {
        var allTracks = tracks
        for child in children {
            allTracks.append(contentsOf: child.allTracks)
        }
        return allTracks
    }
    
    var displayName: String {
        if name.isEmpty {
            return "Root"
        }
        return name
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Folder Hierarchy Builder
class FolderHierarchyBuilder {
    static func buildHierarchy(from tracks: [Track], rootPath: String? = nil) -> [FolderNode] {
        var folderMap: [String: [Track]] = [:]
        
        // Group tracks by their folder path
        for track in tracks {
            let trackURL = URL(fileURLWithPath: track.path)
            let folderPath = trackURL.deletingLastPathComponent().path
            
            if folderMap[folderPath] == nil {
                folderMap[folderPath] = []
            }
            folderMap[folderPath]?.append(track)
        }
        
        // Create a simple flat structure for now
        var rootFolders: [FolderNode] = []
        
        for (folderPath, tracksInFolder) in folderMap {
            let pathComponents = folderPath.components(separatedBy: "/").filter { !$0.isEmpty }
            let folderName = pathComponents.last ?? "Unknown"
            
            let folderNode = FolderNode(
                name: folderName,
                path: folderPath,
                isExpanded: false,
                children: [],
                tracks: tracksInFolder,
                level: 0
            )
            
            rootFolders.append(folderNode)
        }
        
        return sortFolderHierarchy(rootFolders)
    }
    

    
    private static func sortFolderHierarchy(_ folders: [FolderNode]) -> [FolderNode] {
        return folders.sorted { folder1, folder2 in
            // Sort folders first, then tracks
            if folder1.hasChildren && !folder2.hasChildren {
                return true
            } else if !folder1.hasChildren && folder2.hasChildren {
                return false
            } else {
                // Both are folders or both are leaf nodes, sort by name
                return folder1.name.localizedCaseInsensitiveCompare(folder2.name) == .orderedAscending
            }
        }.map { folder in
            // Recursively sort children
            let sortedChildren = sortFolderHierarchy(folder.children)
            let sortedTracks = folder.tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            
            return FolderNode(
                name: folder.name,
                path: folder.path,
                isExpanded: folder.isExpanded,
                children: sortedChildren,
                tracks: sortedTracks,
                level: folder.level
            )
        }
    }
    

}

// MARK: - Folder Hierarchy Manager
class FolderHierarchyManager: ObservableObject {
    @Published var rootFolders: [FolderNode] = []
    @Published var expandedFolders: Set<String> = []
    @Published var selectedFolders: Set<String> = []
    
    func buildHierarchy(from tracks: [Track]) {
        rootFolders = FolderHierarchyBuilder.buildHierarchy(from: tracks)
    }
    
    func toggleExpansion(for folderPath: String) {
        if expandedFolders.contains(folderPath) {
            expandedFolders.remove(folderPath)
        } else {
            expandedFolders.insert(folderPath)
        }
    }
    
    func isExpanded(_ folderPath: String) -> Bool {
        return expandedFolders.contains(folderPath)
    }
    
    func toggleSelection(for folderPath: String) {
        if selectedFolders.contains(folderPath) {
            selectedFolders.remove(folderPath)
        } else {
            selectedFolders.insert(folderPath)
        }
    }
    
    func isSelected(_ folderPath: String) -> Bool {
        return selectedFolders.contains(folderPath)
    }
    
    func getAllSelectedTracks() -> [Track] {
        var selectedTracks: [Track] = []
        
        func collectTracks(from folders: [FolderNode]) {
            for folder in folders {
                if selectedFolders.contains(folder.path) {
                    selectedTracks.append(contentsOf: folder.allTracks)
                }
                collectTracks(from: folder.children)
            }
        }
        
        collectTracks(from: rootFolders)
        return selectedTracks
    }
}
