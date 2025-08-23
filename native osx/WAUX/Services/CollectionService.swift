import Foundation
import SQLite3
import Combine

class CollectionService: ObservableObject {
    // MARK: - Constants
    private let databaseVersion = 5
    private let tableMusic = "music"
    private let tablePlaylists = "playlists"
    private let tablePlaylistTracks = "playlist_tracks"
    private let tableLocalRoots = "local_root_folders"
    private let tableUiSettings = "ui_settings"
    
    // Column names for music table
    private let columnId = "id"
    private let columnTitle = "title"
    private let columnArtist = "artist"
    private let columnAlbum = "album"
    private let columnAlbumArtist = "albumArtist"
    private let columnComposer = "composer"
    private let columnGenre = "genre"
    private let columnYear = "year"
    private let columnTrackNumber = "trackNumber"
    private let columnDiscNumber = "discNumber"
    private let columnBpm = "bpm"
    private let columnPath = "path"
    private let columnIsUrl = "isUrl"
    private let columnDuration = "duration"
    private let columnTimeMarkers = "timeMarkers"
    private let columnWaveformData = "waveformData"
    private let columnRating = "rating"
    private let columnComment = "comment"
    private let columnGeneralTags = "generalTags"
    
    // MARK: - Properties
    @Published var tracks: [Track] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var database: OpaquePointer?
    private var activeCollectionDefinition: CollectionDefinition?
    private var localCollectionRootFolders: [String] = []
    
    // MARK: - Initialization
    init() {
        print("CollectionService initialized. Ready to open a collection.")
    }
    
    deinit {
        closeCollection()
    }
    
    // MARK: - Collection Management
    func openCollection(_ definition: CollectionDefinition) async throws {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        print("Opening collection: \(definition.name) (\(definition.type.rawValue))")
        
        do {
            closeCollection()
            activeCollectionDefinition = definition
            
            // Ensure directories exist
            if definition.type == .shared {
                let dbDir = URL(fileURLWithPath: definition.rootPath!)
                if !FileManager.default.fileExists(atPath: dbDir.path) {
                    throw CollectionError.rootDirectoryNotFound(path: definition.rootPath!)
                }
            } else {
                // Local
                let dbDir = URL(fileURLWithPath: definition.dbPath).deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            }
            
            try openDatabase(path: definition.dbPath)
            print("Database opened at: \(definition.dbPath)")
            
            if definition.type == .local {
                try await loadLocalCollectionRootFolders()
            } else {
                localCollectionRootFolders = []
            }
            
            print("Collection \(definition.name) opened successfully.")
            
        } catch {
            print("Error opening collection \(definition.name): \(error)")
            activeCollectionDefinition = nil
            database = nil
            localCollectionRootFolders = []
            throw error
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    func closeCollection() {
        if let db = database {
            sqlite3_close(db)
            database = nil
        }
        activeCollectionDefinition = nil
        localCollectionRootFolders = []
        
        Task { @MainActor in
            tracks = []
        }
    }
    
    func getActiveCollection() -> CollectionDefinition? {
        return activeCollectionDefinition
    }
    
    // MARK: - Database Operations
    private func openDatabase(path: String) throws {
        // Handle path encoding issues (backslashes, spaces, etc.)
        let cleanPath = path.replacingOccurrences(of: "\\", with: "/")
        
        // Check if file exists and is readable
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: cleanPath) else {
            throw CollectionError.databaseOpenFailed(message: "Database file does not exist at path: \(cleanPath)")
        }
        
        // Check file permissions
        guard fileManager.isReadableFile(atPath: cleanPath) else {
            throw CollectionError.databaseOpenFailed(message: "Database file is not readable. Please check file permissions.")
        }
        
        print("Attempting to open database at: \(cleanPath)")
        
        // Try with UTF8 encoding
        let result = sqlite3_open_v2(cleanPath, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            sqlite3_close(database)
            database = nil
            throw CollectionError.databaseOpenFailed(message: "SQLite error: \(errorMessage)")
        }
        
        // Enable foreign keys
        let enableFKResult = sqlite3_exec(database, "PRAGMA foreign_keys = ON", nil, nil, nil)
        if enableFKResult != SQLITE_OK {
            print("Warning: Could not enable foreign keys")
        }
        
        print("Successfully opened database")
    }
    
    private func loadLocalCollectionRootFolders() async throws {
        guard let db = database,
              activeCollectionDefinition?.type == .local else {
            localCollectionRootFolders = []
            return
        }
        
        let query = "SELECT path FROM \(tableLocalRoots)"
        var statement: OpaquePointer?
        
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        if result == SQLITE_OK {
            var folders: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let pathPtr = sqlite3_column_text(statement, 0) {
                    let path = String(cString: pathPtr)
                    folders.append(path)
                }
            }
            localCollectionRootFolders = folders
            print("Loaded \(folders.count) root folders for local collection: \(activeCollectionDefinition?.name ?? "Unknown")")
        } else {
            print("Error loading local root folders")
            localCollectionRootFolders = []
        }
    }
    
