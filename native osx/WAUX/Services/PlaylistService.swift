import Foundation
import SQLite3
import Combine
import SwiftUI

class PlaylistService: ObservableObject {
    // MARK: - Constants
    private let tablePlaylists = "playlists"
    private let tablePlaylistTracks = "playlist_tracks"
    
    // Column names
    private let columnPlaylistsId = "id"
    private let columnPlaylistsName = "name"
    private let columnPlaylistTracksPlaylistId = "playlist_id"
    private let columnPlaylistTracksTrackPath = "track_path"
    private let columnPlaylistTracksSortOrder = "sort_order"
    
    // MARK: - Properties
    @Published var playlists: [Playlist] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
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
        print("PlaylistService database set")
    }
    
    func closeCollection() {
        database = nil
        activeCollectionDefinition = nil
        databaseQueue = nil
        collectionService = nil
        
        DispatchQueue.main.async {
            self.playlists = []
        }
    }
    
    // MARK: - Helper Methods
    private func withDatabaseQueue<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        guard let queue = databaseQueue else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        let result = try await operation()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
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
        
        return try await withDatabaseQueue {
            let query = "SELECT * FROM \(self.tablePlaylists)"
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
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
            
            await MainActor.run {
                self.playlists = sortedPlaylists
                self.isLoading = false
            }
            
            print("Loaded \(loadedPlaylists.count) playlists")
            return ()
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
        
        return try await withDatabaseQueue {
            let trackPaths = try self.loadPlaylistTracksSync(playlistId: playlistId, db: db)
            return trackPaths
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
        
        return try await withDatabaseQueue {
            let query = "INSERT INTO \(self.tablePlaylists) (\(self.columnPlaylistsId), \(self.columnPlaylistsName)) VALUES (?, ?)"
            var statement: OpaquePointer?
            
            let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(statement, 1, (newPlaylist.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (newPlaylist.name as NSString).utf8String, -1, nil)
            
            let insertResult = sqlite3_step(statement)
            if insertResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            await MainActor.run {
                self.playlists.append(newPlaylist)
                self.playlists.sort { $0.name < $1.name }
            }
            
            print("Created playlist: \(newPlaylist.name)")
            return newPlaylist
        }
    }
    
    func deletePlaylist(playlistId: String) async throws {
        guard let db = database,
              let _ = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withDatabaseQueue {
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
    
    func addTrackToPlaylist(playlistId: String, absoluteTrackPath: String) async throws {
        guard let db = database,
              let activeCollection = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withDatabaseQueue {
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
                        return ()
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
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(insertStatement, 1, (playlistId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (pathToAdd as NSString).utf8String, -1, nil)
            sqlite3_bind_int(insertStatement, 3, Int32(sortOrder))
            
            let stepResult = sqlite3_step(insertStatement)
            if stepResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            // Update local playlist
            let finalPathToAdd = pathToAdd
            await MainActor.run {
                if let index = self.playlists.firstIndex(where: { $0.id == playlistId }) {
                    self.playlists[index].addTrack(finalPathToAdd)
                }
            }
            
            print("Added track '\(pathToAdd)' to playlist '\(playlistId)'")
            return ()
        }
    }
    
    func removeTrackFromPlaylist(playlistId: String, absoluteTrackPath: String) async throws {
        guard let db = database,
              let activeCollection = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withDatabaseQueue {
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
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(statement, 1, (playlistId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (pathToRemove as NSString).utf8String, -1, nil)
            
            let deleteResult = sqlite3_step(statement)
            if deleteResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            // Update local playlist
            let finalPathToRemove = pathToRemove
            await MainActor.run {
                if let index = self.playlists.firstIndex(where: { $0.id == playlistId }) {
                    self.playlists[index].removeTrack(finalPathToRemove)
                }
            }
            
            print("Removed track '\(pathToRemove)' from playlist '\(playlistId)'")
            return ()
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
        
        return try await withDatabaseQueue {
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
        guard let db = database,
              let activeCollection = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw PlaylistError.invalidName
        }
        
        return try await withDatabaseQueue {
            // First, create the new playlist
            let newPlaylistId = UUID().uuidString
            let insertQuery = "INSERT INTO \(self.tablePlaylists) (\(self.columnPlaylistsId), \(self.columnPlaylistsName)) VALUES (?, ?)"
            var insertStatement: OpaquePointer?
            
            let insertResult = sqlite3_prepare_v2(db, insertQuery, -1, &insertStatement, nil)
            defer { sqlite3_finalize(insertStatement) }
            
            if insertResult != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(insertStatement, 1, (newPlaylistId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (trimmedName as NSString).utf8String, -1, nil)
            
            let stepResult = sqlite3_step(insertStatement)
            if stepResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            // Get all tracks from the original playlist
            let tracksQuery = "SELECT \(self.columnPlaylistTracksTrackPath), \(self.columnPlaylistTracksSortOrder) FROM \(self.tablePlaylistTracks) WHERE \(self.columnPlaylistTracksPlaylistId) = ? ORDER BY \(self.columnPlaylistTracksSortOrder)"
            var tracksStatement: OpaquePointer?
            
            let tracksResult = sqlite3_prepare_v2(db, tracksQuery, -1, &tracksStatement, nil)
            defer { sqlite3_finalize(tracksStatement) }
            
            if tracksResult != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(tracksStatement, 1, (playlistId as NSString).utf8String, -1, nil)
            
            var trackPaths: [String] = []
            while sqlite3_step(tracksStatement) == SQLITE_ROW {
                if let trackPathPtr = sqlite3_column_text(tracksStatement, 0) {
                    let trackPath = String(cString: trackPathPtr)
                    trackPaths.append(trackPath)
                }
            }
            
            // Copy all tracks to the new playlist
            for (index, trackPath) in trackPaths.enumerated() {
                let copyQuery = """
                    INSERT INTO \(self.tablePlaylistTracks) 
                    (\(self.columnPlaylistTracksPlaylistId), \(self.columnPlaylistTracksTrackPath), \(self.columnPlaylistTracksSortOrder)) 
                    VALUES (?, ?, ?)
                """
                var copyStatement: OpaquePointer?
                
                let copyResult = sqlite3_prepare_v2(db, copyQuery, -1, &copyStatement, nil)
                defer { sqlite3_finalize(copyStatement) }
                
                if copyResult != SQLITE_OK {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw PlaylistError.queryFailed(message: errorMessage)
                }
                
                sqlite3_bind_text(copyStatement, 1, (newPlaylistId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(copyStatement, 2, (trackPath as NSString).utf8String, -1, nil)
                sqlite3_bind_int(copyStatement, 3, Int32(index))
                
                let copyStepResult = sqlite3_step(copyStatement)
                if copyStepResult != SQLITE_DONE {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw PlaylistError.queryFailed(message: errorMessage)
                }
            }
            
            // Create the new playlist object
            let newPlaylist = Playlist(id: newPlaylistId, name: trimmedName, trackPaths: trackPaths)
            
            // Update local playlists
            await MainActor.run {
                self.playlists.append(newPlaylist)
                self.playlists.sort { $0.name < $1.name }
            }
            
            print("Duplicated playlist '\(playlistId)' to '\(newPlaylistId)' with \(trackPaths.count) tracks")
            return newPlaylist
        }
    }
    
    func exportPlaylistFiles(playlistId: String, destinationURL: URL) async throws {
        guard let db = database,
              let activeCollection = activeCollectionDefinition else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withDatabaseQueue {
            // Get all tracks from the playlist
            let tracksQuery = "SELECT \(self.columnPlaylistTracksTrackPath) FROM \(self.tablePlaylistTracks) WHERE \(self.columnPlaylistTracksPlaylistId) = ? ORDER BY \(self.columnPlaylistTracksSortOrder)"
            var tracksStatement: OpaquePointer?
            
            let tracksResult = sqlite3_prepare_v2(db, tracksQuery, -1, &tracksStatement, nil)
            defer { sqlite3_finalize(tracksStatement) }
            
            if tracksResult != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(tracksStatement, 1, (playlistId as NSString).utf8String, -1, nil)
            
            var trackPaths: [String] = []
            while sqlite3_step(tracksStatement) == SQLITE_ROW {
                if let trackPathPtr = sqlite3_column_text(tracksStatement, 0) {
                    let trackPath = String(cString: trackPathPtr)
                    trackPaths.append(trackPath)
                }
            }
            
            // Convert relative paths to absolute paths
            var absolutePaths: [String] = []
            for trackPath in trackPaths {
                let absolutePath = self.convertToAbsolutePath(trackPath, activeCollection: activeCollection)
                if FileManager.default.fileExists(atPath: absolutePath) {
                    absolutePaths.append(absolutePath)
                } else {
                    print("Warning: File not found at path: \(absolutePath)")
                }
            }
            
            // Copy files to destination
            let fileManager = FileManager.default
            for absolutePath in absolutePaths {
                let sourceURL = URL(fileURLWithPath: absolutePath)
                let destinationFileURL = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)
                
                do {
                    try fileManager.copyItem(at: sourceURL, to: destinationFileURL)
                    print("Copied file: \(sourceURL.lastPathComponent)")
                } catch {
                    print("Error copying file \(sourceURL.lastPathComponent): \(error)")
                    // Continue with other files even if one fails
                }
            }
            
            print("Exported \(absolutePaths.count) files to: \(destinationURL.path)")
        }
    }
    
    func exportPlaylistCSV(playlistId: String, destinationURL: URL) async throws {
        guard let db = database,
              let activeCollection = activeCollectionDefinition,
              let collectionService = collectionService else {
            throw PlaylistError.noActiveCollection
        }
        
        return try await withDatabaseQueue {
            // Get all tracks from the playlist
            let tracksQuery = "SELECT \(self.columnPlaylistTracksTrackPath), \(self.columnPlaylistTracksSortOrder) FROM \(self.tablePlaylistTracks) WHERE \(self.columnPlaylistTracksPlaylistId) = ? ORDER BY \(self.columnPlaylistTracksSortOrder)"
            var tracksStatement: OpaquePointer?
            
            let tracksResult = sqlite3_prepare_v2(db, tracksQuery, -1, &tracksStatement, nil)
            defer { sqlite3_finalize(tracksStatement) }
            
            if tracksResult != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw PlaylistError.queryFailed(message: errorMessage)
            }
            
            sqlite3_bind_text(tracksStatement, 1, (playlistId as NSString).utf8String, -1, nil)
            
            var trackPaths: [String] = []
            while sqlite3_step(tracksStatement) == SQLITE_ROW {
                if let trackPathPtr = sqlite3_column_text(tracksStatement, 0) {
                    let trackPath = String(cString: trackPathPtr)
                    trackPaths.append(trackPath)
                }
            }
            
            // Get tracks from the collection service using the paths
            let allTracks = collectionService.tracks
            var playlistTracks: [Track] = []
            
            for trackPath in trackPaths {
                if let track = allTracks.first(where: { $0.path == trackPath }) {
                    playlistTracks.append(track)
                }
            }
            
            var csvContent = "Title,Artist,Album,Album Artist,Composer,Genre,Year,Track Number,Disc Number,BPM,Relative Path,Duration,Rating,Comment,Tags,Date Added\n"
            
            for track in playlistTracks {
                // Format duration as MM:SS
                let durationMinutes = track.duration / 60000
                let durationSeconds = (track.duration % 60000) / 1000
                let formattedDuration = String(format: "%d:%02d", durationMinutes, durationSeconds)
                
                // Format date added
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                let formattedDateAdded = dateFormatter.string(from: track.dateAdded)
                
                // Escape CSV values
                let escapedTitle = track.title.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedArtist = track.artist.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedAlbum = track.album.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedAlbumArtist = (track.albumArtist ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                let escapedComposer = (track.composer ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                let escapedGenre = (track.genre ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                // Convert absolute path to relative path
                let relativePath = self.convertToRelativePath(track.path, activeCollection: activeCollection)
                let escapedTrackPath = relativePath.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedComment = track.comment.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedGeneralTags = track.generalTags.joined(separator: ", ").replacingOccurrences(of: "\"", with: "\"\"")
                let escapedDateAdded = formattedDateAdded.replacingOccurrences(of: "\"", with: "\"\"")
                
                csvContent += "\"\(escapedTitle)\",\"\(escapedArtist)\",\"\(escapedAlbum)\",\"\(escapedAlbumArtist)\",\"\(escapedComposer)\",\"\(escapedGenre)\",\"\(track.year ?? 0)\",\"\(track.trackNumber ?? 0)\",\"\(track.discNumber ?? 0)\",\"\(track.bpm ?? 0)\",\"\(escapedTrackPath)\",\"\(formattedDuration)\",\"\(track.rating)\",\"\(escapedComment)\",\"\(escapedGeneralTags)\",\"\(escapedDateAdded)\"\n"
            }
            
            // Write CSV to file
            try csvContent.write(to: destinationURL, atomically: true, encoding: .utf8)
            print("Exported CSV to: \(destinationURL.path)")
        }
    }
    
    private func convertToAbsolutePath(_ relativePath: String, activeCollection: CollectionDefinition) -> String {
        switch activeCollection.type {
        case .shared:
            if let rootPath = activeCollection.rootPath {
                return (rootPath as NSString).appendingPathComponent(relativePath)
            } else {
                return relativePath
            }
        case .local:
            // For local collections, the path might already be absolute
            if relativePath.hasPrefix("/") {
                return relativePath
            } else {
                // Try to resolve relative to database location
                let dbURL = URL(fileURLWithPath: activeCollection.dbPath)
                let dbDir = dbURL.deletingLastPathComponent()
                return dbDir.appendingPathComponent(relativePath).path
            }
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
