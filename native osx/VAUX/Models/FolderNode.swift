import Foundation
import SwiftUI

// MARK: - Folder Node
struct FolderNode: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let isExpanded: Bool
    let children: [FolderNode]
    let tracks: [Track]
    let level: Int
    
    init(id: UUID = UUID(), name: String, path: String, isExpanded: Bool = false, children: [FolderNode] = [], tracks: [Track] = [], level: Int = 0) {
        self.id = id
        self.name = name
        self.path = path
        self.isExpanded = isExpanded
        self.children = children
        self.tracks = tracks
        self.level = level
    }

    func replacingTrack(_ track: Track) -> FolderNode {
        FolderNode(
            id: id,
            name: name,
            path: path,
            isExpanded: isExpanded,
            children: children.map { $0.replacingTrack(track) },
            tracks: tracks.map { $0.id == track.id ? track : $0 },
            level: level
        )
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
        
        // Build nested folder structure
        // Start with folders that directly contain tracks, then add ancestor folders up to the rootPath
        let trackFolderPaths = Set(folderMap.keys)
        var allFolderPaths = trackFolderPaths

        // Ensure ancestor folders (that might not directly contain tracks) are included in the tree
        for folderPath in trackFolderPaths {
            var currentURL = URL(fileURLWithPath: folderPath)
            while true {
                let parentURL = currentURL.deletingLastPathComponent()
                let parentPath = parentURL.path

                // Stop if we reached the filesystem root or no progress
                if parentPath.isEmpty || parentPath == currentURL.path {
                    break
                }

                // If a rootPath is provided, stop ascension once we include it
                if let rootPath = rootPath {
                    // Do not go above the configured root folder
                    if !folderPath.hasPrefix(rootPath) {
                        // Track is outside of the specified root; don't constrain by rootPath in this case
                    } else if !parentPath.hasPrefix(rootPath) {
                        // Parent would be above root; ensure root is included and stop
                        allFolderPaths.insert(rootPath)
                        break
                    }
                    allFolderPaths.insert(parentPath)
                    if parentPath == rootPath { break }
                } else {
                    // No explicit root; include all ancestors until filesystem root
                    allFolderPaths.insert(parentPath)
                }

                currentURL = parentURL
            }
        }
        var folderNodes: [String: FolderNode] = [:]
        
        // Create all folder nodes first
        for folderPath in allFolderPaths {
            let pathComponents = folderPath.components(separatedBy: "/").filter { !$0.isEmpty }
            let folderName = pathComponents.last ?? "Unknown"
            
            // Calculate level relative to root path
            let level: Int
            if let rootPath = rootPath {
                let rootComponents = rootPath.components(separatedBy: "/").filter { !$0.isEmpty }
                let relativeLevel = pathComponents.count - rootComponents.count
                level = max(0, relativeLevel - 1) // Ensure level is never negative
            } else {
                // If no root path specified, find the common root among all paths
                let allPathComponents = allFolderPaths.map { $0.components(separatedBy: "/").filter { !$0.isEmpty } }
                if let commonPrefix = findCommonPrefix(allPathComponents) {
                    let relativeLevel = pathComponents.count - commonPrefix.count
                    level = max(0, relativeLevel - 1)
                } else {
                    level = pathComponents.count - 1 // Fallback to original behavior
                }
            }
            
            let folderNode = FolderNode(
                name: folderName,
                path: folderPath,
                isExpanded: false,
                children: [],
                tracks: folderMap[folderPath] ?? [],
                level: level
            )
            
            folderNodes[folderPath] = folderNode
        }
        
        // Build parent-child relationships using paths only, then assemble a deep tree.
        // Storing [FolderNode] snapshots and updating parents in arbitrary order left nested
        // folders with empty `children` (stale value types), so folder-only parents had no chevron.
        var rootFolderPaths: [String] = []
        var childrenMap: [String: [String]] = [:]
        
        for folderPath in allFolderPaths {
            let pathURL = URL(fileURLWithPath: folderPath)
            let parentPath = pathURL.deletingLastPathComponent().path
            
            // If parent exists in our folder map, this is a child folder
            if allFolderPaths.contains(parentPath) && parentPath != folderPath {
                if childrenMap[parentPath] == nil {
                    childrenMap[parentPath] = []
                }
                childrenMap[parentPath]?.append(folderPath)
            } else {
                rootFolderPaths.append(folderPath)
            }
        }
        
        let rootFolders = rootFolderPaths.map {
            buildFolderNode(at: $0, folderNodes: folderNodes, childrenMap: childrenMap)
        }
        
        return sortFolderHierarchy(rootFolders)
    }
    
    /// Recursively builds folder nodes so each level references up-to-date nested `children`.
    private static func buildFolderNode(
        at path: String,
        folderNodes: [String: FolderNode],
        childrenMap: [String: [String]]
    ) -> FolderNode {
        guard let base = folderNodes[path] else {
            fatalError("Missing folder node for path: \(path)")
        }
        let childPaths = childrenMap[path] ?? []
        let builtChildren = childPaths.map {
            buildFolderNode(at: $0, folderNodes: folderNodes, childrenMap: childrenMap)
        }
        return FolderNode(
            name: base.name,
            path: base.path,
            isExpanded: base.isExpanded,
            children: builtChildren,
            tracks: base.tracks,
            level: base.level
        )
    }
    
    // Helper function to find the common prefix among path components
    private static func findCommonPrefix(_ pathComponents: [[String]]) -> [String]? {
        guard !pathComponents.isEmpty else { return nil }
        
        let firstPath = pathComponents[0]
        var commonPrefix: [String] = []
        
        for (index, component) in firstPath.enumerated() {
            // Check if all paths have the same component at this index
            let allMatch = pathComponents.allSatisfy { path in
                index < path.count && path[index] == component
            }
            
            if allMatch {
                commonPrefix.append(component)
            } else {
                break
            }
        }
        
        return commonPrefix.isEmpty ? nil : commonPrefix
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
    
    func buildHierarchy(from tracks: [Track], rootPath: String? = nil) {
        rootFolders = FolderHierarchyBuilder.buildHierarchy(from: tracks, rootPath: rootPath)
    }

    func patchTrack(_ track: Track) {
        rootFolders = rootFolders.map { $0.replacingTrack(track) }
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
