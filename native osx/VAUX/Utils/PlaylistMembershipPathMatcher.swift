import Foundation

/// Resolves a stored file path to `music.id` for playlist membership (migration and drag-drop).
struct PlaylistPathLookup {
    private let byExactPath: [String: Int]
    private let byNormalizedPath: [String: Int]
    private let byUniqueFilename: [String: Int]
    private let collectionRootPath: String?
    private let databasePath: String?

    init(idAndPaths: [(id: Int, path: String)], collectionRootPath: String?, databasePath: String?) {
        self.collectionRootPath = collectionRootPath
        self.databasePath = databasePath

        var byExact: [String: Int] = [:]
        byExact.reserveCapacity(idAndPaths.count * 2)
        var byNormalized: [String: Int] = [:]
        var filenameFirst: [String: Int] = [:]
        var ambiguousFilenames = Set<String>()

        for (id, path) in idAndPaths {
            byExact[path] = id
            let expanded = PlaylistMembershipPathMatcher.expandRelativePath(
                path,
                collectionRootPath: collectionRootPath,
                databasePath: databasePath
            )
            if expanded != path {
                byExact[expanded] = id
            }
            for key in PlaylistMembershipPathMatcher.canonicalKeys(for: path) {
                byNormalized[key] = id
            }
            if expanded != path {
                for key in PlaylistMembershipPathMatcher.canonicalKeys(for: expanded) {
                    byNormalized[key] = id
                }
            }
            let name = PlaylistMembershipPathMatcher.fileName(of: path)
            if let existing = filenameFirst[name], existing != id {
                ambiguousFilenames.insert(name)
            } else {
                filenameFirst[name] = id
            }
        }
        for name in ambiguousFilenames {
            filenameFirst.removeValue(forKey: name)
        }

        self.byExactPath = byExact
        self.byNormalizedPath = byNormalized
        self.byUniqueFilename = filenameFirst
    }

    func resolve(_ storedPath: String) -> Int? {
        if let id = byExactPath[storedPath] { return id }
        let expanded = PlaylistMembershipPathMatcher.expandRelativePath(
            storedPath,
            collectionRootPath: collectionRootPath,
            databasePath: databasePath
        )
        if expanded != storedPath, let id = byExactPath[expanded] { return id }
        for key in PlaylistMembershipPathMatcher.canonicalKeys(for: storedPath) {
            if let id = byNormalizedPath[key] { return id }
        }
        if expanded != storedPath {
            for key in PlaylistMembershipPathMatcher.canonicalKeys(for: expanded) {
                if let id = byNormalizedPath[key] { return id }
            }
        }
        let name = PlaylistMembershipPathMatcher.fileName(of: storedPath)
        if let id = byUniqueFilename[name] { return id }
        if expanded != storedPath {
            let expandedName = PlaylistMembershipPathMatcher.fileName(of: expanded)
            if let id = byUniqueFilename[expandedName] { return id }
        }
        return nil
    }
}

enum PlaylistMembershipPathMatcher {
    static func fileName(of path: String) -> String {
        if let slash = path.lastIndex(of: "/") {
            return String(path[path.index(after: slash)...])
        }
        return path
    }

    static func expandRelativePath(_ storedPath: String, collectionRootPath: String?, databasePath: String?) -> String {
        if storedPath.hasPrefix("/") { return storedPath }
        if let root = collectionRootPath, !root.isEmpty {
            return (root as NSString).appendingPathComponent(storedPath)
        }
        if let databasePath {
            let dbDir = URL(fileURLWithPath: databasePath).deletingLastPathComponent().path
            return (dbDir as NSString).appendingPathComponent(storedPath)
        }
        return storedPath
    }

    static func canonicalKeys(for path: String) -> [String] {
        var seen = Set<String>()
        var keys: [String] = []
        func add(_ value: String) {
            guard !value.isEmpty, seen.insert(value).inserted else { return }
            keys.append(value)
        }
        add(path)
        let standardized = (path as NSString).standardizingPath
        add(standardized)
        add(path.precomposedStringWithCanonicalMapping)
        add(standardized.precomposedStringWithCanonicalMapping)
        if standardized.hasPrefix("/private/") {
            add(String(standardized.dropFirst("/private".count)))
        } else if standardized.hasPrefix("/") {
            add("/private" + standardized)
        }
        return keys
    }
}
