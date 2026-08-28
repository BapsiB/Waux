import Foundation
import SQLite3
import Combine
import SwiftUI

class PlaylistService: ObservableObject {
    // MARK: - Constants
    private let tablePlaylists = "playlists"
    private let tablePlaylistTracks = "playlist_tracks"
    private let tablePlaylistFolders = "playlist_folders"
    
    // Column names - playlists table
    private let columnPlaylistsId = "id"
    private let columnPlaylistsName = "name"
    private let columnPlaylistsFolderId = "folder_id"
    
    // Column names - playlist_tracks table
    private let columnPlaylistTracksPlaylistId = "playlist_id"
    private let columnPlaylistTracksTrackId = "track_id"
    private let columnPlaylistTracksSortOrder = "sort_order"
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    // Column names - playlist_folders table
    private let columnPlaylistFoldersId = "id"
    private let columnPlaylistFoldersName = "name"
    private let columnPlaylistFoldersParentId = "parent_folder_id"
    private let columnPlaylistFoldersDateCreated = "date_created"
    private let columnPlaylistFoldersDateModified = "date_modified"
    
    // MARK: - Properties
    @Published var playlists: [Playlist] = []
    @Published var folders: [PlaylistFolder] = []
    @Published var folderExpandedStates: [String: Bool] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var snackbarMessage: String?
    
    private var database: OpaquePointer?
    private var activeCollectionDefinition: CollectionDefinition?
    private var collectionService: CollectionService?
    
    // MARK: - Thread Safety
    // Use the same database queue as CollectionService to prevent multi-threaded access
    private var databaseQueue: DispatchQueue?
    
    // MARK: - Initialization
    init() {
        print("PlaylistService initialized")
    }
    
    deinit {
        closeCollection()
    }
    
    // MARK: - Database Management
    func setDatabase(_ db: OpaquePointer?, collectionDefinition: CollectionDefinition, databaseQueue: DispatchQueue, collectionService: CollectionService) {
        self.database = db
        self.activeCollectionDefinition = collectionDefinition
        self.databaseQueue = databaseQueue
        self.collectionService = collectionService
        print("PlaylistService database set with queue: \(databaseQueue)")
        
        // Run database migration for folder support - ensure it's properly queued
        Task {
            do {
                // Wait a bit to ensure the database queue is fully established
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                print("🔧 Starting database migration for folder support...")
                try await migrateDatabaseForFolders()
                print("✅ Database migration completed successfully")
            } catch {
                print("⚠️ Failed to migrate database for folder support: \(error)")
                await MainActor.run {
                    self.errorMessage = "Failed to migrate database for folder support: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func closeCollection() {
        database = nil
        activeCollectionDefinition = nil
        databaseQueue = nil
        collectionService = nil
        
        DispatchQueue.main.async {
            self.playlists = []
            self.folders = []
            self.folderExpandedStates = [:]
        }
    }
    
    // MARK: - Database Migration
    func migrateDatabaseForFolders() async throws {
        guard let _ = database else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withDatabaseQueue {
            guard let db = self.database else {
                throw PlaylistError.noActiveCollection
            }
            // Create playlist_folders table if it doesn't exist
            let createFoldersTableSQL = """
            CREATE TABLE IF NOT EXISTS \(self.tablePlaylistFolders) (
                \(self.columnPlaylistFoldersId) TEXT PRIMARY KEY,
                \(self.columnPlaylistFoldersName) TEXT NOT NULL,
                \(self.columnPlaylistFoldersParentId) TEXT,
                \(self.columnPlaylistFoldersDateCreated) TEXT NOT NULL,
                \(self.columnPlaylistFoldersDateModified) TEXT NOT NULL,
                FOREIGN KEY (\(self.columnPlaylistFoldersParentId)) REFERENCES \(self.tablePlaylistFolders)(\(self.columnPlaylistFoldersId)) ON DELETE CASCADE
            )
            """
            
            if sqlite3_exec(db, createFoldersTableSQL, nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: "Failed to create playlist_folders table: \(errorMessage)")
            }
            
            // Check if folder_id column exists in playlists table
            let checkColumnSQL = "PRAGMA table_info(\(self.tablePlaylists))"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, checkColumnSQL, -1, &statement, nil) == SQLITE_OK {
                defer { sqlite3_finalize(statement) }
                
                var hasFolderIdColumn = false
                while sqlite3_step(statement) == SQLITE_ROW {
                    let columnName = String(cString: sqlite3_column_text(statement, 1))
                    if columnName == self.columnPlaylistsFolderId {
                        hasFolderIdColumn = true
                        break
                    }
                }
                
                if !hasFolderIdColumn {
                    print("🔧 Adding folder_id column to playlists table...")
                    let addColumnSQL = "ALTER TABLE \(self.tablePlaylists) ADD COLUMN \(self.columnPlaylistsFolderId) TEXT"
                    
                    if sqlite3_exec(db, addColumnSQL, nil, nil, nil) != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        throw PlaylistError.queryFailed(message: "Failed to add folder_id column: \(errorMessage)")
                    }
                    
                    // Add foreign key constraint (note: SQLite doesn't support adding FK constraints to existing tables,
                    // but we can add the column and the constraint will be enforced for new data)
                    print("✅ Successfully added folder_id column to playlists table")
                }
            }
            
            // Create indexes for performance optimization
            let createIndexes = [
                "CREATE INDEX IF NOT EXISTS idx_playlists_folder_id ON \(self.tablePlaylists)(\(self.columnPlaylistsFolderId))",
                "CREATE INDEX IF NOT EXISTS idx_playlist_folders_parent_id ON \(self.tablePlaylistFolders)(\(self.columnPlaylistFoldersParentId))",
                "CREATE INDEX IF NOT EXISTS idx_playlist_folders_name ON \(self.tablePlaylistFolders)(\(self.columnPlaylistFoldersName))"
            ]
            
            for indexSQL in createIndexes {
                if sqlite3_exec(db, indexSQL, nil, nil, nil) != SQLITE_OK {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    print("⚠️ Failed to create index: \(errorMessage)")
                    // Don't throw error as indexes are for performance optimization
                }
            }
            
            print("✅ Database migration for folder support completed successfully")
        }
    }
    