    // MARK: - Testing
    func testDatabaseConnection(path: String) -> Bool {
        var testDb: OpaquePointer?
        let cleanPath = path.replacingOccurrences(of: "\\", with: "/")
        
        print("Testing database connection to: \(cleanPath)")
        
        // Try with read-only access first
        let result = sqlite3_open_v2(cleanPath, &testDb, SQLITE_OPEN_READONLY, nil)
        if result == SQLITE_OK {
            print("✅ Database connection test successful")
            sqlite3_close(testDb)
            return true
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(testDb))
            print("❌ Database connection test failed: \(errorMessage)")
            sqlite3_close(testDb)
            
            // Try with read-write access as fallback
            let result2 = sqlite3_open_v2(cleanPath, &testDb, SQLITE_OPEN_READWRITE, nil)
            if result2 == SQLITE_OK {
                print("✅ Database connection test successful (read-write)")
                sqlite3_close(testDb)
                return true
            } else {
                let errorMessage2 = String(cString: sqlite3_errmsg(testDb))
                print("❌ Database connection test failed (read-write): \(errorMessage2)")
                sqlite3_close(testDb)
                return false
            }
        }
    }
    
    // MARK: - Track Operations
    func loadAllTracks() async throws {
        guard let db = database else {
            throw CollectionError.databaseNotOpen
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        let query = "SELECT * FROM \(tableMusic)"
        var statement: OpaquePointer?
        
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        
        var loadedTracks: [Track] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let track = try? parseTrackFromRow(statement) {
                let resolvedTrack = resolveTrackPath(track)
                loadedTracks.append(resolvedTrack)
            }
        }
        
        await MainActor.run {
            tracks = loadedTracks.sorted()
            isLoading = false
        }
        
        print("Loaded \(loadedTracks.count) tracks from database")
    }
    
    private func parseTrackFromRow(_ statement: OpaquePointer?) throws -> Track {
        let id = Int(sqlite3_column_int(statement, 0))
        let title = String(cString: sqlite3_column_text(statement, 1))
        let artist = String(cString: sqlite3_column_text(statement, 2))
        let album = String(cString: sqlite3_column_text(statement, 3))
        
        // Optional metadata fields
        let albumArtist = sqlite3_column_type(statement, 4) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 4)) : nil
        let composer = sqlite3_column_type(statement, 5) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 5)) : nil
        let genre = sqlite3_column_type(statement, 6) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 6)) : nil
        let year = sqlite3_column_type(statement, 7) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 7)) : nil
        let trackNumber = sqlite3_column_type(statement, 8) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 8)) : nil
        let discNumber = sqlite3_column_type(statement, 9) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 9)) : nil
        let bpm = sqlite3_column_type(statement, 10) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 10)) : nil
        
        let path = String(cString: sqlite3_column_text(statement, 11))
        let isUrl = sqlite3_column_int(statement, 12) != 0
        let duration = Int(sqlite3_column_int(statement, 13))
        
        // Parse time markers
        let timeMarkers: [TimeMarker]
        if sqlite3_column_type(statement, 14) != SQLITE_NULL {
            let markersJson = String(cString: sqlite3_column_text(statement, 14))
            timeMarkers = try parseTimeMarkers(from: markersJson)
        } else {
            timeMarkers = []
        }
        
        // Parse waveform data
        let waveformData: [Double]?
        if sqlite3_column_type(statement, 15) != SQLITE_NULL {
            let waveformJson = String(cString: sqlite3_column_text(statement, 15))
            waveformData = try parseWaveformData(from: waveformJson)
        } else {
            waveformData = nil
        }
        
        let rating = Int(sqlite3_column_int(statement, 16))
        let comment = sqlite3_column_type(statement, 17) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 17)) : ""
        
        // Parse general tags
        let generalTags: [String]
        if sqlite3_column_type(statement, 18) != SQLITE_NULL {
            let tagsJson = String(cString: sqlite3_column_text(statement, 18))
            generalTags = try parseGeneralTags(from: tagsJson)
        } else {
            generalTags = []
        }
        
        return Track(
            id: id,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            composer: composer,
            genre: genre,
            year: year,
            trackNumber: trackNumber,
            discNumber: discNumber,
            bpm: bpm,
            path: path,
            isUrl: isUrl,
            duration: duration,
            timeMarkers: timeMarkers,
            waveformData: waveformData,
            rating: rating,
            comment: comment,
            generalTags: generalTags
        )
    }
    
    private func parseTimeMarkers(from jsonString: String) throws -> [TimeMarker] {
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode([TimeMarker].self, from: data)
    }
    
    private func parseWaveformData(from jsonString: String) throws -> [Double] {
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode([Double].self, from: data)
    }
    
    private func parseGeneralTags(from jsonString: String) throws -> [String] {
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode([String].self, from: data)
    }
    
    // MARK: - Path Resolution
    private func resolveTrackPath(_ track: Track) -> Track {
        guard let definition = activeCollectionDefinition,
              definition.type == .shared,
              !track.isUrl,
              let rootPath = definition.rootPath else {
            return track
        }
        
        let absolutePath = (rootPath as NSString).appendingPathComponent(track.path)
        return Track(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            albumArtist: track.albumArtist,
            composer: track.composer,
            genre: track.genre,
            year: track.year,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            bpm: track.bpm,
            path: absolutePath,
            isUrl: track.isUrl,
            duration: track.duration,
            timeMarkers: track.timeMarkers,
            waveformData: track.waveformData,
            rating: track.rating,
            comment: track.comment,
            generalTags: track.generalTags
        )
    }
    
    // MARK: - Utility Methods
    func getRootFolders() -> [String] {
        if let definition = activeCollectionDefinition {
            switch definition.type {
            case .shared:
                return definition.rootPath != nil ? [definition.rootPath!] : []
            case .local:
                return localCollectionRootFolders
            }
        }
        return []
    }
    
    func searchTracks(query: String) async throws -> [Track] {
        guard let db = database else {
            throw CollectionError.databaseNotOpen
        }
        
        let lowercaseQuery = query.lowercased()
        let wildcardQuery = "%\(lowercaseQuery)%"
        
        let query = """
            SELECT * FROM \(tableMusic)
            WHERE LOWER(title) LIKE ? OR LOWER(artist) LIKE ? OR LOWER(album) LIKE ? OR LOWER(comment) LIKE ?
        """
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        
        // Bind parameters
        sqlite3_bind_text(statement, 1, wildcardQuery, -1, nil)
        sqlite3_bind_text(statement, 2, wildcardQuery, -1, nil)
        sqlite3_bind_text(statement, 3, wildcardQuery, -1, nil)
        sqlite3_bind_text(statement, 4, wildcardQuery, -1, nil)
        
        var searchResults: [Track] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let track = try? parseTrackFromRow(statement) {
                let resolvedTrack = resolveTrackPath(track)
                searchResults.append(resolvedTrack)
            }
        }
        
        return searchResults.sorted()
    }
}

// MARK: - Errors
enum CollectionError: LocalizedError {
    case databaseNotOpen
    case databaseOpenFailed(message: String)
    case queryFailed(message: String)
    case rootDirectoryNotFound(path: String)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .databaseNotOpen:
            return "Database is not open"
        case .databaseOpenFailed(let message):
            return "Failed to open database: \(message)"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .rootDirectoryNotFound(let path):
            return "Root directory not found: \(path)"
        case .invalidData:
            return "Invalid data format"
        }
    }
}
