import Foundation
import AVFoundation
import SQLite3
import Combine
import SwiftUI

class CollectionService: ObservableObject {
    // MARK: - Constants
    private let databaseVersion = 6
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
    private let columnDateAdded = "dateAdded"
    
    // Explicit column selection to guarantee order across different DB schemas
    private var selectTrackColumns: String {
        "\(columnId), \(columnTitle), \(columnArtist), \(columnAlbum), \(columnAlbumArtist), \(columnComposer), \(columnGenre), \(columnYear), \(columnTrackNumber), \(columnDiscNumber), \(columnBpm), \(columnPath), \(columnIsUrl), \(columnDuration), \(columnTimeMarkers), \(columnWaveformData), \(columnRating), \(columnComment), \(columnGeneralTags), \(columnDateAdded)"
    }
    
    // MARK: - Properties
    @Published var tracks: [Track] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var globalTags: [TagDefinition] = []
    var pendingWaveformTrackIds: [Int] = []
    
    private var database: OpaquePointer?
    private var activeCollectionDefinition: CollectionDefinition?
    private var localCollectionRootFolders: [String] = []
    private var securityScopedURL: URL?
    private var isReadOnlyMode: Bool = false
    private let supportedExtensions: Set<String> = ["mp3", "wav", "ogg", "m4a", "aac", "flac"]
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    // MARK: - Thread Safety
    let databaseQueue = DispatchQueue(label: "com.waux.collection.database", qos: .userInitiated)
    
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
            try ensureUiSettingsTable()
            
            if definition.type == .local {
                // For local collections, the root folder is the folder containing the database
                let dbURL = URL(fileURLWithPath: definition.dbPath)
                let rootFolder = dbURL.deletingLastPathComponent().path
                localCollectionRootFolders = [rootFolder]
                print("📁 Set local collection root folder: \(rootFolder)")
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

        // Load global tags after opening the DB
        do {
            try await loadGlobalTags()
        } catch {
            print("Warning: Failed to load global tags: \(error)")
        }
    }
    
    func closeCollection() {
        if let db = database {
            sqlite3_close(db)
            database = nil
        }
        
        activeCollectionDefinition = nil
        localCollectionRootFolders = []
        isReadOnlyMode = false
        
        DispatchQueue.main.async {
            self.tracks = []
        }
    }
    
    func getActiveCollection() -> CollectionDefinition? {
        return activeCollectionDefinition
    }
    
    func getDatabase() -> OpaquePointer? {
        return database
    }
    
    func setSecurityScopedURL(_ url: URL) {
        securityScopedURL = url
        print("[Security] Set security-scoped URL: \(url.path)")
    }
    
    private func ensureSecurityAccess() -> Bool {
        guard let url = securityScopedURL else {
            print("[Security] No security-scoped URL set")
            return false
        }
        
        // Start accessing the security-scoped resource
        let success = url.startAccessingSecurityScopedResource()
        return success
    }
    
    private func stopSecurityAccess() {
        guard let url = securityScopedURL else { return }
        url.stopAccessingSecurityScopedResource()
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
        
        // Note: File permissions are checked in ContentView before calling this method
        // Security-scoped URLs may not report correct permissions here
        
        print("Attempting to open database at: \(cleanPath)")
        
        // Try with UTF8 encoding and thread safety
        // First try read-write, if that fails, try read-only (match flags used in testDatabaseConnection)
        var result = sqlite3_open_v2(cleanPath, &database, SQLITE_OPEN_READWRITE, nil)
        if result != SQLITE_OK {
            print("Read-write mode failed, trying read-only mode")
            result = sqlite3_open_v2(cleanPath, &database, SQLITE_OPEN_READONLY, nil)
            if result == SQLITE_OK {
                print("Database opened in read-only mode")
                isReadOnlyMode = true
            }
        }
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            sqlite3_close(database)
            database = nil
            throw CollectionError.databaseOpenFailed(message: "SQLite error: \(errorMessage)")
        }
        
        // Configure database for better compatibility and stability
        // Use DELETE journal mode to avoid creating separate journal files
        let journalModeResult = sqlite3_exec(database, "PRAGMA journal_mode = DELETE", nil, nil, nil)
        if journalModeResult != SQLITE_OK {
            print("Warning: Could not set journal mode to DELETE")
        }
        
        // Set synchronous mode to NORMAL for better performance while maintaining safety
        let synchronousResult = sqlite3_exec(database, "PRAGMA synchronous = NORMAL", nil, nil, nil)
        if synchronousResult != SQLITE_OK {
            print("Warning: Could not set synchronous mode")
        }
        
        // Set busy timeout to handle concurrent access
        let timeoutResult = sqlite3_busy_timeout(database, 30000) // 30 seconds
        if timeoutResult != SQLITE_OK {
            print("Warning: Could not set busy timeout")
        }
        
        // Disable WAL mode explicitly to avoid journal file issues
        let walResult = sqlite3_exec(database, "PRAGMA journal_mode = DELETE", nil, nil, nil)
        if walResult != SQLITE_OK {
            print("Warning: Could not disable WAL mode")
        }
        
        // Set temp store to memory to avoid creating temporary files
        let tempStoreResult = sqlite3_exec(database, "PRAGMA temp_store = MEMORY", nil, nil, nil)
        if tempStoreResult != SQLITE_OK {
            print("Warning: Could not set temp store to memory")
        }
        
        // Enable foreign keys
        let enableFKResult = sqlite3_exec(database, "PRAGMA foreign_keys = ON", nil, nil, nil)
        if enableFKResult != SQLITE_OK {
            print("Warning: Could not enable foreign keys")
        }
        
        print("Successfully opened database")
        