    // MARK: - Helper Methods
    private func withDatabaseQueue<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        guard let queue = databaseQueue else {
            throw PlaylistError.noActiveCollection
        }
        
        // bridge the callback-based queue.async to async/await
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                // Block the serial queue while the async operation runs
                // This ensures true serialization of database access
                let semaphore = DispatchSemaphore(value: 0)
                
                Task {
                    do {
                        let result = try await operation()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    semaphore.signal()
                }
                
                semaphore.wait()
            }
        }
    }
    
    // Helper method to get database connection safely within queue context
    private func getDatabaseConnection() throws -> OpaquePointer {
        guard let db = database else {
            throw PlaylistError.noActiveCollection
        }
        print("🔍 getDatabaseConnection called on thread: \(Thread.current), db: \(db)")
        return db
    }
    
    // MARK: - Playlist Operations
    func loadPlaylists() async throws {
        guard let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        return try await withDatabaseQueue {
            guard let db = self.database else {
                throw PlaylistError.noActiveCollection
            }
            let query = """
                SELECT \(self.columnPlaylistsId), \(self.columnPlaylistsName), \(self.columnPlaylistsFolderId) 
                FROM \(self.tablePlaylists)
            """
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            var loadedPlaylists: [Playlist] = []
            let tracksByPlaylist = try self.loadAllPlaylistTrackIdsSync(db: db)

            while sqlite3_step(statement) == SQLITE_ROW {
                let playlistId = String(cString: sqlite3_column_text(statement, 0))
                let playlistName = String(cString: sqlite3_column_text(statement, 1))
                
                let folderId: String?
                if let folderPtr = sqlite3_column_text(statement, 2) {
                    folderId = String(cString: folderPtr)
                } else {
                    folderId = nil
                }
                
                let playlist = Playlist(
                    id: playlistId,
                    name: playlistName,
                    trackIds: tracksByPlaylist[playlistId] ?? [],
                    folderId: folderId
                )
                loadedPlaylists.append(playlist)
            }
            
            let sortedPlaylists = loadedPlaylists.sorted { $0.name < $1.name }
            
            await MainActor.run {
                self.playlists = sortedPlaylists
                self.isLoading = false
            }
            
            print("Loaded \(loadedPlaylists.count) playlists")
            return ()
        }
    }
    
    private func loadAllPlaylistTrackIdsSync(db: OpaquePointer) throws -> [String: [Int]] {
        let query = """
            SELECT \(columnPlaylistTracksPlaylistId), \(columnPlaylistTracksTrackId)
            FROM \(tablePlaylistTracks)
            ORDER BY \(columnPlaylistTracksPlaylistId), \(columnPlaylistTracksSortOrder) ASC
        """
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }

        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw PlaylistError.queryFailed(message: errorMessage)
        }

        var tracksByPlaylist: [String: [Int]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let playlistId = String(cString: sqlite3_column_text(statement, 0))
            let trackId = Int(sqlite3_column_int64(statement, 1))
            tracksByPlaylist[playlistId, default: []].append(trackId)
        }
        return tracksByPlaylist
    }

    /// Ordered `music.id` values for a playlist.
    private func loadPlaylistTrackIdsSync(playlistId: String, db: OpaquePointer) throws -> [Int] {
        let query = """
            SELECT \(columnPlaylistTracksTrackId)
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

        sqlite3_bind_text(statement, 1, playlistId, -1, SQLITE_TRANSIENT)

        var ids: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.append(Int(sqlite3_column_int64(statement, 0)))
        }
        return ids
    }

    /// Playlists that contain this track.
    func playlistsContaining(trackId: Int) -> [Playlist] {
        playlists.filter { $0.trackIds.contains(trackId) }.sorted { $0.name < $1.name }
    }

    /// Playlists that contain every listed track. Empty `ids` yields no playlists.
    func playlistsContainingAllTracks(trackIds: [Int]) -> [Playlist] {
        guard !trackIds.isEmpty else { return [] }
        return playlists.filter { pl in
            trackIds.allSatisfy { pl.trackIds.contains($0) }
        }.sorted { $0.name < $1.name }
    }

    /// Drop deleted collection tracks from in-memory playlists. SQLite CASCADE already removed the rows.
    @MainActor
    func removeDeletedTrackIdsFromPlaylists(_ trackIds: [Int]) {
        guard !trackIds.isEmpty else { return }
        let idSet = Set(trackIds)
        for index in playlists.indices {
            let before = playlists[index].trackIds.count
            playlists[index].trackIds.removeAll { idSet.contains($0) }
            if playlists[index].trackIds.count != before {
                playlists[index].dateModified = Date()
            }
        }
    }

    func createPlaylist(name: String, folderId: String? = nil) async throws -> Playlist {
        guard let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw PlaylistError.invalidName
        }
        
        // Validate folder exists if specified
        if let targetFolderId = folderId {
            let folderExists = try await self.folderExists(folderId: targetFolderId)
            if !folderExists {
                throw PlaylistError.folderNotFound
            }
        }
        
        let newPlaylist = Playlist(name: trimmedName, folderId: folderId)
        
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            let query = "INSERT INTO \(self.tablePlaylists) (\(self.columnPlaylistsId), \(self.columnPlaylistsName), \(self.columnPlaylistsFolderId)) VALUES (?, ?, ?)"
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(statement, 1, (newPlaylist.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (newPlaylist.name as NSString).utf8String, -1, nil)
            
            if let targetFolderId = folderId {
                sqlite3_bind_text(statement, 3, (targetFolderId as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            
            let insertResult = sqlite3_step(statement)
            if insertResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            await MainActor.run {
                self.playlists.append(newPlaylist)
                self.playlists.sort { $0.name < $1.name }
            }
            
            print("Created playlist: \(newPlaylist.name) in folder: \(folderId ?? "root")")
            return newPlaylist
        }
    }
    
    func deletePlaylist(playlistId: String) async throws {
        guard let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            let query = "DELETE FROM \(self.tablePlaylists) WHERE \(self.columnPlaylistsId) = ?"
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(statement, 1, (playlistId as NSString).utf8String, -1, nil)
            
            let deleteResult = sqlite3_step(statement)
            if deleteResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            await MainActor.run {
                self.playlists.removeAll { $0.id == playlistId }
            }
            
            print("Deleted playlist ID: \(playlistId)")
            return ()
        }
    }
    
    func addTrackToPlaylist(playlistId: String, trackId: Int) async throws -> Bool {
        let result = try await addTracksToPlaylist(playlistId: playlistId, trackIds: [trackId])
        return result.newTracks > 0
    }

    /// Resolves each path to `music.id` at the boundary (drag-drop). Unknown files are skipped.
    func addTracksToPlaylist(playlistId: String, trackPaths: [String]) async throws -> (newTracks: Int, duplicateTracks: Int) {
        guard let collectionService else {
            throw PlaylistError.noActiveCollection
        }
        let lookup = collectionService.makePlaylistPathLookup()
        var trackIds: [Int] = []
        trackIds.reserveCapacity(trackPaths.count)
        for path in trackPaths {
            if let id = lookup.resolve(path) {
                trackIds.append(id)
            } else {
                print("Skipping playlist add for path not in collection: \(path)")
            }
        }
        return try await addTracksToPlaylist(playlistId: playlistId, trackIds: trackIds)
    }

    func addTracksToPlaylist(playlistId: String, trackIds: [Int]) async throws -> (newTracks: Int, duplicateTracks: Int) {
        guard activeCollectionDefinition != nil else {
            throw PlaylistError.noActiveCollection
        }
        if trackIds.isEmpty {
            return (0, 0)
        }

        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            var newCount = 0
            var duplicateCount = 0

            let countQuery = "SELECT COUNT(*) FROM \(self.tablePlaylistTracks) WHERE \(self.columnPlaylistTracksPlaylistId) = ?"
            var countStatement: OpaquePointer?
            let countPrepare = sqlite3_prepare_v2(db, countQuery, -1, &countStatement, nil)
            defer { sqlite3_finalize(countStatement) }
            var sortOrder = 0
            if countPrepare == SQLITE_OK {
                sqlite3_bind_text(countStatement, 1, playlistId, -1, self.SQLITE_TRANSIENT)
                if sqlite3_step(countStatement) == SQLITE_ROW {
                    sortOrder = Int(sqlite3_column_int(countStatement, 0))
                }
            }

            let existsQuery = """
                SELECT 1 FROM \(self.tablePlaylistTracks)
                WHERE \(self.columnPlaylistTracksPlaylistId) = ? AND \(self.columnPlaylistTracksTrackId) = ?
            """
            var existsStatement: OpaquePointer?
            guard sqlite3_prepare_v2(db, existsQuery, -1, &existsStatement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            defer { sqlite3_finalize(existsStatement) }

            let musicExistsQuery = "SELECT 1 FROM music WHERE id = ?"
            var musicExistsStatement: OpaquePointer?
            guard sqlite3_prepare_v2(db, musicExistsQuery, -1, &musicExistsStatement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            defer { sqlite3_finalize(musicExistsStatement) }

            let insertQuery = """
                INSERT INTO \(self.tablePlaylistTracks)
                (\(self.columnPlaylistTracksPlaylistId), \(self.columnPlaylistTracksTrackId), \(self.columnPlaylistTracksSortOrder))
                VALUES (?, ?, ?)
            """
            var insertStatement: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertQuery, -1, &insertStatement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            defer { sqlite3_finalize(insertStatement) }

            var addedIds: [Int] = []
            var seenThisBatch = Set<Int>()

            for trackId in trackIds {
                if seenThisBatch.contains(trackId) {
                    duplicateCount += 1
                    continue
                }
                seenThisBatch.insert(trackId)

                sqlite3_reset(musicExistsStatement)
                sqlite3_clear_bindings(musicExistsStatement)
                sqlite3_bind_int64(musicExistsStatement, 1, Int64(trackId))
                if sqlite3_step(musicExistsStatement) != SQLITE_ROW {
                    print("Skipping playlist add for unknown music.id \(trackId)")
                    continue
                }

                sqlite3_reset(existsStatement)
                sqlite3_clear_bindings(existsStatement)
                sqlite3_bind_text(existsStatement, 1, playlistId, -1, self.SQLITE_TRANSIENT)
                sqlite3_bind_int64(existsStatement, 2, Int64(trackId))
                if sqlite3_step(existsStatement) == SQLITE_ROW {
                    duplicateCount += 1
                    continue
                }

                sqlite3_reset(insertStatement)
                sqlite3_clear_bindings(insertStatement)
                sqlite3_bind_text(insertStatement, 1, playlistId, -1, self.SQLITE_TRANSIENT)
                sqlite3_bind_int64(insertStatement, 2, Int64(trackId))
                sqlite3_bind_int(insertStatement, 3, Int32(sortOrder))
                let stepResult = sqlite3_step(insertStatement)
                if stepResult != SQLITE_DONE {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw PlaylistError.queryFailed(message: errorMessage)
                }
                sortOrder += 1
                newCount += 1
                addedIds.append(trackId)
            }

            await MainActor.run {
                if let index = self.playlists.firstIndex(where: { $0.id == playlistId }) {
                    for id in addedIds {
                        self.playlists[index].addTrack(id)
                    }
                }
            }

            print("Added \(newCount) tracks to playlist '\(playlistId)' (\(duplicateCount) duplicates)")
            return (newTracks: newCount, duplicateTracks: duplicateCount)
        }
    }

    func removeTrackFromPlaylist(playlistId: String, trackId: Int) async throws {
        guard activeCollectionDefinition != nil else {
            throw PlaylistError.noActiveCollection
        }

        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            let query = """
                DELETE FROM \(self.tablePlaylistTracks)
                WHERE \(self.columnPlaylistTracksPlaylistId) = ? AND \(self.columnPlaylistTracksTrackId) = ?
            """
            var statement: OpaquePointer?
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }

            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }

            sqlite3_bind_text(statement, 1, playlistId, -1, self.SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 2, Int64(trackId))

            let deleteResult = sqlite3_step(statement)
            if deleteResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }

            await MainActor.run {
                self.syncInMemoryPlaylistRemove(playlistId: playlistId, trackId: trackId)
            }

            print("Removed track id \(trackId) from playlist '\(playlistId)'")
            return ()
        }
    }

    private func syncInMemoryPlaylistRemove(playlistId: String, trackId: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].removeTrack(trackId)
    }
    
    func renamePlaylist(playlistId: String, newName: String) async throws {
        guard let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw PlaylistError.invalidName
        }
        
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            let query = "UPDATE \(self.tablePlaylists) SET \(self.columnPlaylistsName) = ? WHERE \(self.columnPlaylistsId) = ?"
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(statement, 1, (trimmedName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (playlistId as NSString).utf8String, -1, nil)
            
            let updateResult = sqlite3_step(statement)
            if updateResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            // Update local playlist
            await MainActor.run {
                if let index = self.playlists.firstIndex(where: { $0.id == playlistId }) {
                    self.playlists[index].name = trimmedName
                    self.playlists.sort { $0.name < $1.name }
                }
            }
            
            print("Renamed playlist '\(playlistId)' to '\(trimmedName)'")
            return ()
        }
    }
    
    func duplicatePlaylist(playlistId: String, newName: String) async throws -> Playlist {
        guard let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw PlaylistError.invalidName
        }
        
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            // First, get the original playlist's folder ID
            let originalPlaylist = self.playlists.first { $0.id == playlistId }
            let originalFolderId = originalPlaylist?.folderId
            
            // Create the new playlist with the same folder ID
            let newPlaylistId = UUID().uuidString
            let insertQuery = "INSERT INTO \(self.tablePlaylists) (\(self.columnPlaylistsId), \(self.columnPlaylistsName), \(self.columnPlaylistsFolderId)) VALUES (?, ?, ?)"
            var insertStatement: OpaquePointer?
            
            let insertResult = sqlite3_prepare_v2(db, insertQuery, -1, &insertStatement, nil)
            defer { sqlite3_finalize(insertStatement) }
            
            if insertResult != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(insertStatement, 1, (newPlaylistId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (trimmedName as NSString).utf8String, -1, nil)
            
            if let folderId = originalFolderId {
                sqlite3_bind_text(insertStatement, 3, (folderId as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(insertStatement, 3)
            }
            
            let stepResult = sqlite3_step(insertStatement)
            if stepResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            let copyQuery = """
                INSERT INTO \(self.tablePlaylistTracks)
                (\(self.columnPlaylistTracksPlaylistId), \(self.columnPlaylistTracksTrackId), \(self.columnPlaylistTracksSortOrder))
                SELECT ?, \(self.columnPlaylistTracksTrackId), \(self.columnPlaylistTracksSortOrder)
                FROM \(self.tablePlaylistTracks)
                WHERE \(self.columnPlaylistTracksPlaylistId) = ?
            """
            var copyStatement: OpaquePointer?
            let copyResult = sqlite3_prepare_v2(db, copyQuery, -1, &copyStatement, nil)
            defer { sqlite3_finalize(copyStatement) }

            if copyResult != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }

            sqlite3_bind_text(copyStatement, 1, newPlaylistId, -1, self.SQLITE_TRANSIENT)
            sqlite3_bind_text(copyStatement, 2, playlistId, -1, self.SQLITE_TRANSIENT)

            let copyStepResult = sqlite3_step(copyStatement)
            if copyStepResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }

            let trackIds = try self.loadPlaylistTrackIdsSync(playlistId: newPlaylistId, db: db)
            let newPlaylist = Playlist(id: newPlaylistId, name: trimmedName, trackIds: trackIds, folderId: originalFolderId)

            await MainActor.run {
                self.playlists.append(newPlaylist)
                self.playlists.sort { $0.name < $1.name }
            }

            print("Duplicated playlist '\(playlistId)' to '\(newPlaylistId)' with \(trackIds.count) tracks")
            return newPlaylist
        }
    }

    func exportPlaylistFiles(playlistId: String, destinationURL: URL) async throws {
        guard activeCollectionDefinition != nil,
              let collectionService else {
            throw PlaylistError.noActiveCollection
        }

        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            let trackIds = try self.loadPlaylistTrackIdsSync(playlistId: playlistId, db: db)
            let playlistTracks = collectionService.tracks(ids: trackIds)

            var absolutePaths: [String] = []
            for track in playlistTracks {
                if FileManager.default.fileExists(atPath: track.path) {
                    absolutePaths.append(track.path)
                } else {
                    print("Warning: File not found at path: \(track.path)")
                }
            }

            let fileManager = FileManager.default
            for absolutePath in absolutePaths {
                let sourceURL = URL(fileURLWithPath: absolutePath)
                let destinationFileURL = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)

                do {
                    try fileManager.copyItem(at: sourceURL, to: destinationFileURL)
                    print("Copied file: \(sourceURL.lastPathComponent)")
                } catch {
                    print("Error copying file \(sourceURL.lastPathComponent): \(error)")
                }
            }

            print("Exported \(absolutePaths.count) files to: \(destinationURL.path)")
        }
    }

    func exportPlaylistCSV(playlistId: String, destinationURL: URL) async throws {
        guard let activeCollection = activeCollectionDefinition,
              let collectionService else {
            throw PlaylistError.noActiveCollection
        }

        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            let trackIds = try self.loadPlaylistTrackIdsSync(playlistId: playlistId, db: db)
            let playlistTracks = collectionService.tracks(ids: trackIds)

            var csvContent = "Title,Artist,Album,Album Artist,Composer,Genre,Year,Track Number,Disc Number,BPM,Relative Path,Duration,Rating,Comment,Tags,Date Added\n"

            for track in playlistTracks {
                let durationMinutes = track.duration / 60000
                let durationSeconds = (track.duration % 60000) / 1000
                let formattedDuration = String(format: "%d:%02d", durationMinutes, durationSeconds)

                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                let formattedDateAdded = dateFormatter.string(from: track.dateAdded)

                let escapedTitle = track.title.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedArtist = track.artist.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedAlbum = track.album.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedAlbumArtist = (track.albumArtist ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                let escapedComposer = (track.composer ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                let escapedGenre = (track.genre ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                let relativePath = self.convertToRelativePath(track.path, activeCollection: activeCollection)
                let escapedTrackPath = relativePath.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedComment = track.comment.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedGeneralTags = track.generalTags.joined(separator: ", ").replacingOccurrences(of: "\"", with: "\"\"")
                let escapedDateAdded = formattedDateAdded.replacingOccurrences(of: "\"", with: "\"\"")

                csvContent += "\"\(escapedTitle)\",\"\(escapedArtist)\",\"\(escapedAlbum)\",\"\(escapedAlbumArtist)\",\"\(escapedComposer)\",\"\(escapedGenre)\",\"\(track.year ?? 0)\",\"\(track.trackNumber ?? 0)\",\"\(track.discNumber ?? 0)\",\"\(track.bpm ?? 0)\",\"\(escapedTrackPath)\",\"\(formattedDuration)\",\"\(track.rating)\",\"\(escapedComment)\",\"\(escapedGeneralTags)\",\"\(escapedDateAdded)\"\n"
            }

            try csvContent.write(to: destinationURL, atomically: true, encoding: .utf8)
            print("Exported CSV to: \(destinationURL.path)")
        }
    }
    
    private func convertToRelativePath(_ absolutePath: String, activeCollection: CollectionDefinition) -> String {
        switch activeCollection.type {
        case .shared:
            if let rootPath = activeCollection.rootPath {
                let rootURL = URL(fileURLWithPath: rootPath)
                let absoluteURL = URL(fileURLWithPath: absolutePath)
                
                if absoluteURL.path.hasPrefix(rootURL.path) {
                    let relativePath = String(absoluteURL.path.dropFirst(rootURL.path.count + 1))
                    return relativePath
                } else {
                    return absolutePath
                }
            } else {
                return absolutePath
            }
        case .local:
            // For local collections, try to make relative to database location
            let dbURL = URL(fileURLWithPath: activeCollection.dbPath)
            let dbDir = dbURL.deletingLastPathComponent()
            let absoluteURL = URL(fileURLWithPath: absolutePath)
            
            if absoluteURL.path.hasPrefix(dbDir.path) {
                let relativePath = String(absoluteURL.path.dropFirst(dbDir.path.count + 1))
                return relativePath
            } else {
                return absolutePath
            }
        }
    }
    
    // MARK: - Folder Management
    func loadFolders() async throws {
        guard let _ = activeCollectionDefinition else {
            // Silently return if no collection is active yet - this is normal during app startup
            await MainActor.run {
                self.folders = []
                self.isLoading = false
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            
            let query = """
                SELECT \(self.columnPlaylistFoldersId), \(self.columnPlaylistFoldersName), 
                       \(self.columnPlaylistFoldersParentId), \(self.columnPlaylistFoldersDateCreated), 
                       \(self.columnPlaylistFoldersDateModified)
                FROM \(self.tablePlaylistFolders)
                ORDER BY \(self.columnPlaylistFoldersName) ASC
            """
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            var loadedFolders: [PlaylistFolder] = []
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let folderId = String(cString: sqlite3_column_text(statement, 0))
                let folderName = String(cString: sqlite3_column_text(statement, 1))
                
                let parentFolderId: String?
                if let parentPtr = sqlite3_column_text(statement, 2) {
                    parentFolderId = String(cString: parentPtr)
                } else {
                    parentFolderId = nil
                }
                
                let dateCreatedString = String(cString: sqlite3_column_text(statement, 3))
                let dateModifiedString = String(cString: sqlite3_column_text(statement, 4))
                
                // Parse dates (assuming ISO 8601 format)
                let formatter = ISO8601DateFormatter()
                let dateCreated = formatter.date(from: dateCreatedString) ?? Date()
                let dateModified = formatter.date(from: dateModifiedString) ?? Date()
                
                // Get expansion state from local storage or default to true
                let isExpanded = self.folderExpandedStates[folderId] ?? true
                
                var folder = PlaylistFolder(
                    id: folderId,
                    name: folderName,
                    parentFolderId: parentFolderId,
                    isExpanded: isExpanded
                )
                
                // Update the folder's dates to match database
                folder.dateCreated = dateCreated
                folder.dateModified = dateModified
                
                loadedFolders.append(folder)
            }
            
            await MainActor.run {
                self.folders = loadedFolders
                self.isLoading = false
            }
            
            print("Loaded \(loadedFolders.count) folders")
            return ()
        }
    }
    
    func createFolder(name: String, parentFolderId: String? = nil) async throws -> PlaylistFolder {
        guard let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw PlaylistError.invalidName
        }
        
        // Validate parent folder exists if specified
        if let parentId = parentFolderId {
            let parentExists = try await folderExists(folderId: parentId)
            if !parentExists {
                throw PlaylistError.folderNotFound
            }
            
            // Check for maximum depth
            let depth = try await calculateFolderDepth(folderId: parentId)
            if depth >= 10 {
                throw PlaylistError.maxDepthExceeded
            }
        }
        
        let newFolder = PlaylistFolder(name: trimmedName, parentFolderId: parentFolderId)
        
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            
            let formatter = ISO8601DateFormatter()
            let dateCreatedString = formatter.string(from: newFolder.dateCreated)
            let dateModifiedString = formatter.string(from: newFolder.dateModified)
            
            let query = """
                INSERT INTO \(self.tablePlaylistFolders) 
                (\(self.columnPlaylistFoldersId), \(self.columnPlaylistFoldersName), 
                 \(self.columnPlaylistFoldersParentId), \(self.columnPlaylistFoldersDateCreated), 
                 \(self.columnPlaylistFoldersDateModified)) 
                VALUES (?, ?, ?, ?, ?)
            """
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(statement, 1, (newFolder.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (newFolder.name as NSString).utf8String, -1, nil)
            
            if let parentId = newFolder.parentFolderId {
                sqlite3_bind_text(statement, 3, (parentId as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            
            sqlite3_bind_text(statement, 4, (dateCreatedString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (dateModifiedString as NSString).utf8String, -1, nil)
            
            let insertResult = sqlite3_step(statement)
            if insertResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            await MainActor.run {
                self.folders.append(newFolder)
                self.folders.sort { $0.name < $1.name }
                self.folderExpandedStates[newFolder.id] = newFolder.isExpanded
            }
            
            print("Created folder: \(newFolder.name) with ID: \(newFolder.id)")
            return newFolder
        }
    }
    
    func deleteFolder(folderId: String) async throws {
        guard let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            // First, move all child playlists to the parent folder (or root if no parent)
            let folder = self.folders.first { $0.id == folderId }
            let parentFolderId = folder?.parentFolderId
            
            // Update playlists that are in this folder to move to parent folder
            let updatePlaylistsQuery = """
                UPDATE \(self.tablePlaylists) 
                SET \(self.columnPlaylistsFolderId) = ? 
                WHERE \(self.columnPlaylistsFolderId) = ?
            """
            var updatePlaylistsStatement: OpaquePointer?
            
            let updatePlaylistsResult = sqlite3_prepare_v2(db, updatePlaylistsQuery, -1, &updatePlaylistsStatement, nil)
            defer { sqlite3_finalize(updatePlaylistsStatement) }
            
            if updatePlaylistsResult == SQLITE_OK {
                if let parentId = parentFolderId {
                    sqlite3_bind_text(updatePlaylistsStatement, 1, (parentId as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(updatePlaylistsStatement, 1)
                }
                sqlite3_bind_text(updatePlaylistsStatement, 2, (folderId as NSString).utf8String, -1, nil)
                
                let updatePlaylistsStepResult = sqlite3_step(updatePlaylistsStatement)
                if updatePlaylistsStepResult != SQLITE_DONE {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw PlaylistError.queryFailed(message: "Failed to update playlists: \(errorMessage)")
                }
            }
            
            // Update child folders to move to parent folder
            let updateFoldersQuery = """
                UPDATE \(self.tablePlaylistFolders) 
                SET \(self.columnPlaylistFoldersParentId) = ? 
                WHERE \(self.columnPlaylistFoldersParentId) = ?
            """
            var updateFoldersStatement: OpaquePointer?
            
            let updateFoldersResult = sqlite3_prepare_v2(db, updateFoldersQuery, -1, &updateFoldersStatement, nil)
            defer { sqlite3_finalize(updateFoldersStatement) }
            
            if updateFoldersResult == SQLITE_OK {
                if let parentId = parentFolderId {
                    sqlite3_bind_text(updateFoldersStatement, 1, (parentId as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(updateFoldersStatement, 1)
                }
                sqlite3_bind_text(updateFoldersStatement, 2, (folderId as NSString).utf8String, -1, nil)
                
                let updateFoldersStepResult = sqlite3_step(updateFoldersStatement)
                if updateFoldersStepResult != SQLITE_DONE {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw PlaylistError.queryFailed(message: "Failed to update child folders: \(errorMessage)")
                }
            }
            
            // Delete the folder
            let deleteQuery = "DELETE FROM \(self.tablePlaylistFolders) WHERE \(self.columnPlaylistFoldersId) = ?"
            var deleteStatement: OpaquePointer?
            
            let deleteResult = sqlite3_prepare_v2(db, deleteQuery, -1, &deleteStatement, nil)
            defer { sqlite3_finalize(deleteStatement) }
            
            if deleteResult != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(deleteStatement, 1, (folderId as NSString).utf8String, -1, nil)
            
            let deleteStepResult = sqlite3_step(deleteStatement)
            if deleteStepResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            await MainActor.run {
                // Update local state
                self.folders.removeAll { $0.id == folderId }
                self.folderExpandedStates.removeValue(forKey: folderId)
                
                // Update parent folder IDs for orphaned items
                for i in 0..<self.folders.count {
                    if self.folders[i].parentFolderId == folderId {
                        self.folders[i].parentFolderId = parentFolderId
                    }
                }
                
                for i in 0..<self.playlists.count {
                    if self.playlists[i].folderId == folderId {
                        self.playlists[i].folderId = parentFolderId
                    }
                }
            }
            
            print("Deleted folder ID: \(folderId)")
            return ()
        }
    }
    
    func renameFolder(folderId: String, newName: String) async throws {
        guard let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw PlaylistError.invalidName
        }
        
        // Check if folder exists
        let folderExists = try await self.folderExists(folderId: folderId)
        if !folderExists {
            throw PlaylistError.folderNotFound
        }
        
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            
            let query = """
                UPDATE \(self.tablePlaylistFolders) 
                SET \(self.columnPlaylistFoldersName) = ?, \(self.columnPlaylistFoldersDateModified) = ? 
                WHERE \(self.columnPlaylistFoldersId) = ?
            """
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            let dateModified = ISO8601DateFormatter().string(from: Date())
            sqlite3_bind_text(statement, 1, (trimmedName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (dateModified as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (folderId as NSString).utf8String, -1, nil)
            
            let updateResult = sqlite3_step(statement)
            if updateResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            // Update local folder state
            await MainActor.run {
                if let index = self.folders.firstIndex(where: { $0.id == folderId }) {
                    self.folders[index].name = trimmedName
                    self.folders[index].dateModified = Date()
                }
            }
            
            print("Renamed folder '\(folderId)' to '\(trimmedName)'")
            return ()
        }
    }
    
    func movePlaylistToFolder(playlistId: String, folderId: String?) async throws {
        guard let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        // Validate that playlist exists
        guard let playlistIndex = await MainActor.run(body: { 
            self.playlists.firstIndex(where: { $0.id == playlistId }) 
        }) else {
            throw PlaylistError.queryFailed(message: "Playlist not found")
        }
        
        // If moving to a folder, validate that folder exists
        if let targetFolderId = folderId {
            let folderExists = try await self.folderExists(folderId: targetFolderId)
            if !folderExists {
                throw PlaylistError.folderNotFound
            }
        }
        
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            
            let query = "UPDATE \(self.tablePlaylists) SET \(self.columnPlaylistsFolderId) = ? WHERE \(self.columnPlaylistsId) = ?"
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            if let targetFolderId = folderId {
                sqlite3_bind_text(statement, 1, (targetFolderId as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 1)
            }
            sqlite3_bind_text(statement, 2, (playlistId as NSString).utf8String, -1, nil)
            
            let updateResult = sqlite3_step(statement)
            if updateResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            // Update local playlist state
            await MainActor.run {
                self.playlists[playlistIndex].folderId = folderId
            }
            
            let folderDescription = folderId ?? "root level"
            print("Moved playlist '\(playlistId)' to folder '\(folderDescription)'")
            return ()
        }
    }
    
    func moveFolderToFolder(folderId: String, parentFolderId: String?) async throws {
        guard let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        // Validate that source folder exists
        let folderExists = try await self.folderExists(folderId: folderId)
        if !folderExists {
            throw PlaylistError.folderNotFound
        }
        
        // If moving to a parent folder, validate it exists and prevent circular references
        if let targetParentId = parentFolderId {
            let parentExists = try await self.folderExists(folderId: targetParentId)
            if !parentExists {
                throw PlaylistError.folderNotFound
            }
            
            // Check for circular reference - ensure target parent is not a descendant of the folder being moved
            if try await isDescendantFolder(childId: targetParentId, ancestorId: folderId) {
                throw PlaylistError.circularReference
            }
        }
        
        // Calculate new depth and validate maximum depth limit
        let newDepth = try await calculateNewFolderDepth(folderId: folderId, newParentId: parentFolderId)
        if newDepth > 10 { // Maximum depth limit
            throw PlaylistError.maxDepthExceeded
        }
        
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            
            let query = """
                UPDATE \(self.tablePlaylistFolders) 
                SET \(self.columnPlaylistFoldersParentId) = ?, \(self.columnPlaylistFoldersDateModified) = ? 
                WHERE \(self.columnPlaylistFoldersId) = ?
            """
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            let dateModified = ISO8601DateFormatter().string(from: Date())
            if let targetParentId = parentFolderId {
                sqlite3_bind_text(statement, 1, (targetParentId as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 1)
            }
            sqlite3_bind_text(statement, 2, (dateModified as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (folderId as NSString).utf8String, -1, nil)
            
            let updateResult = sqlite3_step(statement)
            if updateResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            // Update local folder state
            await MainActor.run {
                if let index = self.folders.firstIndex(where: { $0.id == folderId }) {
                    self.folders[index].parentFolderId = parentFolderId
                    self.folders[index].dateModified = Date()
                }
            }
            
            let parentDescription = parentFolderId ?? "root level"
            print("Moved folder '\(folderId)' to parent '\(parentDescription)'")
            return ()
        }
    }
    
    // MARK: - Helper Methods for Folder Management
    private func folderExists(folderId: String) async throws -> Bool {
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            let query = "SELECT COUNT(*) FROM \(self.tablePlaylistFolders) WHERE \(self.columnPlaylistFoldersId) = ?"
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(statement, 1, (folderId as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = sqlite3_column_int(statement, 0)
                return count > 0
            }
            
            return false
        }
    }
    
    private func calculateFolderDepth(folderId: String) async throws -> Int {
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            var currentId: String? = folderId
            var depth = 0
            
            while let id = currentId, depth < 20 { // Safety limit to prevent infinite loops
                let query = "SELECT \(self.columnPlaylistFoldersParentId) FROM \(self.tablePlaylistFolders) WHERE \(self.columnPlaylistFoldersId) = ?"
                var statement: OpaquePointer?
                
                let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                defer { sqlite3_finalize(statement) }
                
                if result != SQLITE_OK {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw PlaylistError.queryFailed(message: errorMessage)
                }
                
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let parentPtr = sqlite3_column_text(statement, 0) {
                        currentId = String(cString: parentPtr)
                        depth += 1
                    } else {
                        currentId = nil // Reached root
                    }
                } else {
                    currentId = nil // Folder not found
                }
            }
            
            return depth
        }
    }
    
    private func isDescendantFolder(childId: String, ancestorId: String) async throws -> Bool {
        return try await withDatabaseQueue {
            let db = try self.getDatabaseConnection()
            var currentId: String? = childId
            var visited: Set<String> = []
            
            while let id = currentId {
                // Prevent infinite loops
                if visited.contains(id) {
                    return false
                }
                visited.insert(id)
                
                // If we found the ancestor, it's a circular reference
                if id == ancestorId {
                    return true
                }
                
                // Get parent of current folder
                let query = "SELECT \(self.columnPlaylistFoldersParentId) FROM \(self.tablePlaylistFolders) WHERE \(self.columnPlaylistFoldersId) = ?"
                var statement: OpaquePointer?
                
                let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                defer { sqlite3_finalize(statement) }
                
                if result != SQLITE_OK {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw PlaylistError.queryFailed(message: errorMessage)
                }
                
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let parentPtr = sqlite3_column_text(statement, 0) {
                        currentId = String(cString: parentPtr)
                    } else {
                        currentId = nil // Reached root
                    }
                } else {
                    currentId = nil // Folder not found
                }
            }
            
            return false
        }
    }
    
    private func calculateNewFolderDepth(folderId: String, newParentId: String?) async throws -> Int {
        // If moving to root level, depth is 0
        guard let parentId = newParentId else {
            return 0
        }
        
        // Calculate depth of the new parent and add 1
        let parentDepth = try await self.calculateFolderDepth(folderId: parentId)
        return parentDepth + 1
    }
    
    // MARK: - Folder as Playlist Support
    
    /// Get all track ids from all playlists within a folder (recursively)
    func getFolderTrackIds(folderId: String) async throws -> [Int] {
        return try await withDatabaseQueue {
            try self.getFolderTrackIdsSync(folderId: folderId)
        }
    }

    private func getFolderTrackIdsSync(folderId: String) throws -> [Int] {
        print("🔍 Inside database queue for folder: \(folderId) on thread: \(Thread.current)")
        let db = try self.getDatabaseConnection()

        let query = """
            WITH RECURSIVE folder_hierarchy AS (
                SELECT \(self.columnPlaylistFoldersId) as folder_id
                FROM \(self.tablePlaylistFolders)
                WHERE \(self.columnPlaylistFoldersId) = ?

                UNION ALL

                SELECT f.\(self.columnPlaylistFoldersId) as folder_id
                FROM \(self.tablePlaylistFolders) f
                INNER JOIN folder_hierarchy fh ON f.\(self.columnPlaylistFoldersParentId) = fh.folder_id
            )
            SELECT pt.\(self.columnPlaylistTracksTrackId)
            FROM \(self.tablePlaylistTracks) pt
            JOIN \(self.tablePlaylists) p ON pt.\(self.columnPlaylistTracksPlaylistId) = p.\(self.columnPlaylistsId)
            JOIN folder_hierarchy fh ON p.\(self.columnPlaylistsFolderId) = fh.folder_id
            ORDER BY pt.\(self.columnPlaylistTracksSortOrder)
        """

        print("🔍 About to prepare statement for folder: \(folderId)")
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }

        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ SQLite prepare failed: \(errorMessage)")
            throw PlaylistError.queryFailed(message: errorMessage)
        }

        print("🔍 Statement prepared successfully for folder: \(folderId)")
        sqlite3_bind_text(statement, 1, folderId, -1, self.SQLITE_TRANSIENT)

        var trackIds: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            trackIds.append(Int(sqlite3_column_int64(statement, 0)))
        }

        print("🔍 Found \(trackIds.count) tracks for folder: \(folderId)")
        return trackIds
    }

    /// Get the total duration of all tracks in a folder
    func getFolderDuration(folderId: String) async throws -> TimeInterval {
        let trackIds = try await getFolderTrackIds(folderId: folderId)

        guard let collectionService else {
            return 0
        }

        var totalDuration: TimeInterval = 0
        for track in collectionService.tracks(ids: trackIds) {
            totalDuration += Double(track.duration)
        }

        return totalDuration
    }

    /// Get a SelectableItem for a folder with computed track ids and duration
    func getSelectableItem(for folder: PlaylistFolder) async throws -> SelectableItem {
        _ = try await getFolderTrackIds(folderId: folder.id)
        _ = try await getFolderDuration(folderId: folder.id)
        return .folder(folder)
    }
    
    /// Get a SelectableItem for a playlist
    func getSelectableItem(for playlist: Playlist) -> SelectableItem {
        return .playlist(playlist)
    }
    
    // MARK: - Snackbar Methods
    func showSnackbar(message: String) {
        DispatchQueue.main.async {
            self.snackbarMessage = message
        }
    }
    
    func dismissSnackbar() {
        DispatchQueue.main.async {
            self.snackbarMessage = nil
        }
    }
}

// MARK: - Errors
enum PlaylistError: LocalizedError {
    case noActiveCollection
    case queryFailed(message: String)
    case invalidName
    case folderNotFound
    case circularReference
    case maxDepthExceeded
    case folderNotEmpty
    
    var errorDescription: String? {
        switch self {
        case .noActiveCollection:
            return "No active collection"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .invalidName:
            return "Invalid playlist name"
        case .folderNotFound:
            return "Folder not found"
        case .circularReference:
            return "Circular reference detected"
        case .maxDepthExceeded:
            return "Maximum folder depth exceeded"
        case .folderNotEmpty:
            return "Folder is not empty"
        }
    }
}
