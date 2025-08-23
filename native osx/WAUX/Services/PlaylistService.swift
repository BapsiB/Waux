import Foundation
import SQLite3
import Combine

class PlaylistService: ObservableObject {
    // MARK: - Constants
    private let tablePlaylists = "playlists"
    private let tablePlaylistTracks = "playlist_tracks"
    private let columnPlaylistId = "id"
    private let columnPlaylistName = "name"
    private let columnPlaylistTracksPlaylistId = "playlist_id"
    private let columnPlaylistTracksTrackPath = "track_path"
    private let columnPlaylistTracksSortOrder = "sort_order"
    
    // MARK: - Properties
    @Published var playlists: [Playlist] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var database: OpaquePointer?
    private var activeCollectionDefinition: CollectionDefinition?
    
    // MARK: - Thread Safety
    private let databaseQueue = DispatchQueue(label: "com.waux.playlist.database", qos: .userInitiated)
    
    // MARK: - Initialization
    init() {
        print("PlaylistService initialized")
    }
    
    // MARK: - Setup
    func setDatabase(_ db: OpaquePointer?, collectionDefinition: CollectionDefinition?) {
        self.database = db
        self.activeCollectionDefinition = collectionDefinition
    }
    
    // MARK: - Playlist Operations
    func loadPlaylists() async throws {
        guard let db = database,
              let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    let query = "SELECT * FROM \(self.tablePlaylists)"
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    var loadedPlaylists: [Playlist] = []
                    
                    while sqlite3_step(statement) == SQLITE_ROW {
                        let playlistId = String(cString: sqlite3_column_text(statement, 0))
                        let playlistName = String(cString: sqlite3_column_text(statement, 1))
                        
                        // Fetch tracks for this playlist
                        let trackPaths = try self.loadPlaylistTracksSync(playlistId: playlistId, db: db)
                        
                        let playlist = Playlist(
                            id: playlistId,
                            name: playlistName,
                            trackPaths: trackPaths
                        )
                        loadedPlaylists.append(playlist)
                    }
                    
                    let sortedPlaylists = loadedPlaylists.sorted { $0.name < $1.name }
                    
                    Task { @MainActor in
                        self.playlists = sortedPlaylists
                        self.isLoading = false
                    }
                    
                    print("Loaded \(loadedPlaylists.count) playlists")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func loadPlaylistTracksSync(playlistId: String, db: OpaquePointer) throws -> [String] {
        guard let activeCollection = activeCollectionDefinition else {
            return []
        }
        
        let query = """
            SELECT \(columnPlaylistTracksTrackPath) 
            FROM \(tablePlaylistTracks) 
            WHERE \(columnPlaylistTracksPlaylistId) = ? 
            ORDER BY \(columnPlaylistTracksSortOrder) ASC
        """
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw PlaylistError.queryFailed(message: errorMessage)
        }
        
        sqlite3_bind_text(statement, 1, (playlistId as NSString).utf8String, -1, nil)
        
        var trackPaths: [String] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let storedPath = String(cString: sqlite3_column_text(statement, 0))
            
            // Resolve relative paths for shared collections
            let resolvedPath: String
            if activeCollection.type == .shared,
               activeCollection.rootPath != nil,
               URL(string: storedPath)?.scheme == nil {
                resolvedPath = (activeCollection.rootPath! as NSString).appendingPathComponent(storedPath)
            } else {
                resolvedPath = storedPath
            }
            
            trackPaths.append(resolvedPath)
        }
        