        // Check and migrate database schema if needed
        try migrateDatabaseSchema()
    }
    
    // MARK: - Database Migration
    private func migrateDatabaseSchema() throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        
        // Check if dateAdded column exists
        let checkColumnSQL = "PRAGMA table_info(\(tableMusic))"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, checkColumnSQL, -1, &statement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(statement) }
            
            var hasDateAddedColumn = false
            while sqlite3_step(statement) == SQLITE_ROW {
                let columnName = String(cString: sqlite3_column_text(statement, 1))
                if columnName == columnDateAdded {
                    hasDateAddedColumn = true
                    break
                }
            }
            
            if !hasDateAddedColumn {
                print("🔧 Adding dateAdded column to existing database...")
                let addColumnSQL = "ALTER TABLE \(tableMusic) ADD COLUMN \(columnDateAdded) TEXT DEFAULT ''"
                
                if sqlite3_exec(db, addColumnSQL, nil, nil, nil) != SQLITE_OK {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    print("⚠️ Failed to add dateAdded column: \(errorMessage)")
                    // Don't throw error as this is not critical for basic functionality
                } else {
                    print("✅ Successfully added dateAdded column")
                    
                    // Set a default date for existing tracks (use a date in the past to indicate they were added before this feature)
                    let defaultDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400 * 30)) // 30 days ago
                    let updateExistingSQL = "UPDATE \(tableMusic) SET \(columnDateAdded) = '\(defaultDate)' WHERE \(columnDateAdded) = '' OR \(columnDateAdded) IS NULL"
                    
                    if sqlite3_exec(db, updateExistingSQL, nil, nil, nil) != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        print("⚠️ Failed to set default dates for existing tracks: \(errorMessage)")
                    } else {
                        print("✅ Successfully set default dates for existing tracks")
                    }
                }
            }
        }
    }

    // MARK: - Database Creation (for new local collections)
    /// Creates a new local database file at the given path with the required schema if it doesn't already exist.
    func createNewLocalDatabase(at dbPath: String) throws {
        print("[DBCreate] Requested new DB at: \(dbPath)")
        let fm = FileManager.default
        let cleanPath = dbPath.replacingOccurrences(of: "\\", with: "/")
        let dbURL = URL(fileURLWithPath: cleanPath)

        // Ensure parent directory exists
        try fm.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        print("[DBCreate] Ensured directory exists: \(dbURL.deletingLastPathComponent().path)")

        // Create the file if needed (SQLite will also create, but we keep our openDatabase contract)
        if !fm.fileExists(atPath: cleanPath) {
            fm.createFile(atPath: cleanPath, contents: nil)
            print("[DBCreate] Created empty file at: \(cleanPath)")
        } else {
            print("[DBCreate] File already exists, will initialize schema: \(cleanPath)")
        }

        // Open and initialize schema
        try openDatabase(path: cleanPath)
        print("[DBCreate] Opened DB for schema initialization")
        defer {
            if let db = database {
                sqlite3_close(db)
                database = nil
            }
        }

        guard let db = database else { throw CollectionError.databaseNotOpen }

        let createMusicSQL = """
        CREATE TABLE IF NOT EXISTS \(tableMusic) (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            artist TEXT,
            album TEXT,
            albumArtist TEXT,
            composer TEXT,
            genre TEXT,
            year INTEGER,
            trackNumber INTEGER,
            discNumber INTEGER,
            bpm INTEGER,
            path TEXT NOT NULL,
            isUrl INTEGER NOT NULL DEFAULT 0,
            duration INTEGER,
            timeMarkers TEXT,
            waveformData TEXT,
            rating INTEGER DEFAULT 0,
            comment TEXT,
            generalTags TEXT,
            dateAdded TEXT DEFAULT ''
        )
        """

        let createPlaylistsSQL = """
        CREATE TABLE IF NOT EXISTS \(tablePlaylists) (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL
        )
        """

        let createPlaylistTracksSQL = """
        CREATE TABLE IF NOT EXISTS \(tablePlaylistTracks) (
            playlist_id TEXT NOT NULL,
            track_path TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
        )
        """

        let createLocalRootsSQL = """
        CREATE TABLE IF NOT EXISTS \(tableLocalRoots) (
            path TEXT PRIMARY KEY
        )
        """

        let statements = [createMusicSQL, createPlaylistsSQL, createPlaylistTracksSQL, createLocalRootsSQL]
        for sql in statements {
            print("[DBCreate] Executing SQL: \(sql.replacingOccurrences(of: "\n", with: " "))")
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                let err = String(cString: sqlite3_errmsg(db))
                throw CollectionError.queryFailed(message: "Schema creation failed: \(err)")
            }
        }

        // Ensure ui_settings exists
        try ensureUiSettingsTable()
        print("[DBCreate] Schema created successfully")
    }

    private func ensureUiSettingsTable() throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS \(tableUiSettings) (
            key TEXT PRIMARY KEY,
            value TEXT
        )
        """
        let result = sqlite3_exec(db, createTableSQL, nil, nil, nil)
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Failed creating ui_settings: \(errorMessage)")
        }
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
        print("🎵 loadAllTracks called")
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else {
                        print("❌ Database not open")
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    
                    // Check for existing tracks with tags to understand the format
                    let sampleQuery = "SELECT id, \(self.columnGeneralTags) FROM \(self.tableMusic) WHERE \(self.columnGeneralTags) IS NOT NULL AND LENGTH(TRIM(\(self.columnGeneralTags))) > 0 LIMIT 3"
                    var sampleStatement: OpaquePointer?
                    if sqlite3_prepare_v2(db, sampleQuery, -1, &sampleStatement, nil) == SQLITE_OK {
                        defer { sqlite3_finalize(sampleStatement) }
                        print("[Sample] Checking existing tag formats:")
                        while sqlite3_step(sampleStatement) == SQLITE_ROW {
                            let trackId = Int(sqlite3_column_int(sampleStatement, 0))
                            let tagsData = String(cString: sqlite3_column_text(sampleStatement, 1))
                            print("[Sample] Track \(trackId) existing tags format: '\(tagsData)'")
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.isLoading = true
                    }
                    
                    let query = "SELECT \(self.selectTrackColumns) FROM \(self.tableMusic)"
                    print("🔍 Executing query: \(query)")
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        print("❌ Query failed: \(errorMessage)")
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    var loadedTracks: [Track] = []
                    var failedTracks: [(id: Int, title: String, error: String, rawData: String)] = []
                    var rowCount = 0
                    
                    while sqlite3_step(statement) == SQLITE_ROW {
                        rowCount += 1
                        do {
                            let track = try self.parseTrackFromRow(statement)
                            let resolvedTrack = self.resolveTrackPath(track)
                            loadedTracks.append(resolvedTrack)
                        } catch {
                            // Enhanced error logging for failed track parsing
                            let id = Int(sqlite3_column_int(statement, 0))
                            let title = String(cString: sqlite3_column_text(statement, 1))
                            let artist = String(cString: sqlite3_column_text(statement, 2))
                            let album = String(cString: sqlite3_column_text(statement, 3))
                            
                            // Get raw data for problematic fields
                            var rawData = "ID: \(id), Title: '\(title)', Artist: '\(artist)', Album: '\(album)'"
                            
                            // Check for problematic generalTags data
                            if sqlite3_column_type(statement, 18) != SQLITE_NULL {
                                let tagsData = String(cString: sqlite3_column_text(statement, 18))
                                rawData += ", Tags: '\(tagsData)'"
                                
                                // Try to identify encoding issues in tags
                                if let data = tagsData.data(using: .utf8) {
                                    do {
                                        let decoder = JSONDecoder()
                                        let _ = try decoder.decode([String].self, from: data)
                                        print("🔍 Tags JSON is valid for track \(id)")
                                    } catch {
                                        print("🚨 JSON decode error for track \(id) tags: \(error)")
                                        print("🚨 Raw tags data: '\(tagsData)'")
                                        print("🚨 Data length: \(data.count) bytes")
                                        
                                        // Try different encodings
                                        if let dataUTF16 = tagsData.data(using: .utf16) {
                                            print("🚨 UTF-16 data length: \(dataUTF16.count) bytes")
                                        }
                                        if let dataASCII = tagsData.data(using: .ascii) {
                                            print("🚨 ASCII data length: \(dataASCII.count) bytes")
                                        }
                                    }
                                } else {
                                    print("🚨 Cannot convert tags data to UTF-8 for track \(id)")
                                    print("🚨 Raw tags string: '\(tagsData)'")
                                }
                            }
                            
                            // Check for problematic timeMarkers data
                            if sqlite3_column_type(statement, 14) != SQLITE_NULL {
                                let markersData = String(cString: sqlite3_column_text(statement, 14))
                                rawData += ", Markers: '\(markersData)'"
                                
                                if let data = markersData.data(using: .utf8) {
                                    do {
                                        let decoder = JSONDecoder()
                                        let _ = try decoder.decode([TimeMarker].self, from: data)
                                        print("🔍 Markers JSON is valid for track \(id)")
                                    } catch {
                                        print("🚨 JSON decode error for track \(id) markers: \(error)")
                                        print("🚨 Raw markers data: '\(markersData)'")
                                    }
                                }
                            }
                            
                            // Check for problematic waveformData
                            if sqlite3_column_type(statement, 15) != SQLITE_NULL {
                                let waveformData = String(cString: sqlite3_column_text(statement, 15))
                                rawData += ", Waveform: '\(waveformData.prefix(100))...'"
                                
                                if let data = waveformData.data(using: .utf8) {
                                    do {
                                        let decoder = JSONDecoder()
                                        let _ = try decoder.decode([Double].self, from: data)
                                        print("🔍 Waveform JSON is valid for track \(id)")
                                    } catch {
                                        print("🚨 JSON decode error for track \(id) waveform: \(error)")
                                        print("🚨 Raw waveform data (first 200 chars): '\(waveformData.prefix(200))'")
                                    }
                                }
                            }
                            
                            failedTracks.append((id: id, title: title, error: error.localizedDescription, rawData: rawData))
                            print("❌ Failed to parse track at row \(rowCount): \(error)")
                            print("❌ Track details - \(rawData)")
                        }
                    }
                    
                    // Log summary of failed tracks
                    if !failedTracks.isEmpty {
                        print("🚨 DATABASE LOADING ERRORS SUMMARY:")
                        print("🚨 Total tracks processed: \(rowCount)")
                        print("🚨 Successfully loaded: \(loadedTracks.count)")
                        print("🚨 Failed to load: \(failedTracks.count)")
                        print("🚨 Failed tracks details:")
                        for failed in failedTracks {
                            print("   - ID: \(failed.id), Title: '\(failed.title)'")
                            print("     Error: \(failed.error)")
                            print("     Raw data: \(failed.rawData)")
                            print("")
                        }
                    }
                    

                    
                    DispatchQueue.main.async {
                        self.tracks = loadedTracks.sorted()
                        self.isLoading = false
                    }
                    
                    print("✅ Loaded \(loadedTracks.count) tracks from database")
                    if !failedTracks.isEmpty {
                        print("⚠️  \(failedTracks.count) tracks failed to load due to metadata encoding issues")
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Filesystem Scan and Change Application
    struct MovedFileUpdate: Identifiable, Equatable {
        let id = UUID()
        let trackId: Int
        let oldPath: String
        let newPath: String
        let trackTitle: String
    }

    /// Recursively find audio files in a directory tree.
    private func findAudioFilesRecursively(in folder: String, into list: inout [String]) {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: folder)
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                do {
                    let res = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    if res.isRegularFile == true {
                        let ext = fileURL.pathExtension.lowercased()
                        if supportedExtensions.contains(ext) {
                            list.append(fileURL.path)
                        }
                    }
                } catch {
                    // Ignore unreadable entries
                }
            }
        }
    }

    /// Scans root folders vs DB and returns file system changes.
    func scanFilesystemChanges() async throws -> (newFiles: [String], deletedTracks: [Track], movedUpdates: [MovedFileUpdate]) {
        guard activeCollectionDefinition != nil else { return ([], [], []) }

        print("🔍 [Scan] Starting filesystem scan...")

        // Gather files on disk
        var filesOnDiskList: [String] = []
        let roots = getRootFolders()
        print("🔍 [Scan] Root folders: \(roots)")
        for root in roots {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue {
                print("🔍 [Scan] Scanning root: \(root)")
                findAudioFilesRecursively(in: root, into: &filesOnDiskList)
            }
        }
        print("🔍 [Scan] Found \(filesOnDiskList.count) files on disk")
        let normalizedDisk: Set<String> = Set(filesOnDiskList.map { ($0 as NSString).standardizingPath })
        print("🔍 [Scan] Normalized disk files: \(normalizedDisk.count)")

        // Get tracks in DB (use cached if available; otherwise load)
        var dbTracks: [Track] = tracks
        print("🔍 [Scan] Current tracks in memory: \(dbTracks.count)")
        if dbTracks.isEmpty {
            print("🔍 [Scan] No tracks in memory, loading from DB...")
            try await loadAllTracks()
            dbTracks = tracks
            print("🔍 [Scan] Loaded \(dbTracks.count) tracks from DB")
        }
        // Create dictionary from tracks, handling duplicates by keeping the first occurrence
        var dbByPath: [String: Track] = [:]
        for track in dbTracks {
            let norm = (track.path as NSString).standardizingPath
            if dbByPath[norm] == nil {
                dbByPath[norm] = track
            } else {
                print("⚠️ [Scan] Duplicate track found for path: \(norm)")
                print("⚠️ [Scan] Existing track ID: \(dbByPath[norm]?.id ?? -1), New track ID: \(track.id ?? -1)")
                // Keep the first occurrence, skip the duplicate
            }
        }
        print("🔍 [Scan] DB tracks by normalized path: \(dbByPath.count)")

        // Compute diffs
        var newDiskOnly: [String] = []
        var dbOnlyTracks: [Track] = []
        for p in normalizedDisk { if dbByPath[p] == nil { newDiskOnly.append(p) } }
        for (p, t) in dbByPath { if !normalizedDisk.contains(p) { dbOnlyTracks.append(t) } }
        print("🔍 [Scan] New files on disk: \(newDiskOnly.count)")
        print("🔍 [Scan] Missing files (in DB but not on disk): \(dbOnlyTracks.count)")

        // Detect moved files by filename match
        var moved: [MovedFileUpdate] = []
        
        // Convert absolute paths to relative paths for comparison
        let newByRelativePath: [String: String] = Dictionary(uniqueKeysWithValues: newDiskOnly.compactMap { absolutePath in
            let relativePath = self.convertToRelativePath(absolutePath)
            return (relativePath, absolutePath)
        })
        
        var trulyNew: [String] = []
        for missing in dbOnlyTracks {
            // Use the stored relative path from the database
            let missingRelativePath = missing.path
            if let newAbsolutePath = newByRelativePath[missingRelativePath], let id = missing.id {
                moved.append(MovedFileUpdate(trackId: id, oldPath: (missing.path as NSString).standardizingPath, newPath: newAbsolutePath, trackTitle: missing.title))
                // Note: We don't remove from newByRelativePath here since we're using relative paths as keys
            }
        }
        
        // Add all remaining new files as truly new
        trulyNew.append(contentsOf: newByRelativePath.values)
        print("🔍 [Scan] Moved files: \(moved.count)")
        print("🔍 [Scan] Truly new files: \(trulyNew.count)")

        let result = (trulyNew.sorted(), dbOnlyTracks, moved)
        print("🔍 [Scan] Final result - new: \(result.0.count), deleted: \(result.1.count), moved: \(result.2.count)")
        return result
    }

    /// Adds a local file to the database. Returns the inserted Track.
    func addLocalFile(at absolutePath: String) async throws -> Track {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return 
                    }
                    if self.isReadOnlyMode { 
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot add in read-only mode."))
                        return 
                    }

                    let fm = FileManager.default
                    guard fm.fileExists(atPath: absolutePath) else { 
                        continuation.resume(throwing: CollectionError.queryFailed(message: "File not found at path: \(absolutePath)"))
                        return 
                    }

                    // Compute duration and extract metadata via AVFoundation
                    let url = URL(fileURLWithPath: absolutePath)
                    let asset = AVURLAsset(url: url)
                    let durationSeconds = CMTimeGetSeconds(asset.duration)
                    let durationMs = durationSeconds.isFinite && durationSeconds > 0 ? Int(durationSeconds * 1000) : 0
                    let meta = self.extractAudioMetadata(from: asset)

                    // Let's first check the actual database schema to understand the column order
                    let schemaQuery = "PRAGMA table_info(\(self.tableMusic))"
                    var schemaStatement: OpaquePointer?
                    var columnOrder: [String] = []
                    
                    if sqlite3_prepare_v2(db, schemaQuery, -1, &schemaStatement, nil) == SQLITE_OK {
                        defer { sqlite3_finalize(schemaStatement) }
                        while sqlite3_step(schemaStatement) == SQLITE_ROW {
                            let columnName = String(cString: sqlite3_column_text(schemaStatement, 1))
                            columnOrder.append(columnName)
                        }
                    }
                    
                    print("🔍 [CollectionService] Database schema column order: \(columnOrder)")
                    
                    // Explicit INSERT with all relevant columns to ensure correct mapping
                    let insertSQL = """
                        INSERT INTO \(self.tableMusic) (
                            \(self.columnTitle), \(self.columnArtist), \(self.columnAlbum), \(self.columnAlbumArtist), \(self.columnComposer), \(self.columnGenre), \(self.columnYear), \(self.columnTrackNumber), \(self.columnDiscNumber), \(self.columnBpm), \(self.columnPath), \(self.columnIsUrl), \(self.columnDuration), \(self.columnTimeMarkers), \(self.columnWaveformData), \(self.columnRating), \(self.columnComment), \(self.columnGeneralTags), \(self.columnDateAdded)
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, '[]', NULL, 0, '', '[]', ?)
                    """
                    print("🔍 [CollectionService] addLocalFile - SQL: \(insertSQL)")
                    var stmt: OpaquePointer?
                    let prepareResult = sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil)
                    guard prepareResult == SQLITE_OK else {
                        let err = String(cString: sqlite3_errmsg(db))
                        print("❌ [CollectionService] SQL prepare failed with result \(prepareResult): \(err)")
                        continuation.resume(throwing: CollectionError.queryFailed(message: err))
                        return
                    }
                    defer { sqlite3_finalize(stmt) }
                    
                    // Bind basics
                    let filenameTitle = URL(fileURLWithPath: absolutePath).deletingPathExtension().lastPathComponent
                    let title = meta.title ?? filenameTitle
                    print("🔍 [CollectionService] addLocalFile - title: '\(title)', path: '\(absolutePath)'")
                    print("🔍 [CollectionService] addLocalFile - path length: \(absolutePath.count), isEmpty: \(absolutePath.isEmpty)")
                    
                    // Check if path is valid
                    guard !absolutePath.isEmpty else {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Path is empty"))
                        return
                    }
                    
                    // Normalize the path to handle any encoding issues
                    let normalizedPath = (absolutePath as NSString).standardizingPath
                    print("🔍 [CollectionService] addLocalFile - normalized path: '\(normalizedPath)'")
                    
                    // Verify the file still exists after normalization
                    guard fm.fileExists(atPath: normalizedPath) else {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "File not found after path normalization: \(normalizedPath)"))
                        return
                    }
                    
                    // Convert to relative path for storage (like existing tracks)
                    let relativePath = self.convertToRelativePath(normalizedPath)
                    print("🔍 [CollectionService] Converting to relative path: '\(relativePath)'")
                    
                    print("🔍 [CollectionService] Binding parameters:")
                    print("  - Parameter 1 (title): '\(title)'")
                    print("  - Parameter 2 (artist): '\(meta.artist ?? "Unknown")")
                    print("  - Parameter 3 (album): '\(meta.album ?? "Unknown")")
                    print("  - Parameter 4 (albumArtist): '\(meta.albumArtist ?? "")'")
                    print("  - Parameter 5 (composer): '\(meta.composer ?? "")'")
                    print("  - Parameter 6 (genre): '\(meta.genre ?? "")'")
                    print("  - Parameter 7 (year): \(meta.year ?? -1)")
                    print("  - Parameter 8 (trackNumber): \(meta.trackNumber ?? -1)")
                    print("  - Parameter 9 (discNumber): \(meta.discNumber ?? -1)")
                    print("  - Parameter 10 (bpm): \(meta.bpm ?? -1)")
                    print("  - Parameter 11 (path): '\(relativePath)'")
                    print("  - Parameter 12 (duration): \(durationMs)")
                    
                    // 1 title
                    title.withCString { sqlite3_bind_text(stmt, 1, $0, -1, self.SQLITE_TRANSIENT) }
                    // 2 artist
                    if let v = meta.artist { v.withCString { sqlite3_bind_text(stmt, 2, $0, -1, self.SQLITE_TRANSIENT) } } else { "Unknown".withCString { sqlite3_bind_text(stmt, 2, $0, -1, self.SQLITE_TRANSIENT) } }
                    // 3 album
                    if let v = meta.album { v.withCString { sqlite3_bind_text(stmt, 3, $0, -1, self.SQLITE_TRANSIENT) } } else { "Unknown".withCString { sqlite3_bind_text(stmt, 3, $0, -1, self.SQLITE_TRANSIENT) } }
                    // 4 albumArtist
                    if let v = meta.albumArtist { v.withCString { sqlite3_bind_text(stmt, 4, $0, -1, self.SQLITE_TRANSIENT) } } else { sqlite3_bind_null(stmt, 4) }
                    // 5 composer
                    if let v = meta.composer { v.withCString { sqlite3_bind_text(stmt, 5, $0, -1, self.SQLITE_TRANSIENT) } } else { sqlite3_bind_null(stmt, 5) }
                    // 6 genre
                    if let v = meta.genre { v.withCString { sqlite3_bind_text(stmt, 6, $0, -1, self.SQLITE_TRANSIENT) } } else { sqlite3_bind_null(stmt, 6) }
                    // 7 year
                    if let v = meta.year { sqlite3_bind_int(stmt, 7, Int32(v)) } else { sqlite3_bind_null(stmt, 7) }
                    // 8 trackNumber
                    if let v = meta.trackNumber { sqlite3_bind_int(stmt, 8, Int32(v)) } else { sqlite3_bind_null(stmt, 8) }
                    // 9 discNumber
                    if let v = meta.discNumber { sqlite3_bind_int(stmt, 9, Int32(v)) } else { sqlite3_bind_null(stmt, 9) }
                    // 10 bpm
                    if let v = meta.bpm { sqlite3_bind_int(stmt, 10, Int32(v)) } else { sqlite3_bind_null(stmt, 10) }
                    // 11 path
                    relativePath.withCString { sqlite3_bind_text(stmt, 11, $0, -1, self.SQLITE_TRANSIENT) }
                    // 12 duration
                    sqlite3_bind_int(stmt, 12, Int32(durationMs))
                    // 13 dateAdded
                    let currentDate = ISO8601DateFormatter().string(from: Date())
                    currentDate.withCString { sqlite3_bind_text(stmt, 13, $0, -1, self.SQLITE_TRANSIENT) }

                    let stepResult = sqlite3_step(stmt)
                    guard stepResult == SQLITE_DONE else {
                        let err = String(cString: sqlite3_errmsg(db))
                        print("❌ [CollectionService] SQL step failed with result \(stepResult): \(err)")
                        continuation.resume(throwing: CollectionError.queryFailed(message: err))
                        return
                    }
                    let newId = Int(sqlite3_last_insert_rowid(db))
                    
                    // Verify the insertion by reading back the track
                    let verifySQL = "SELECT * FROM \(self.tableMusic) WHERE \(self.columnId) = ?"
                    var verifyStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, verifySQL, -1, &verifyStmt, nil) == SQLITE_OK {
                        defer { sqlite3_finalize(verifyStmt) }
                        sqlite3_bind_int(verifyStmt, 1, Int32(newId))
                        if sqlite3_step(verifyStmt) == SQLITE_ROW {
                            let storedTitle = String(cString: sqlite3_column_text(verifyStmt, 1))
                            let storedArtist = String(cString: sqlite3_column_text(verifyStmt, 2))
                            let storedAlbum = String(cString: sqlite3_column_text(verifyStmt, 3))
                            let storedPath = String(cString: sqlite3_column_text(verifyStmt, 11))
                            print("🔍 [CollectionService] Verification - stored data for ID \(newId):")
                            print("  - Title: '\(storedTitle)'")
                            print("  - Artist: '\(storedArtist)'")
                            print("  - Album: '\(storedAlbum)'")
                            print("  - Path: '\(storedPath)'")
                            if storedPath != relativePath {
                                print("❌ [CollectionService] PATH MISMATCH! Expected: '\(relativePath)', Stored: '\(storedPath)'")
                            }
                        }
                    }

                    let inserted = Track(
                        id: newId,
                        title: title,
                        artist: meta.artist ?? "Unknown",
                        album: meta.album ?? "Unknown",
                        albumArtist: meta.albumArtist,
                        composer: meta.composer,
                        genre: meta.genre,
                        year: meta.year,
                        trackNumber: meta.trackNumber,
                        discNumber: meta.discNumber,
                        bpm: meta.bpm,
                        path: relativePath,
                        isUrl: false,
                        duration: durationMs,
                        timeMarkers: [],
                        waveformData: nil,
                        rating: 0,
                        comment: "",
                        generalTags: [],
                        dateAdded: Date()
                    )
                    // Queue waveform processing
                    self.pendingWaveformTrackIds.append(newId)
                    continuation.resume(returning: inserted)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Recursively import all audio files under a root folder into the current database.
    func importAllAudioFilesUnderRoot(rootFolderPath: String) async throws {
        print("[Import] Starting import under root: \(rootFolderPath)")
        guard let _ = database else { throw CollectionError.databaseNotOpen }
        var files: [String] = []
        findAudioFilesRecursively(in: rootFolderPath, into: &files)
        print("[Import] Found \(files.count) audio files")
        for p in files.sorted() {
            do {
                print("[Import] Adding: \(p)")
                _ = try await addLocalFile(at: p)
            } catch {
                print("[Import] Failed to add \(p): \(error)")
            }
        }
        print("[Import] Import complete")
    }

    // MARK: - Metadata Extraction
    private func extractAudioMetadata(from asset: AVURLAsset) -> (title: String?, artist: String?, album: String?, albumArtist: String?, composer: String?, genre: String?, year: Int?, trackNumber: Int?, discNumber: Int?, bpm: Int?) {
        var title: String?
        var artist: String?
        var album: String?
        var albumArtist: String?
        var composer: String?
        var genre: String?
        var year: Int?
        var trackNumber: Int?
        var discNumber: Int?
        var bpm: Int?

        // Common metadata
        for item in asset.commonMetadata {
            guard let key = item.commonKey?.rawValue else { continue }
            switch key {
            case "title":
                title = item.stringValue ?? title
            case "artist":
                artist = item.stringValue ?? artist
            case "albumName":
                album = item.stringValue ?? album
            case "composer":
                composer = item.stringValue ?? composer
            case "genre":
                genre = item.stringValue ?? genre
            default:
                break
            }
        }

        func parseInt(_ value: String?) -> Int? {
            guard let v = value else { return nil }
            // Supports formats like "5/12"
            let parts = v.split(separator: "/")
            if let first = parts.first, let n = Int(first.trimmingCharacters(in: .whitespaces)) { return n }
            return Int(v.trimmingCharacters(in: .whitespaces))
        }

        // ID3 metadata
        for item in asset.metadata(forFormat: .id3Metadata) {
            guard let id = item.identifier?.rawValue.lowercased() else { continue }
            let str = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.contains("albumartist") || id.contains("band") { albumArtist = str ?? albumArtist }
            if id.contains("year") || id.contains("date") { year = year ?? parseInt(str) }
            if id.contains("tracknumber") || id.contains("track") { trackNumber = trackNumber ?? parseInt(str) }
            if id.contains("discnumber") || id.contains("partofset") { discNumber = discNumber ?? parseInt(str) }
            if id.contains("beatspermin") || id.contains("bpm") { bpm = bpm ?? parseInt(str) }
        }

        // iTunes metadata
        for item in asset.metadata(forFormat: .iTunesMetadata) {
            guard let id = item.identifier?.rawValue.lowercased() else { continue }
            let str = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.contains("albumartist") { albumArtist = str ?? albumArtist }
            if id.contains("year") || id.contains("release") { year = year ?? parseInt(str) }
            if id.contains("tracknumber") { trackNumber = trackNumber ?? parseInt(str) }
            if id.contains("discnumber") { discNumber = discNumber ?? parseInt(str) }
            if id.contains("beatspermin") || id.contains("bpm") { bpm = bpm ?? parseInt(str) }
        }

        return (title, artist, album, albumArtist, composer, genre, year, trackNumber, discNumber, bpm)
    }

    func deleteTrack(_ id: Int) throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        if isReadOnlyMode { throw CollectionError.queryFailed(message: "Cannot delete in read-only mode.") }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM \(tableMusic) WHERE \(columnId) = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: err)
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(id))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let err = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: err)
        }
    }

    func updateTrackPath(trackId: Int, newPath: String) throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        if isReadOnlyMode { throw CollectionError.queryFailed(message: "Cannot update in read-only mode.") }
        var stmt: OpaquePointer?
        let sql = "UPDATE \(tableMusic) SET \(columnPath) = ? WHERE \(columnId) = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: err)
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, newPath, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(trackId))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let err = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: err)
        }
    }

    /// Apply selected filesystem changes and refresh in-memory tracks
    func applyFilesystemChanges(newFiles: [String], deletedTrackIds: [Int], movedUpdates: [MovedFileUpdate]) async throws {
        print("🔍 [CollectionService] applyFilesystemChanges called - newFiles: \(newFiles.count), deletedTrackIds: \(deletedTrackIds.count), movedUpdates: \(movedUpdates.count)")
        
        // Apply moved updates first to preserve IDs
        for upd in movedUpdates {
            print("🔍 [CollectionService] Updating track path: \(upd.trackId) -> \(upd.newPath)")
            try updateTrackPath(trackId: upd.trackId, newPath: upd.newPath)
        }
        
        // Delete tracks
        for id in deletedTrackIds {
            print("🔍 [CollectionService] Deleting track: \(id)")
            try deleteTrack(id)
        }
        
        // Add new files
        for p in newFiles {
            print("🔍 [CollectionService] Adding new file: \(p)")
            _ = try await addLocalFile(at: p)
        }
        
        print("🔍 [CollectionService] Reloading all tracks...")
        try await loadAllTracks()
        print("🔍 [CollectionService] Filesystem changes applied successfully")
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
        
        // Parse time markers with enhanced error handling
        let timeMarkers: [TimeMarker]
        if sqlite3_column_type(statement, 14) != SQLITE_NULL {
            let markersJson = String(cString: sqlite3_column_text(statement, 14))
            do {
                timeMarkers = try parseTimeMarkers(from: markersJson)
            } catch {
                print("🚨 Failed to parse time markers for track \(id): \(error)")
                print("🚨 Raw markers data: '\(markersJson)'")
                throw CollectionError.invalidData
            }
        } else {
            timeMarkers = []
        }
        
        // Parse waveform data with enhanced error handling
        let waveformData: [Double]?
        if sqlite3_column_type(statement, 15) != SQLITE_NULL {
            let waveformJson = String(cString: sqlite3_column_text(statement, 15))
            do {
                waveformData = try parseWaveformData(from: waveformJson)
            } catch {
                print("🚨 Failed to parse waveform data for track \(id): \(error)")
                print("🚨 Raw waveform data (first 200 chars): '\(waveformJson.prefix(200))'")
                throw CollectionError.invalidData
            }
        } else {
            waveformData = nil
        }
        
        let rating = Int(sqlite3_column_int(statement, 16))
        let comment = sqlite3_column_type(statement, 17) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 17)) : ""
        
        // Parse general tags with enhanced error handling
        let generalTags: [String]
        if sqlite3_column_type(statement, 18) != SQLITE_NULL {
            let tagsJson = String(cString: sqlite3_column_text(statement, 18))
            do {
                generalTags = try parseGeneralTags(from: tagsJson)
            } catch {
                print("🚨 Failed to parse general tags for track \(id): \(error)")
                print("🚨 Raw tags data: '\(tagsJson)'")
                print("🚨 Tags data length: \(tagsJson.count) characters")
                
                // Try to identify the specific encoding issue
                if let data = tagsJson.data(using: .utf8) {
                    print("🚨 UTF-8 data length: \(data.count) bytes")
                } else {
                    print("🚨 Cannot convert tags to UTF-8 data")
                }
                
                // Try alternative encodings
                if let dataUTF16 = tagsJson.data(using: .utf16) {
                    print("🚨 UTF-16 data length: \(dataUTF16.count) bytes")
                }
                if let dataASCII = tagsJson.data(using: .ascii) {
                    print("🚨 ASCII data length: \(dataASCII.count) bytes")
                }
                
                throw CollectionError.invalidData
            }
        } else {
            generalTags = []
        }
        
        // Parse dateAdded with fallback to a reasonable default date for existing tracks
        let dateAdded: Date
        if sqlite3_column_type(statement, 19) != SQLITE_NULL {
            let dateString = String(cString: sqlite3_column_text(statement, 19))
            if let parsedDate = ISO8601DateFormatter().date(from: dateString) {
                dateAdded = parsedDate
            } else {
                // Use a fallback date instead of current date to avoid showing current time
                dateAdded = Date().addingTimeInterval(-86400 * 30) // 30 days ago as fallback
            }
        } else {
            // Use a fallback date instead of current date to avoid showing current time
            dateAdded = Date().addingTimeInterval(-86400 * 30) // 30 days ago as fallback
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
            generalTags: generalTags,
            dateAdded: dateAdded
        )
    }
    
    private func parseTimeMarkers(from jsonString: String) throws -> [TimeMarker] {
        // Handle edge cases first
        let trimmedString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty or just whitespace, return empty array
        if trimmedString.isEmpty {
            print("🔧 Empty time markers data, returning empty array")
            return []
        }
        
        // Clean up control characters that might be present
        let cleanedString = trimmedString.filter { char in
            // Allow printable characters, spaces, and common JSON characters
            // ASCII values 32-126 are printable characters
            if let asciiValue = char.asciiValue {
                return asciiValue >= 32 && asciiValue <= 126
            }
            return false
        }
        
        if cleanedString != trimmedString {
            print("🔧 Cleaned time markers data from '\(trimmedString)' to '\(cleanedString)'")
        }
        
        // If after cleaning we have an empty string, return empty array
        if cleanedString.isEmpty {
            print("🔧 Time markers data became empty after cleaning, returning empty array")
            return []
        }
        
        guard let data = cleanedString.data(using: .utf8) else {
            print("🚨 Cannot convert cleaned time markers JSON string to UTF-8 data")
            print("🚨 Original string: '\(jsonString)'")
            print("🚨 Cleaned string: '\(cleanedString)'")
            throw CollectionError.invalidData
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([TimeMarker].self, from: data)
        } catch {
            print("🚨 JSON decode error for time markers: \(error)")
            print("🚨 Original JSON string: '\(jsonString)'")
            print("🚨 Cleaned JSON string: '\(cleanedString)'")
            print("🚨 Data length: \(data.count) bytes")
            
            // Try to identify the specific JSON parsing issue
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                print("🚨 JSON is valid but not an array: \(type(of: jsonObject))")
            }
            
            throw error
        }
    }
    
    private func parseWaveformData(from jsonString: String) throws -> [Double] {
        // Handle edge cases first
        let trimmedString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty or just whitespace, return empty array
        if trimmedString.isEmpty {
            print("🔧 Empty waveform data, returning empty array")
            return []
        }
        
        // Check if the data looks like it might be corrupted (contains non-JSON text)
        if trimmedString.contains("Unknown") || trimmedString.contains(".mp3") || trimmedString.contains("music") {
             print("🚨 Waveform data appears to be corrupted (contains metadata text)")
            print("🚨 Corrupted data (first 200 chars): '\(trimmedString.prefix(200))'")
            // Try to recover by extracting the JSON array substring
            if let startIdx = trimmedString.firstIndex(of: "["), let endIdx = trimmedString.lastIndex(of: "]"), startIdx < endIdx {
                let jsonSlice = String(trimmedString[startIdx...endIdx])
                if let data = jsonSlice.data(using: .utf8), let decoded = try? JSONDecoder().decode([Double].self, from: data) {
                    print("🔧 Recovered waveform array from corrupted field (length=\(decoded.count))")
                    return decoded
                } else {
                    print("🚨 Failed to recover waveform array from corrupted field")
                }
            }
            // Fall back to empty array to trigger regeneration
            return []
        }
        
        // Clean up control characters that might be present
        let cleanedString = trimmedString.filter { char in
            // Allow printable characters, spaces, and common JSON characters
            // ASCII values 32-126 are printable characters
            if let asciiValue = char.asciiValue {
                return asciiValue >= 32 && asciiValue <= 126
            }
            return false
        }
        
        if cleanedString != trimmedString {
            print("🔧 Cleaned waveform data from '\(trimmedString.prefix(100))' to '\(cleanedString.prefix(100))'")
        }
        
        // If after cleaning we have an empty string, return empty array
        if cleanedString.isEmpty {
            print("🔧 Waveform data became empty after cleaning, returning empty array")
            return []
        }
        
        guard let data = cleanedString.data(using: .utf8) else {
            print("🚨 Cannot convert cleaned waveform JSON string to UTF-8 data")
            print("🚨 Original string (first 200 chars): '\(jsonString.prefix(200))'")
            print("🚨 Cleaned string (first 200 chars): '\(cleanedString.prefix(200))'")
            throw CollectionError.invalidData
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([Double].self, from: data)
        } catch {
            print("🚨 JSON decode error for waveform data: \(error)")
            print("🚨 Original JSON string (first 200 chars): '\(jsonString.prefix(200))'")
            print("🚨 Cleaned JSON string (first 200 chars): '\(cleanedString.prefix(200))'")
            print("🚨 Data length: \(data.count) bytes")
            
            // Try to identify the specific JSON parsing issue
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                print("🚨 JSON is valid but not an array: \(type(of: jsonObject))")
            }
            
            // Instead of throwing an error, return empty array for corrupted data
            print("🔧 Returning empty array for corrupted waveform data")
            return []
        }
    }
    
    private func parseGeneralTags(from jsonString: String) throws -> [String] {
        // Handle edge cases first
        let trimmedString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty or just whitespace, return empty array
        if trimmedString.isEmpty {
            print("🔧 Empty tags data, returning empty array")
            return []
        }
        
        // Clean up control characters that might be present
        let cleanedString = trimmedString.filter { char in
            // Allow printable characters, spaces, and common JSON characters
            // ASCII values 32-126 are printable characters
            if let asciiValue = char.asciiValue {
                return asciiValue >= 32 && asciiValue <= 126
            }
            return false
        }
        
        if cleanedString != trimmedString {
            print("🔧 Cleaned tags data from '\(trimmedString)' to '\(cleanedString)'")
        }
        
        // If after cleaning we have an empty string, return empty array
        if cleanedString.isEmpty {
            print("🔧 Tags data became empty after cleaning, returning empty array")
            return []
        }
        
        guard let data = cleanedString.data(using: .utf8) else {
            print("🚨 Cannot convert cleaned tags JSON string to UTF-8 data")
            print("🚨 Original string: '\(jsonString)'")
            print("🚨 Cleaned string: '\(cleanedString)'")
            throw CollectionError.invalidData
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([String].self, from: data)
        } catch {
            print("🚨 JSON decode error for tags: \(error)")
            print("🚨 Original JSON string: '\(jsonString)'")
            print("🚨 Cleaned JSON string: '\(cleanedString)'")
            print("🚨 Data length: \(data.count) bytes")
            
            // Try to identify the specific JSON parsing issue
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                print("🚨 JSON is valid but not an array: \(type(of: jsonObject))")
            }
            
            // As a last resort, try to parse as a simple comma-separated string
            if cleanedString.hasPrefix("[") && cleanedString.hasSuffix("]") {
                let content = String(cleanedString.dropFirst().dropLast())
                let tags = content.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map { tag in
                        // Remove quotes if present
                        if tag.hasPrefix("\"") && tag.hasSuffix("\"") {
                            return String(tag.dropFirst().dropLast())
                        }
                        return tag
                    }
                print("🔧 Fallback parsing successful, found tags: \(tags)")
                return tags
            }
            
            throw error
        }
    }
    
    // MARK: - Path Resolution
    func resolveTrackPathForWaveform(_ track: Track) -> String {
        
        // Ensure security access for file operations
        let securityAccess = ensureSecurityAccess()
        defer { if securityAccess { stopSecurityAccess() } }
        
        guard let definition = activeCollectionDefinition,
              !track.isUrl else {
            print("   ⚠️ Skipping path resolution (no definition or is URL)")
            return track.path
        }
        
        // Check if the path is already absolute (starts with /)
        if track.path.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: track.path) {
                return track.path
            } else {
                print("   ❌ File does not exist at absolute path: \(track.path)")
                
                // Try to find the file by filename in root folders
                let filename = URL(fileURLWithPath: track.path).lastPathComponent
                print("   🔍 Trying to find file by filename: \(filename)")
                
                for (index, rootFolder) in localCollectionRootFolders.enumerated() {
                    let candidatePath = (rootFolder as NSString).appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: candidatePath) {
                        return candidatePath
                    }
                }
                
                // Also try searching recursively in the root folders
                for (index, rootFolder) in localCollectionRootFolders.enumerated() {
                    print("   🔍 Searching recursively in folder \(index + 1): \(rootFolder)")
                    if let foundPath = findFileRecursively(filename: filename, in: rootFolder) {
                        print("   ✅ Found file recursively at: \(foundPath)")
                        return foundPath
                    }
                }
                
                print("   ❌ File not found by filename or recursive search")
            }
        }
        
        var absolutePath: String
        
        switch definition.type {
        case .shared:
            guard let rootPath = definition.rootPath else {
                print("   ⚠️ No root path for shared collection")
                return track.path
            }
            absolutePath = (rootPath as NSString).appendingPathComponent(track.path)
            print("   📁 Shared collection resolved path: \(absolutePath)")
            
        case .local:
            // For local collections, try to find the file in any of the root folders
            var foundPath = false
            absolutePath = "" // Initialize with empty string
            
            for (index, rootFolder) in localCollectionRootFolders.enumerated() {
                let candidatePath = (rootFolder as NSString).appendingPathComponent(track.path)
                if FileManager.default.fileExists(atPath: candidatePath) {
                    absolutePath = candidatePath
                    foundPath = true
                    break
                }
            }
            // If not found in any root folder, use the first root folder as fallback
            if localCollectionRootFolders.isEmpty {
                print("   ⚠️ No root folders available")
                return track.path
            }
            if !foundPath {
                absolutePath = (localCollectionRootFolders[0] as NSString).appendingPathComponent(track.path)
                print("   📁 Using fallback path: \(absolutePath)")
            }
        }
        
        return absolutePath
    }
    
    private func findFileRecursively(filename: String, in folder: String) -> String? {
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: folder)
            
            // Check if the file is directly in this folder
            if contents.contains(filename) {
                return (folder as NSString).appendingPathComponent(filename)
            }
            
            // Search in subdirectories
            for item in contents {
                let itemPath = (folder as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false
                
                if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                    if let foundPath = findFileRecursively(filename: filename, in: itemPath) {
                        return foundPath
                    }
                }
            }
        } catch {
            print("   ⚠️ Error searching in folder \(folder): \(error)")
        }
        
        return nil
    }
    
    private func resolveTrackPath(_ track: Track) -> Track {
        let resolvedPath = resolveTrackPathForWaveform(track)
        
        let resolvedTrack = Track(
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
            path: resolvedPath,
            isUrl: track.isUrl,
            duration: track.duration,
            timeMarkers: track.timeMarkers,
            waveformData: track.waveformData,
            rating: track.rating,
            comment: track.comment,
            generalTags: track.generalTags,
            dateAdded: track.dateAdded
        )
        
        return resolvedTrack
    }
    
    // MARK: - Utility Methods
    
    /// Converts an absolute path to a relative path based on the collection's root folders
    private func convertToRelativePath(_ absolutePath: String) -> String {
        let normalizedPath = (absolutePath as NSString).standardizingPath
        
        // For local collections, try to find the file in any of the root folders
        for rootFolder in localCollectionRootFolders {
            if normalizedPath.hasPrefix(rootFolder) {
                let relative = String(normalizedPath.dropFirst(rootFolder.count + 1)) // +1 for the slash
                return relative
            }
        }
        
        // For shared collections, use the root path
        if let definition = activeCollectionDefinition, definition.type == .shared, let rootPath = definition.rootPath {
            if normalizedPath.hasPrefix(rootPath) {
                let relative = String(normalizedPath.dropFirst(rootPath.count + 1)) // +1 for the slash
                return relative
            }
        }
        
        // If no root folder matches, return the normalized path as-is
        return normalizedPath
    }
    
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
            SELECT \(selectTrackColumns) FROM \(tableMusic)
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
    
    /// Get tracks sorted by date added (newest first)
    func getTracksSortedByDateAdded() -> [Track] {
        return tracks.sorted { $0.dateAdded > $1.dateAdded }
    }
    
    /// Get tracks sorted by date added (oldest first)
    func getTracksSortedByDateAddedOldestFirst() -> [Track] {
        return tracks.sorted { $0.dateAdded < $1.dateAdded }
    }
    
    // MARK: - Track Updates
    func updateTrackWaveformData(trackId: Int, waveformData: [Double]) async throws {
        print("[CollectionService] 💾 Updating waveform data for track \(trackId), data size: \(waveformData.count)")
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    // Ensure security access for database operations
                    let securityAccess = self.ensureSecurityAccess()
                    defer { if securityAccess { self.stopSecurityAccess() } }
                    
                    guard let db = self.database else { 
                        print("[CollectionService] ❌ Database not open")
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    if self.isReadOnlyMode { 
                        print("[CollectionService] ❌ Database in read-only mode")
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot update waveform in read-only mode."))
                        return
                    }

                    print("[CollectionService] 🔧 Setting journal mode to DELETE")
                    _ = sqlite3_exec(db, "PRAGMA journal_mode = DELETE", nil, nil, nil)

                    let encoder = JSONEncoder()
                    let data = try encoder.encode(waveformData)
                    let json = String(data: data, encoding: .utf8) ?? "[]"
                    print("[CollectionService] 📝 Encoded waveform data to JSON, length: \(json.count)")

                    let sql = "UPDATE \(self.tableMusic) SET \(self.columnWaveformData) = ? WHERE \(self.columnId) = ?"
                    print("[CollectionService] 🔍 Executing SQL: \(sql)")
                    
                    var statement: OpaquePointer?
                    let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    if result != SQLITE_OK { 
                        let errorMsg = String(cString: sqlite3_errmsg(db))
                        print("[CollectionService] ❌ SQL prepare failed: \(errorMsg)")
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMsg))
                        return
                    }
                    
                    print("[CollectionService] 🔗 Binding parameters...")
                    sqlite3_bind_text(statement, 1, json, -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_int(statement, 2, Int32(trackId))
                    
                    print("[CollectionService] ▶️ Executing statement...")
                    let stepResult = sqlite3_step(statement)
                    if stepResult != SQLITE_DONE {
                        let errorMsg = String(cString: sqlite3_errmsg(db))
                        print("[CollectionService] ❌ SQL execution failed: \(errorMsg)")
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMsg))
                        return
                    }
                    print("[CollectionService] ✅ SQL execution successful")

                    // Verify what was written by reading back the value
                    let verifySQL = "SELECT \(self.columnWaveformData) FROM \(self.tableMusic) WHERE \(self.columnId) = ?"
                    var verifyStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, verifySQL, -1, &verifyStmt, nil) == SQLITE_OK {
                        sqlite3_bind_int(verifyStmt, 1, Int32(trackId))
                        if sqlite3_step(verifyStmt) == SQLITE_ROW {
                            if let ptr = sqlite3_column_text(verifyStmt, 0) {
                                let saved = String(cString: ptr)
                                print("[CollectionService] 🔎 Read-back waveform JSON length=\(saved.count), prefix='\(saved.prefix(80))'")
                            } else {
                                print("[CollectionService] 🔎 Read-back waveform JSON is NULL")
                            }
                        } else {
                            print("[CollectionService] 🔎 Read-back step failed for track \(trackId)")
                        }
                        sqlite3_finalize(verifyStmt)
                    } else {
                        let err = String(cString: sqlite3_errmsg(db))
                        print("[CollectionService] 🔎 Read-back prepare failed: \(err)")
                    }

                    // Update the track in the local array on the main thread
                    Task { @MainActor in
                        print("[CollectionService] 🔄 Updating tracks array on main thread...")
                        if let index = self.tracks.firstIndex(where: { $0.id == trackId }) {
                            // Create a completely new array to force SwiftUI to refresh
                            var newTracks = self.tracks
                            newTracks[index] = Track(
                                id: self.tracks[index].id,
                                title: self.tracks[index].title,
                                artist: self.tracks[index].artist,
                                album: self.tracks[index].album,
                                albumArtist: self.tracks[index].albumArtist,
                                composer: self.tracks[index].composer,
                                genre: self.tracks[index].genre,
                                year: self.tracks[index].year,
                                trackNumber: self.tracks[index].trackNumber,
                                discNumber: self.tracks[index].discNumber,
                                bpm: self.tracks[index].bpm,
                                path: self.tracks[index].path,
                                isUrl: self.tracks[index].isUrl,
                                duration: self.tracks[index].duration,
                                timeMarkers: self.tracks[index].timeMarkers,
                                waveformData: waveformData,
                                rating: self.tracks[index].rating,
                                comment: self.tracks[index].comment,
                                generalTags: self.tracks[index].generalTags,
                                dateAdded: self.tracks[index].dateAdded
                            )
                            
                            // Replace the entire array to force SwiftUI refresh
                            self.tracks = newTracks
                            print("[CollectionService] ✅ Successfully updated tracks array for track \(trackId)")
                            
                            // Force a UI refresh
                            self.objectWillChange.send()
                        } else {
                            print("[CollectionService] ⚠️ Track \(trackId) not found in tracks array")
                        }
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    func updateTrackRating(trackId: Int, newRating: Int) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else {
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    
                    if self.isReadOnlyMode {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot update ratings in read-only mode. Please ensure the database file is writable."))
                        return
                    }
                    
                    // First, ensure we're using DELETE journal mode to avoid permission issues
                    let journalResult = sqlite3_exec(db, "PRAGMA journal_mode = DELETE", nil, nil, nil)
                    if journalResult != SQLITE_OK {
                        print("Warning: Could not set journal mode to DELETE for update operation")
                    }
                    
                    let query = "UPDATE \(self.tableMusic) SET \(self.columnRating) = ? WHERE \(self.columnId) = ?"
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    // Bind parameters
                    sqlite3_bind_int(statement, 1, Int32(newRating))
                    sqlite3_bind_int(statement, 2, Int32(trackId))
                    
                    let stepResult = sqlite3_step(statement)
                    if stepResult != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    // Update the track in the local array on the main thread
                    Task { @MainActor in
                        if let index = self.tracks.firstIndex(where: { $0.id == trackId }) {
                            var updatedTracks = self.tracks
                            updatedTracks[index] = Track(
                                id: self.tracks[index].id,
                                title: self.tracks[index].title,
                                artist: self.tracks[index].artist,
                                album: self.tracks[index].album,
                                albumArtist: self.tracks[index].albumArtist,
                                composer: self.tracks[index].composer,
                                genre: self.tracks[index].genre,
                                year: self.tracks[index].year,
                                trackNumber: self.tracks[index].trackNumber,
                                discNumber: self.tracks[index].discNumber,
                                bpm: self.tracks[index].bpm,
                                path: self.tracks[index].path,
                                isUrl: self.tracks[index].isUrl,
                                duration: self.tracks[index].duration,
                                timeMarkers: self.tracks[index].timeMarkers,
                                waveformData: self.tracks[index].waveformData,
                                rating: newRating,
                                comment: self.tracks[index].comment,
                                generalTags: self.tracks[index].generalTags,
                                dateAdded: self.tracks[index].dateAdded
                            )
                            self.tracks = updatedTracks
                        }
                    }
                    
                    print("Updated rating for track \(trackId) to \(newRating)")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func updateTrackMetadata(trackId: Int, updates: [String: Any]) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else {
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    
                    if self.isReadOnlyMode {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot update metadata in read-only mode. Please ensure the database file is writable."))
                        return
                    }
                    
                    // First, ensure we're using DELETE journal mode to avoid permission issues
                    let journalResult = sqlite3_exec(db, "PRAGMA journal_mode = DELETE", nil, nil, nil)
                    if journalResult != SQLITE_OK {
                        print("Warning: Could not set journal mode to DELETE for update operation")
                    }
                    
                    // Build dynamic UPDATE query based on provided updates
                    var setClauses: [String] = []
                    var parameters: [Any] = []
                    
                    for (key, value) in updates {
                        switch key {
                        case "title":
                            setClauses.append("\(self.columnTitle) = ?")
                            parameters.append(value as? String ?? "")
                        case "artist":
                            setClauses.append("\(self.columnArtist) = ?")
                            parameters.append(value as? String ?? "")
                        case "album":
                            setClauses.append("\(self.columnAlbum) = ?")
                            parameters.append(value as? String ?? "")
                        case "albumArtist":
                            setClauses.append("\(self.columnAlbumArtist) = ?")
                            parameters.append(value as? String)
                        case "composer":
                            setClauses.append("\(self.columnComposer) = ?")
                            parameters.append(value as? String)
                        case "genre":
                            setClauses.append("\(self.columnGenre) = ?")
                            parameters.append(value as? String)
                        case "year":
                            setClauses.append("\(self.columnYear) = ?")
                            parameters.append(value as? Int)
                        case "trackNumber":
                            setClauses.append("\(self.columnTrackNumber) = ?")
                            parameters.append(value as? Int)
                        case "discNumber":
                            setClauses.append("\(self.columnDiscNumber) = ?")
                            parameters.append(value as? Int)
                        case "bpm":
                            setClauses.append("\(self.columnBpm) = ?")
                            parameters.append(value as? Int)
                        case "comment":
                            setClauses.append("\(self.columnComment) = ?")
                            parameters.append(value as? String ?? "")
                        case "generalTags":
                            if let tags = value as? [String] {
                                setClauses.append("\(self.columnGeneralTags) = ?")
                                parameters.append(tags.joined(separator: ","))
                            }
                        default:
                            print("Warning: Unknown metadata field '\(key)' ignored")
                            continue
                        }
                    }
                    
                    guard !setClauses.isEmpty else {
                        continuation.resume()
                        return
                    }
                    
                    let query = "UPDATE \(self.tableMusic) SET \(setClauses.joined(separator: ", ")) WHERE \(self.columnId) = ?"
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    // Bind parameters
                    for (index, parameter) in parameters.enumerated() {
                        let bindIndex = Int32(index + 1)
                        if let stringValue = parameter as? String {
                            sqlite3_bind_text(statement, bindIndex, (stringValue as NSString).utf8String, -1, nil)
                        } else if let intValue = parameter as? Int {
                            sqlite3_bind_int(statement, bindIndex, Int32(intValue))
                        } else if parameter is NSNull {
                            sqlite3_bind_null(statement, bindIndex)
                        }
                    }
                    
                    // Bind track ID
                    sqlite3_bind_int(statement, Int32(parameters.count + 1), Int32(trackId))
                    
                    let stepResult = sqlite3_step(statement)
                    if stepResult != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    // Update the track in the local array on the main thread
                    Task { @MainActor in
                        if let index = self.tracks.firstIndex(where: { $0.id == trackId }) {
                            var updatedTracks = self.tracks
                            let currentTrack = self.tracks[index]
                            
                            updatedTracks[index] = Track(
                                id: currentTrack.id,
                                title: updates["title"] as? String ?? currentTrack.title,
                                artist: updates["artist"] as? String ?? currentTrack.artist,
                                album: updates["album"] as? String ?? currentTrack.album,
                                albumArtist: updates["albumArtist"] as? String ?? currentTrack.albumArtist,
                                composer: updates["composer"] as? String ?? currentTrack.composer,
                                genre: updates["genre"] as? String ?? currentTrack.genre,
                                year: updates["year"] as? Int ?? currentTrack.year,
                                trackNumber: updates["trackNumber"] as? Int ?? currentTrack.trackNumber,
                                discNumber: updates["discNumber"] as? Int ?? currentTrack.discNumber,
                                bpm: updates["bpm"] as? Int ?? currentTrack.bpm,
                                path: currentTrack.path,
                                isUrl: currentTrack.isUrl,
                                duration: currentTrack.duration,
                                timeMarkers: currentTrack.timeMarkers,
                                waveformData: currentTrack.waveformData,
                                rating: currentTrack.rating,
                                comment: updates["comment"] as? String ?? currentTrack.comment,
                                generalTags: updates["generalTags"] as? [String] ?? currentTrack.generalTags,
                                dateAdded: currentTrack.dateAdded
                            )
                            self.tracks = updatedTracks
                        }
                    }
                    
                    print("Updated metadata for track \(trackId) with updates: \(updates)")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Global Tags Persistence
    func loadGlobalTags() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }

                    // 1) Try to load from ui_settings
                    var statement: OpaquePointer?
                    let selectSQL = "SELECT value FROM \(self.tableUiSettings) WHERE key = ?"
                    if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    defer { sqlite3_finalize(statement) }
                    sqlite3_bind_text(statement, 1, "global_tags", -1, nil)

                    var loaded: [TagDefinition] = []
                    if sqlite3_step(statement) == SQLITE_ROW {
                        if let textPtr = sqlite3_column_text(statement, 0) {
                            let json = String(cString: textPtr)
                            if let data = json.data(using: .utf8) {
                                let decoder = JSONDecoder()
                                loaded = (try? decoder.decode([TagDefinition].self, from: data)) ?? []
                            }
                        }
                    }

                    if !loaded.isEmpty {
                        Task { @MainActor in
                            self.globalTags = loaded
                        }
                        continuation.resume()
                        return
                    }

                    // 2) If nothing stored, bootstrap from the music table directly (do NOT persist empty)
                    var derivedNames = Set<String>()
                    var stmt2: OpaquePointer?
                    let tagsQuery = "SELECT \(self.columnGeneralTags) FROM \(self.tableMusic) WHERE \(self.columnGeneralTags) IS NOT NULL AND LENGTH(TRIM(\(self.columnGeneralTags))) > 0"
                    if sqlite3_prepare_v2(db, tagsQuery, -1, &stmt2, nil) == SQLITE_OK {
                        defer { sqlite3_finalize(stmt2) }
                        while sqlite3_step(stmt2) == SQLITE_ROW {
                            if let textPtr = sqlite3_column_text(stmt2, 0) {
                                let json = String(cString: textPtr)
                                if let data = json.data(using: .utf8) {
                                    let decoder = JSONDecoder()
                                    if let tags = try? decoder.decode([String].self, from: data) {
                                        for t in tags { derivedNames.insert(t) }
                                    }
                                }
                            }
                        }
                    }

                    let derived = derivedNames.sorted { $0.lowercased() < $1.lowercased() }.map { TagDefinition(name: $0) }

                    // If we derived non-empty tags, persist when possible; otherwise, just publish empty without saving
                    if !derived.isEmpty {
                        if !self.isReadOnlyMode {
                            try self.saveGlobalTags(derived)
                        } else {
                            Task { @MainActor in
                                self.globalTags = derived
                            }
                        }
                    } else {
                        Task { @MainActor in
                            self.globalTags = []
                        }
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func saveGlobalTags(_ tags: [TagDefinition]) throws {
        guard let db = self.database else { throw CollectionError.databaseNotOpen }
        if self.isReadOnlyMode { throw CollectionError.queryFailed(message: "Cannot save UI settings in read-only mode.") }
        let encoder = JSONEncoder()
        let data = try encoder.encode(tags)
        let json = String(data: data, encoding: .utf8) ?? "[]"
        let upsertSQL = "REPLACE INTO \(self.tableUiSettings) (key, value) VALUES (?, ?)"
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, upsertSQL, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        sqlite3_bind_text(statement, 1, "global_tags", -1, nil)
        sqlite3_bind_text(statement, 2, json, -1, nil)
        if sqlite3_step(statement) != SQLITE_DONE {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        Task { @MainActor in
            self.globalTags = tags
        }
    }

    func addGlobalTag(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if globalTags.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return }
        var tags = globalTags
        tags.append(TagDefinition(name: trimmed))
        tags.sort { $0.name.lowercased() < $1.name.lowercased() }
        try saveGlobalTags(tags)
    }

    func removeGlobalTag(_ name: String) throws {
        var tags = globalTags
        tags.removeAll { $0.name == name }
        try saveGlobalTags(tags)
    }

    func updateGlobalTagColor(name: String, color: Color?) throws {
        var tags = globalTags
        if let idx = tags.firstIndex(where: { $0.name == name }) {
            tags[idx].color = color
            try saveGlobalTags(tags)
        }
    }

    // MARK: - Track Tag Updates
    func addTagToTrack(trackId: Int, tag: String) async throws {
        print("[Tags] addTagToTrack: id=\(trackId), tag=\(tag)")
        try await updateTrackTags(trackId: trackId) { current in
            var set = Set(current)
            set.insert(tag)
            return Array(set).sorted { $0.lowercased() < $1.lowercased() }
        }
    }

    func removeTagFromTrack(trackId: Int, tag: String) async throws {
        print("[Tags] removeTagFromTrack: id=\(trackId), tag=\(tag)")
        try await updateTrackTags(trackId: trackId) { current in
            let filtered = current.filter { $0 != tag }
            return filtered
        }
    }

    func addTagToTracks(trackIds: [Int], tag: String) async throws {
        print("[Tags] addTagToTracks: ids=\(trackIds.count), tag=\(tag)")
        for id in trackIds { 
            try await addTagToTrack(trackId: id, tag: tag)
            // Force a UI update after each track update
            await MainActor.run {
                print("[Tags] forcing UI update after adding tag to track \(id)")
            }
        }
    }

    func removeTagFromTracks(trackIds: [Int], tag: String) async throws {
        print("[Tags] removeTagFromTracks: ids=\(trackIds.count), tag=\(tag)")
        for id in trackIds { try await removeTagFromTrack(trackId: id, tag: tag) }
    }

    private func updateTrackTags(trackId: Int, transform: @escaping ([String]) -> [String]) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    if self.isReadOnlyMode { 
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot update tags in read-only mode."))
                        return
                    }
                    
                    print("[Tags] updateTrackTags: database=\(db != nil), readOnly=\(self.isReadOnlyMode)")
                    
                    // Check database state
                    var journalMode: OpaquePointer?
                    if sqlite3_prepare_v2(db, "PRAGMA journal_mode", -1, &journalMode, nil) == SQLITE_OK {
                        defer { sqlite3_finalize(journalMode) }
                        if sqlite3_step(journalMode) == SQLITE_ROW {
                            let mode = String(cString: sqlite3_column_text(journalMode, 0))
                            print("[Tags] Journal mode: \(mode)")
                        }
                    }
                    
                    // Check if database is writable
                    var writable: OpaquePointer?
                    if sqlite3_prepare_v2(db, "PRAGMA writable_schema", -1, &writable, nil) == SQLITE_OK {
                        defer { sqlite3_finalize(writable) }
                        if sqlite3_step(writable) == SQLITE_ROW {
                            let writableSchema = sqlite3_column_int(writable, 0)
                            print("[Tags] Writable schema: \(writableSchema)")
                        }
                    }
                    
                    _ = sqlite3_exec(db, "PRAGMA journal_mode = DELETE", nil, nil, nil)
                    
                    // Check schema on first update attempt
                    self.checkDatabaseSchema()
                    
                    // Get fresh tags from database instead of using potentially stale tracks array
                    let currentTags = try self.getCurrentTagsFromDatabaseSync(trackId: trackId)
                    let newTags = transform(currentTags)
                    print("[Tags] updateTrackTags: id=\(trackId) old=\(currentTags) new=\(newTags)")
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .sortedKeys // Ensure consistent output
                    let data = try encoder.encode(newTags)
                    let json = String(data: data, encoding: .utf8) ?? "[]"
                    print("[Tags] Encoded JSON data length: \(data.count) bytes")
                    print("[Tags] JSON string length: \(json.count) characters")
                    // Try direct SQL execution to avoid binding issues
                    let directSQL = "UPDATE \(self.tableMusic) SET \(self.columnGeneralTags) = '\(json)' WHERE \(self.columnId) = \(trackId)"
                    print("[Tags] Direct SQL: \(directSQL)")
                    
                    let execResult = sqlite3_exec(db, directSQL, nil, nil, nil)
                    print("[Tags] Direct SQL result: \(execResult)")
                    if execResult != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        print("[Tags] Direct SQL error: \(errorMessage)")
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    print("[Tags] Direct SQL successful, rows affected: \(sqlite3_changes(db))")
                    
                    // Force a commit to ensure the transaction is persisted
                    let commitResult = sqlite3_exec(db, "COMMIT", nil, nil, nil)
                    print("[Tags] Commit result: \(commitResult)")
                    
                    // Simple verification without complex statement management
                    let simpleVerify = "SELECT generalTags FROM music WHERE id = \(trackId)"
                    var simpleStatement: OpaquePointer?
                    if sqlite3_prepare_v2(db, simpleVerify, -1, &simpleStatement, nil) == SQLITE_OK {
                        defer { sqlite3_finalize(simpleStatement) }
                        if sqlite3_step(simpleStatement) == SQLITE_ROW {
                            if sqlite3_column_type(simpleStatement, 0) != SQLITE_NULL {
                                let stored = String(cString: sqlite3_column_text(simpleStatement, 0))
                                print("[Tags] SIMPLE VERIFY: Track \(trackId) has stored: '\(stored)'")
                            } else {
                                print("[Tags] SIMPLE VERIFY: Track \(trackId) has NULL")
                            }
                        } else {
                            print("[Tags] SIMPLE VERIFY: Track \(trackId) not found in database")
                        }
                    } else {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        print("[Tags] SIMPLE VERIFY: Failed to prepare query: \(errorMessage)")
                    }
                    // Test: Reload the specific track to see if it's corrupted
                    print("[Tags] Testing track reload after update...")
                    let testQuery = "SELECT * FROM \(self.tableMusic) WHERE \(self.columnId) = ?"
                    var testStatement: OpaquePointer?
                    if sqlite3_prepare_v2(db, testQuery, -1, &testStatement, nil) == SQLITE_OK {
                        defer { sqlite3_finalize(testStatement) }
                        sqlite3_bind_int(testStatement, 1, Int32(trackId))
                        if sqlite3_step(testStatement) == SQLITE_ROW {
                            do {
                                let reloadedTrack = try self.parseTrackFromRow(testStatement)
                                print("[Tags] RELOAD TEST: Track \(trackId) reloaded successfully - title: '\(reloadedTrack.title)', tags: \(reloadedTrack.generalTags)")
                            } catch {
                                print("[Tags] RELOAD TEST: Failed to reload track \(trackId): \(error)")
                            }
                        } else {
                            print("[Tags] RELOAD TEST: Track \(trackId) not found after update!")
                        }
                    }
                    
                    // Update the tracks array with fresh data
                    Task { @MainActor in
                        guard let index = self.tracks.firstIndex(where: { $0.id == trackId }) else { 
                            print("[CollectionService] Warning: track \(trackId) not found in tracks array")
                            return 
                        }
                        print("[CollectionService] updating track \(trackId) tags from \(self.tracks[index].generalTags) to \(newTags)")
                        var updatedTracks = self.tracks
                        updatedTracks[index] = Track(
                            id: self.tracks[index].id,
                            title: self.tracks[index].title,
                            artist: self.tracks[index].artist,
                            album: self.tracks[index].album,
                            albumArtist: self.tracks[index].albumArtist,
                            composer: self.tracks[index].composer,
                            genre: self.tracks[index].genre,
                            year: self.tracks[index].year,
                            trackNumber: self.tracks[index].trackNumber,
                            discNumber: self.tracks[index].discNumber,
                            bpm: self.tracks[index].bpm,
                            path: self.tracks[index].path,
                            isUrl: self.tracks[index].isUrl,
                            duration: self.tracks[index].duration,
                            timeMarkers: self.tracks[index].timeMarkers,
                            waveformData: self.tracks[index].waveformData,
                            rating: self.tracks[index].rating,
                            comment: self.tracks[index].comment,
                            generalTags: newTags,
                            dateAdded: self.tracks[index].dateAdded
                        )
                        self.tracks = updatedTracks
                        print("[CollectionService] track \(trackId) updated, new tags: \(updatedTracks[index].generalTags)")
                        print("[CollectionService] tracks array updated, count: \(self.tracks.count)")
                        
                        // Force a UI update cycle to ensure the change is propagated
                        self.objectWillChange.send()
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // Get current tags directly from database (ensures fresh data) - async version
    private func getCurrentTagsFromDatabase(trackId: Int) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    let tags = try self.getCurrentTagsFromDatabaseSync(trackId: trackId)
                    continuation.resume(returning: tags)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // Get current tags directly from database (ensures fresh data) - sync version for internal use
    private func getCurrentTagsFromDatabaseSync(trackId: Int) throws -> [String] {
        guard let db = self.database else { 
            throw CollectionError.databaseNotOpen
        }
        
        let query = "SELECT \(self.columnGeneralTags) FROM \(self.tableMusic) WHERE \(self.columnId) = ?"
        var statement: OpaquePointer?
        
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        
        sqlite3_bind_int(statement, 1, Int32(trackId))
        
        if sqlite3_step(statement) == SQLITE_ROW {
            if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                let raw = String(cString: sqlite3_column_text(statement, 0))
                let tagsJson = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if tagsJson.isEmpty {
                    print("[Tags] getCurrentTagsFromDatabaseSync: id=\(trackId) empty string, returning []")
                    return []
                }
                do {
                    let currentTags = try self.parseGeneralTags(from: tagsJson)
                    print("[Tags] getCurrentTagsFromDatabaseSync: id=\(trackId) tags=\(currentTags)")
                    return currentTags
                } catch {
                    print("[Tags] getCurrentTagsFromDatabaseSync decode error for id=\(trackId): \(error). Falling back to []")
                    return []
                }
            }
        }
        
        print("[Tags] getCurrentTagsFromDatabaseSync: id=\(trackId) no tags found, returning empty")
        return []
    }

    // Check database schema to see if generalTags column exists
    private func checkDatabaseSchema() {
        guard let db = self.database else { return }
        
        let schemaQuery = "PRAGMA table_info(\(self.tableMusic))"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, schemaQuery, -1, &statement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(statement) }
            
            print("[Schema] Music table columns:")
            while sqlite3_step(statement) == SQLITE_ROW {
                let columnName = String(cString: sqlite3_column_text(statement, 1))
                let columnType = String(cString: sqlite3_column_text(statement, 2))
                print("[Schema] - \(columnName): \(columnType)")
            }
        }
    }

    // Set tags exactly (optimistic UI friendly)
    func setTagsForTrack(trackId: Int, newTags: [String]) async throws {
        print("[Tags] setTagsForTrack: id=\(trackId), incoming=\(newTags)")
        try await updateTrackTags(trackId: trackId) { _ in
            // Ignore the input parameter (which could be stale) and use the provided newTags
            let unique = Array(Set(newTags)).sorted { $0.lowercased() < $1.lowercased() }
            return unique
        }
    }
    
    // MARK: - Database Repair Utilities
    
    /// Attempts to fix corrupted metadata for a specific track - async version
    func fixCorruptedTrackMetadata(trackId: Int) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    try self.fixCorruptedTrackMetadataSync(trackId: trackId)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Attempts to fix corrupted metadata for a specific track - sync version for internal use
    private func fixCorruptedTrackMetadataSync(trackId: Int) throws {
        guard let db = self.database else { 
            throw CollectionError.databaseNotOpen
        }
        if self.isReadOnlyMode { 
            throw CollectionError.queryFailed(message: "Cannot fix metadata in read-only mode.")
        }
        
        print("🔧 Attempting to fix corrupted metadata for track \(trackId)")
        
        // Get the track's basic info first
        let basicQuery = "SELECT title, artist, album FROM \(self.tableMusic) WHERE \(self.columnId) = ?"
        var basicStatement: OpaquePointer?
        
        let basicResult = sqlite3_prepare_v2(db, basicQuery, -1, &basicStatement, nil)
        defer { sqlite3_finalize(basicStatement) }
        
        if basicResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        
        sqlite3_bind_int(basicStatement, 1, Int32(trackId))
        
        guard sqlite3_step(basicStatement) == SQLITE_ROW else {
            throw CollectionError.queryFailed(message: "Track \(trackId) not found")
        }
        
        let title = String(cString: sqlite3_column_text(basicStatement, 0))
        let artist = String(cString: sqlite3_column_text(basicStatement, 1))
        let album = String(cString: sqlite3_column_text(basicStatement, 2))
        
        print("🔧 Fixing metadata for track: \(title) by \(artist)")
        
        // Reset problematic JSON fields to empty arrays
        let fixSQL = """
            UPDATE \(self.tableMusic) 
            SET \(self.columnGeneralTags) = '[]',
                \(self.columnTimeMarkers) = '[]',
                \(self.columnWaveformData) = NULL
            WHERE \(self.columnId) = ?
        """
        
        var fixStatement: OpaquePointer?
        let fixResult = sqlite3_prepare_v2(db, fixSQL, -1, &fixStatement, nil)
        defer { sqlite3_finalize(fixStatement) }
        
        if fixResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        
        sqlite3_bind_int(fixStatement, 1, Int32(trackId))
        
        if sqlite3_step(fixStatement) != SQLITE_DONE {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        
        print("✅ Successfully fixed metadata for track \(trackId)")
        
        // Reload the track in memory
        Task { @MainActor in
            if let index = self.tracks.firstIndex(where: { $0.id == trackId }) {
                var updatedTracks = self.tracks
                updatedTracks[index] = Track(
                    id: self.tracks[index].id,
                    title: self.tracks[index].title,
                    artist: self.tracks[index].artist,
                    album: self.tracks[index].album,
                    albumArtist: self.tracks[index].albumArtist,
                    composer: self.tracks[index].composer,
                    genre: self.tracks[index].genre,
                    year: self.tracks[index].year,
                    trackNumber: self.tracks[index].trackNumber,
                    discNumber: self.tracks[index].discNumber,
                    bpm: self.tracks[index].bpm,
                    path: self.tracks[index].path,
                    isUrl: self.tracks[index].isUrl,
                    duration: self.tracks[index].duration,
                    timeMarkers: [],
                    waveformData: nil,
                    rating: self.tracks[index].rating,
                    comment: self.tracks[index].comment,
                    generalTags: [],
                    dateAdded: self.tracks[index].dateAdded
                )
                self.tracks = updatedTracks
            }
        }
    }
    
    /// Automatically fixes common metadata corruption issues in the database
    func autoFixCorruptedMetadata() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    if self.isReadOnlyMode { 
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot fix metadata in read-only mode."))
                        return
                    }
                    
                    print("🔧 Starting automatic metadata corruption fix...")
                    
                    // Find tracks with problematic metadata
                    let problematicQuery = """
                        SELECT \(self.columnId), \(self.columnTitle), \(self.columnGeneralTags), \(self.columnTimeMarkers), \(self.columnWaveformData)
                        FROM \(self.tableMusic)
                        WHERE (\(self.columnGeneralTags) IS NOT NULL AND \(self.columnGeneralTags) != '[]' AND \(self.columnGeneralTags) != '')
                           OR (\(self.columnTimeMarkers) IS NOT NULL AND \(self.columnTimeMarkers) != '[]' AND \(self.columnTimeMarkers) != '')
                           OR (\(self.columnWaveformData) IS NOT NULL AND \(self.columnWaveformData) != '[]' AND \(self.columnWaveformData) != '')
                    """
                    
                    var statement: OpaquePointer?
                    let result = sqlite3_prepare_v2(db, problematicQuery, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    var fixedCount = 0
                    
                    while sqlite3_step(statement) == SQLITE_ROW {
                        let trackId = Int(sqlite3_column_int(statement, 0))
                        let title = String(cString: sqlite3_column_text(statement, 1))
                        
                        // Check each field for corruption
                        var needsFix = false
                        var fixFields: [String] = []
                        
                        // Check generalTags
                        if sqlite3_column_type(statement, 2) != SQLITE_NULL {
                            let tagsData = String(cString: sqlite3_column_text(statement, 2))
                            if tagsData.isEmpty || tagsData.contains(where: { !$0.isASCII || $0.asciiValue ?? 0 < 32 }) {
                                needsFix = true
                                fixFields.append("generalTags")
                            }
                        }
                        
                        // Check timeMarkers
                        if sqlite3_column_type(statement, 3) != SQLITE_NULL {
                            let markersData = String(cString: sqlite3_column_text(statement, 3))
                            if markersData.isEmpty || markersData.contains(where: { !$0.isASCII || $0.asciiValue ?? 0 < 32 }) {
                                needsFix = true
                                fixFields.append("timeMarkers")
                            }
                        }
                        
                        // Check waveformData
                        if sqlite3_column_type(statement, 4) != SQLITE_NULL {
                            let waveformData = String(cString: sqlite3_column_text(statement, 4))
                            if waveformData.isEmpty || waveformData.contains(where: { !$0.isASCII || $0.asciiValue ?? 0 < 32 }) {
                                needsFix = true
                                fixFields.append("waveformData")
                            }
                        }
                        
                        if needsFix {
                            print("🔧 Auto-fixing track \(trackId) (\(title)) - corrupted fields: \(fixFields)")
                            try self.fixCorruptedTrackMetadataSync(trackId: trackId)
                            fixedCount += 1
                        }
                    }
                    
                    print("✅ Auto-fix completed. Fixed \(fixedCount) tracks.")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Scans the database for tracks with corrupted metadata and returns a list
    func scanForCorruptedTracks() async throws -> [(id: Int, title: String, issues: [String])] {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    
                    print("🔍 Scanning database for corrupted tracks...")
                    
                    let query = "SELECT \(self.columnId), \(self.columnTitle), \(self.columnArtist), \(self.columnGeneralTags), \(self.columnTimeMarkers), \(self.columnWaveformData) FROM \(self.tableMusic)"
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    var corruptedTracks: [(id: Int, title: String, issues: [String])] = []
                    
                    while sqlite3_step(statement) == SQLITE_ROW {
                        let id = Int(sqlite3_column_int(statement, 0))
                        let title = String(cString: sqlite3_column_text(statement, 1))
                        let artist = String(cString: sqlite3_column_text(statement, 2))
                        var issues: [String] = []
                        
                        // Check generalTags
                        if sqlite3_column_type(statement, 3) != SQLITE_NULL {
                            let tagsData = String(cString: sqlite3_column_text(statement, 3))
                            if let data = tagsData.data(using: .utf8) {
                                do {
                                    let _ = try JSONDecoder().decode([String].self, from: data)
                                } catch {
                                    issues.append("Corrupted generalTags JSON")
                                }
                            } else {
                                issues.append("Invalid generalTags encoding")
                            }
                        }
                        
                        // Check timeMarkers
                        if sqlite3_column_type(statement, 4) != SQLITE_NULL {
                            let markersData = String(cString: sqlite3_column_text(statement, 4))
                            if let data = markersData.data(using: .utf8) {
                                do {
                                    let _ = try JSONDecoder().decode([TimeMarker].self, from: data)
                                } catch {
                                    issues.append("Corrupted timeMarkers JSON")
                                }
                            } else {
                                issues.append("Invalid timeMarkers encoding")
                            }
                        }
                        
                        // Check waveformData
                        if sqlite3_column_type(statement, 5) != SQLITE_NULL {
                            let waveformData = String(cString: sqlite3_column_text(statement, 5))
                            if let data = waveformData.data(using: .utf8) {
                                do {
                                    let _ = try JSONDecoder().decode([Double].self, from: data)
                                } catch {
                                    issues.append("Corrupted waveformData JSON")
                                }
                            } else {
                                issues.append("Invalid waveformData encoding")
                            }
                        }
                        
                        if !issues.isEmpty {
                            corruptedTracks.append((id: id, title: "\(title) - \(artist)", issues: issues))
                        }
                    }
                    
                    print("🔍 Found \(corruptedTracks.count) tracks with corrupted metadata")
                    continuation.resume(returning: corruptedTracks)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Fixes corrupted waveform data by resetting it to null
    func fixCorruptedWaveformData(trackId: Int) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    if self.isReadOnlyMode { 
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot fix waveform data in read-only mode."))
                        return
                    }
                    
                    print("🔧 Fixing corrupted waveform data for track \(trackId)")
                    
                    let sql = "UPDATE \(self.tableMusic) SET \(self.columnWaveformData) = NULL WHERE \(self.columnId) = ?"
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    sqlite3_bind_int(statement, 1, Int32(trackId))
                    
                    if sqlite3_step(statement) != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    print("✅ Successfully fixed waveform data for track \(trackId)")
                    
                    // Update the track in memory
                    Task { @MainActor in
                        if let index = self.tracks.firstIndex(where: { $0.id == trackId }) {
                            var updatedTracks = self.tracks
                            updatedTracks[index] = Track(
                                id: self.tracks[index].id,
                                title: self.tracks[index].title,
                                artist: self.tracks[index].artist,
                                album: self.tracks[index].album,
                                albumArtist: self.tracks[index].albumArtist,
                                composer: self.tracks[index].composer,
                                genre: self.tracks[index].genre,
                                year: self.tracks[index].year,
                                trackNumber: self.tracks[index].trackNumber,
                                discNumber: self.tracks[index].discNumber,
                                bpm: self.tracks[index].bpm,
                                path: self.tracks[index].path,
                                isUrl: self.tracks[index].isUrl,
                                duration: self.tracks[index].duration,
                                timeMarkers: self.tracks[index].timeMarkers,
                                waveformData: nil,
                                rating: self.tracks[index].rating,
                                comment: self.tracks[index].comment,
                                generalTags: self.tracks[index].generalTags,
                                dateAdded: self.tracks[index].dateAdded
                            )
                            self.tracks = updatedTracks
                        }
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Updates tracks that don't have a proper dateAdded value
    func updateMissingDateAdded() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    if self.isReadOnlyMode { 
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot update dates in read-only mode."))
                        return
                    }
                    
                    print("🔧 Updating tracks with missing dateAdded values...")
                    
                    // Find tracks with empty or NULL dateAdded
                    let updateSQL = """
                        UPDATE \(self.tableMusic) 
                        SET \(self.columnDateAdded) = ? 
                        WHERE \(self.columnDateAdded) = '' OR \(self.columnDateAdded) IS NULL
                    """
                    
                    var statement: OpaquePointer?
                    let result = sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    // Use a date 30 days ago as default for existing tracks
                    let defaultDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400 * 30))
                    sqlite3_bind_text(statement, 1, defaultDate, -1, self.SQLITE_TRANSIENT)
                    
                    if sqlite3_step(statement) != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    let updatedCount = sqlite3_changes(db)
                    print("✅ Updated \(updatedCount) tracks with missing dateAdded values")
                    
                    // Reload tracks to reflect changes
                    Task { @MainActor in
                        try? await self.loadAllTracks()
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Removes duplicate tracks from the database (keeps the first occurrence)
    func removeDuplicateTracks() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    if self.isReadOnlyMode { 
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot remove duplicates in read-only mode."))
                        return
                    }
                    
                    print("🧹 Starting duplicate track cleanup...")
                    
                    // Find duplicates by path
                    let duplicateQuery = """
                        SELECT path, COUNT(*) as count, GROUP_CONCAT(id) as ids
                        FROM \(self.tableMusic)
                        GROUP BY path
                        HAVING COUNT(*) > 1
                    """
                    
                    var statement: OpaquePointer?
                    let result = sqlite3_prepare_v2(db, duplicateQuery, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    var removedCount = 0
                    
                    while sqlite3_step(statement) == SQLITE_ROW {
                        let path = String(cString: sqlite3_column_text(statement, 0))
                        let count = Int(sqlite3_column_int(statement, 1))
                        let idsString = String(cString: sqlite3_column_text(statement, 2))
                        
                        let ids = idsString.components(separatedBy: ",").compactMap { Int($0) }
                        
                        if ids.count > 1 {
                            print("🧹 Found \(count) duplicates for path: \(path)")
                            print("🧹 Track IDs: \(ids)")
                            
                            // Keep the first ID, remove the rest
                            let idsToRemove = Array(ids.dropFirst())
                            
                            for idToRemove in idsToRemove {
                                let deleteSQL = "DELETE FROM \(self.tableMusic) WHERE \(self.columnId) = ?"
                                var deleteStatement: OpaquePointer?
                                
                                let deleteResult = sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil)
                                defer { sqlite3_finalize(deleteStatement) }
                                
                                if deleteResult == SQLITE_OK {
                                    sqlite3_bind_int(deleteStatement, 1, Int32(idToRemove))
                                    
                                    if sqlite3_step(deleteStatement) == SQLITE_DONE {
                                        print("🧹 Removed duplicate track ID: \(idToRemove)")
                                        removedCount += 1
                                    } else {
                                        let errorMessage = String(cString: sqlite3_errmsg(db))
                                        print("⚠️ Failed to remove duplicate track ID \(idToRemove): \(errorMessage)")
                                    }
                                } else {
                                    let errorMessage = String(cString: sqlite3_errmsg(db))
                                    print("⚠️ Failed to prepare delete statement for track ID \(idToRemove): \(errorMessage)")
                                }
                            }
                        }
                    }
                    
                    print("✅ Duplicate cleanup completed. Removed \(removedCount) duplicate tracks.")
                    
                    // Reload tracks to reflect changes
                    Task { @MainActor in
                        try? await self.loadAllTracks()
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
