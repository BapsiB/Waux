import Foundation
import SwiftUI

// MARK: - Table row (folders + tracks)

struct FolderHierarchyTableRow: Identifiable, Hashable {
    enum Kind: Hashable {
        case folder(FolderNode)
        case track(Track)
    }

    let kind: Kind
    let depth: Int

    var id: String {
        switch kind {
        case .folder(let node):
            return "folder:\(node.path)"
        case .track(let track):
            return "track:\(track.id ?? -1)"
        }
    }

    var folderNode: FolderNode? {
        if case .folder(let n) = kind { return n }
        return nil
    }

    var track: Track? {
        if case .track(let t) = kind { return t }
        return nil
    }

    // MARK: Sort keys (align with TrackTable / Track column values)

    var titleSort: String {
        switch kind {
        case .folder(let n): return n.displayName
        case .track(let t): return t.title
        }
    }

    var artistSort: String {
        switch kind {
        case .folder: return ""
        case .track(let t): return t.artist
        }
    }

    var albumSort: String {
        switch kind {
        case .folder: return ""
        case .track(let t): return t.album
        }
    }

    var formattedDurationSort: String {
        switch kind {
        case .folder: return ""
        case .track(let t): return t.formattedDuration
        }
    }

    var ratingSort: Int {
        switch kind {
        case .folder: return Int.min
        case .track(let t): return t.rating
        }
    }

    var dateAddedSortValue: Int {
        switch kind {
        case .folder: return Int.min
        case .track(let t): return t.dateAddedSortValue
        }
    }

    var composerSort: String {
        switch kind {
        case .folder: return ""
        case .track(let t): return t.composerText
        }
    }

    var generalTagsCount: Int {
        switch kind {
        case .folder: return 0
        case .track(let t): return t.generalTags.count
        }
    }

    var waveformPointCount: Int {
        switch kind {
        case .folder: return 0
        case .track(let t): return t.waveformPointCount
        }
    }
}

// MARK: - Compare rows (KeyPathComparator chain)

enum FolderHierarchyTableRowSorting {
    static func compare(
        _ a: FolderHierarchyTableRow,
        _ b: FolderHierarchyTableRow,
        sortOrder: [KeyPathComparator<FolderHierarchyTableRow>]
    ) -> Bool {
        for cmp in sortOrder {
            let r = cmp.compare(a, b)
            if r == .orderedAscending { return true }
            if r == .orderedDescending { return false }
        }
        return a.id < b.id
    }
}

// MARK: - Hierarchical sibling sort (preserves tree shape)

private enum SiblingMergeItem {
    case folder(FolderNode)
    case track(Track)
}

enum FolderHierarchySorter {
    /// Sorts direct children + tracks at each node, then recurses. Top-level roots are sorted among themselves.
    static func sortedTree(
        _ roots: [FolderNode],
        sortOrder: [KeyPathComparator<FolderHierarchyTableRow>]
    ) -> [FolderNode] {
        let inner = roots.map { sortNode($0, sortOrder: sortOrder) }
        return inner.sorted { a, b in
            FolderHierarchyTableRowSorting.compare(
                FolderHierarchyTableRow(kind: .folder(a), depth: 0),
                FolderHierarchyTableRow(kind: .folder(b), depth: 0),
                sortOrder: sortOrder
            )
        }
    }

    private static func sortNode(
        _ node: FolderNode,
        sortOrder: [KeyPathComparator<FolderHierarchyTableRow>]
    ) -> FolderNode {
        let sortedChildren = node.children.map { sortNode($0, sortOrder: sortOrder) }
        var merged: [SiblingMergeItem] = sortedChildren.map { .folder($0) } + node.tracks.map { .track($0) }
        merged.sort { x, y in
            let rowX = tableRow(from: x)
            let rowY = tableRow(from: y)
            return FolderHierarchyTableRowSorting.compare(rowX, rowY, sortOrder: sortOrder)
        }
        var newChildren: [FolderNode] = []
        var newTracks: [Track] = []
        for item in merged {
            switch item {
            case .folder(let n): newChildren.append(n)
            case .track(let t): newTracks.append(t)
            }
        }
        return FolderNode(
            name: node.name,
            path: node.path,
            isExpanded: node.isExpanded,
            children: newChildren,
            tracks: newTracks,
            level: node.level
        )
    }

    private static func tableRow(from item: SiblingMergeItem) -> FolderHierarchyTableRow {
        switch item {
        case .folder(let n): return FolderHierarchyTableRow(kind: .folder(n), depth: 0)
        case .track(let t): return FolderHierarchyTableRow(kind: .track(t), depth: 0)
        }
    }
}

// MARK: - Flatten visible rows (DFS, respects expansion + search)

enum FolderHierarchyFlatten {
    static func visibleRows(
        sortedRoots: [FolderNode],
        folderManager: FolderHierarchyManager,
        searchService: SearchService
    ) -> [FolderHierarchyTableRow] {
        var out: [FolderHierarchyTableRow] = []
        func visit(_ folders: [FolderNode], depth: Int) {
            for folder in folders {
                out.append(FolderHierarchyTableRow(kind: .folder(folder), depth: depth))
                guard folderManager.isExpanded(folder.path) else { continue }
                visit(folder.children, depth: depth + 1)
                for track in folder.tracks where searchService.trackMatchesSearch(track) {
                    out.append(FolderHierarchyTableRow(kind: .track(track), depth: depth + 1))
                }
            }
        }
        visit(sortedRoots, depth: 0)
        return out
    }

    /// Ordered row ids for shift–click range selection.
    static func orderedRowIds(from rows: [FolderHierarchyTableRow]) -> [String] {
        rows.map(\.id)
    }
}