        return trackPaths
    }
    
    private func loadPlaylistTracks(playlistId: String) async throws -> [String] {
        guard let db = database else { return [] }
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    let trackPaths = try self.loadPlaylistTracksSync(playlistId: playlistId, db: db)
                    continuation.resume(returning: trackPaths)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func createPlaylist(name: String) async throws -> Playlist {
        guard let db = database,
              let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw PlaylistError.invalidName
        }
        
        let newPlaylist = Playlist(name: trimmedName)
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    let query = "INSERT INTO \(self.tablePlaylists) (\(self.columnPlaylistId), \(self.columnPlaylistName)) VALUES (?, ?)"
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    sqlite3_bind_text(statement, 1, (newPlaylist.id as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 2, (newPlaylist.name as NSString).utf8String, -1, nil)
                    
                    let insertResult = sqlite3_step(statement)
                    if insertResult != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    Task { @MainActor in
                        self.playlists.append(newPlaylist)
                        self.playlists.sort { $0.name < $1.name }
                    }
                    
                    print("Created playlist: \(newPlaylist.name)")
                    continuation.resume(returning: newPlaylist)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func deletePlaylist(playlistId: String) async throws {
        guard let db = database,
              let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    let query = "DELETE FROM \(self.tablePlaylists) WHERE \(self.columnPlaylistId) = ?"
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    sqlite3_bind_text(statement, 1, (playlistId as NSString).utf8String, -1, nil)
                    
                    let deleteResult = sqlite3_step(statement)
                    if deleteResult != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    Task { @MainActor in
                        self.playlists.removeAll { $0.id == playlistId }
                    }
                    
                    print("Deleted playlist ID: \(playlistId)")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func addTrackToPlaylist(playlistId: String, absoluteTrackPath: String) async throws {
        guard let db = database,
              let activeCollection = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    var pathToAdd = absoluteTrackPath
                    
                    // Convert to relative path if it's a shared collection and the path is within its root
                    if activeCollection.type == .shared,
                       activeCollection.rootPath != nil,
                       URL(string: absoluteTrackPath)?.scheme == nil {
                        let absoluteURL = URL(fileURLWithPath: absoluteTrackPath)
                        let rootURL = URL(fileURLWithPath: activeCollection.rootPath!)
                        
                        if absoluteURL.path.hasPrefix(rootURL.path) {
                            pathToAdd = String(absoluteURL.path.dropFirst(rootURL.path.count + 1))
                        } else {
                            print("Warning: Track path '\(absoluteTrackPath)' is not within shared root '\(activeCollection.rootPath!)'. Storing absolute path in playlist.")
                            pathToAdd = absoluteTrackPath
                        }
                    }
                    
                    // Check if track already exists in this playlist
                    let checkQuery = """
                        SELECT COUNT(*) FROM \(self.tablePlaylistTracks) 
                        WHERE \(self.columnPlaylistTracksPlaylistId) = ? AND \(self.columnPlaylistTracksTrackPath) = ?
                    """
                    var checkStatement: OpaquePointer?
                    
                    let checkResult = sqlite3_prepare_v2(db, checkQuery, -1, &checkStatement, nil)
                    defer { sqlite3_finalize(checkStatement) }
                    
                    if checkResult == SQLITE_OK {
                        sqlite3_bind_text(checkStatement, 1, (playlistId as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(checkStatement, 2, (pathToAdd as NSString).utf8String, -1, nil)
                        
                        if sqlite3_step(checkStatement) == SQLITE_ROW {
                            let count = sqlite3_column_int(checkStatement, 0)
                            if count > 0 {
                                print("Track '\(pathToAdd)' already in playlist '\(playlistId)'")
                                continuation.resume()
                                return
                            }
                        }
                    }
                    
                    // Get sort order
                    let countQuery = "SELECT COUNT(*) FROM \(self.tablePlaylistTracks) WHERE \(self.columnPlaylistTracksPlaylistId) = ?"
                    var countStatement: OpaquePointer?
                    
                    let countResult = sqlite3_prepare_v2(db, countQuery, -1, &countStatement, nil)
                    defer { sqlite3_finalize(countStatement) }
                    
                    var sortOrder = 0
                    if countResult == SQLITE_OK {
                        sqlite3_bind_text(countStatement, 1, (playlistId as NSString).utf8String, -1, nil)
                        if sqlite3_step(countStatement) == SQLITE_ROW {
                            sortOrder = Int(sqlite3_column_int(countStatement, 0))
                        }
                    }
                    
                    // Insert track
                    let insertQuery = """
                        INSERT INTO \(self.tablePlaylistTracks) 
                        (\(self.columnPlaylistTracksPlaylistId), \(self.columnPlaylistTracksTrackPath), \(self.columnPlaylistTracksSortOrder)) 
                        VALUES (?, ?, ?)
                    """
                    var insertStatement: OpaquePointer?
                    
                    let insertResult = sqlite3_prepare_v2(db, insertQuery, -1, &insertStatement, nil)
                    defer { sqlite3_finalize(insertStatement) }
                    
                    if insertResult != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    sqlite3_bind_text(insertStatement, 1, (playlistId as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(insertStatement, 2, (pathToAdd as NSString).utf8String, -1, nil)
                    sqlite3_bind_int(insertStatement, 3, Int32(sortOrder))
                    
                    let stepResult = sqlite3_step(insertStatement)
                    if stepResult != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    // Update local playlist
                    let finalPathToAdd = pathToAdd
                    Task { @MainActor in
                        if let index = self.playlists.firstIndex(where: { $0.id == playlistId }) {
                            self.playlists[index].addTrack(finalPathToAdd)
                        }
                    }
                    
                    print("Added track '\(pathToAdd)' to playlist '\(playlistId)'")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func removeTrackFromPlaylist(playlistId: String, absoluteTrackPath: String) async throws {
        guard let db = database,
              let activeCollection = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    var pathToRemove = absoluteTrackPath
                    
                    // Convert to relative path if it's a shared collection
                    if activeCollection.type == .shared,
                       activeCollection.rootPath != nil,
                       URL(string: absoluteTrackPath)?.scheme == nil {
                        let absoluteURL = URL(fileURLWithPath: absoluteTrackPath)
                        let rootURL = URL(fileURLWithPath: activeCollection.rootPath!)
                        
                        if absoluteURL.path.hasPrefix(rootURL.path) {
                            pathToRemove = String(absoluteURL.path.dropFirst(rootURL.path.count + 1))
                        } else {
                            pathToRemove = absoluteTrackPath
                        }
                    }
                    
                    let query = """
                        DELETE FROM \(self.tablePlaylistTracks) 
                        WHERE \(self.columnPlaylistTracksPlaylistId) = ? AND \(self.columnPlaylistTracksTrackPath) = ?
                    """
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    sqlite3_bind_text(statement, 1, (playlistId as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 2, (pathToRemove as NSString).utf8String, -1, nil)
                    
                    let deleteResult = sqlite3_step(statement)
                    if deleteResult != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    // Update local playlist
                    let finalPathToRemove = pathToRemove
                    Task { @MainActor in
                        if let index = self.playlists.firstIndex(where: { $0.id == playlistId }) {
                            self.playlists[index].removeTrack(finalPathToRemove)
                        }
                    }
                    
                    print("Removed track '\(pathToRemove)' from playlist '\(playlistId)'")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func renamePlaylist(playlistId: String, newName: String) async throws {
        guard let db = database,
              let activeCollection = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw PlaylistError.invalidName
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    let query = "UPDATE \(self.tablePlaylists) SET \(self.columnPlaylistName) = ? WHERE \(self.columnPlaylistId) = ?"
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    sqlite3_bind_text(statement, 1, (trimmedName as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 2, (playlistId as NSString).utf8String, -1, nil)
                    
                    let updateResult = sqlite3_step(statement)
                    if updateResult != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: PlaylistError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    // Update local playlist
                    Task { @MainActor in
                        if let index = self.playlists.firstIndex(where: { $0.id == playlistId }) {
                            self.playlists[index].name = trimmedName
                            self.playlists.sort { $0.name < $1.name }
                        }
                    }
                    
                    print("Renamed playlist '\(playlistId)' to '\(trimmedName)'")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Errors
enum PlaylistError: LocalizedError {
    case noActiveCollection
    case queryFailed(message: String)
    case invalidName
    
    var errorDescription: String? {
        switch self {
        case .noActiveCollection:
            return "No active collection"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .invalidName:
            return "Invalid playlist name"
        }
    }
}
