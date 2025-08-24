import Foundation
import SQLite3
import Combine
import SwiftUI

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
    @Published var globalTags: [TagDefinition] = []
    
    private var database: OpaquePointer?
    private var activeCollectionDefinition: CollectionDefinition?
    private var localCollectionRootFolders: [String] = []
    private var securityScopedURL: URL?
    private var isReadOnlyMode: Bool = false
    
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
        
        Task { @MainActor in
            tracks = []
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
        guard let db = database else {
            print("❌ Database not open")
            throw CollectionError.databaseNotOpen
        }
        
        // Check for existing tracks with tags to understand the format
        let sampleQuery = "SELECT id, \(columnGeneralTags) FROM \(tableMusic) WHERE \(columnGeneralTags) IS NOT NULL AND LENGTH(TRIM(\(columnGeneralTags))) > 0 LIMIT 3"
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
        
        await MainActor.run {
            isLoading = true
        }
        
        let query = "SELECT * FROM \(tableMusic)"
        print("🔍 Executing query: \(query)")
        var statement: OpaquePointer?
        
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Query failed: \(errorMessage)")
            throw CollectionError.queryFailed(message: errorMessage)
        }
        
        var loadedTracks: [Track] = []
        var failedTracks: [(id: Int, title: String, error: String, rawData: String)] = []
        var rowCount = 0
        
        while sqlite3_step(statement) == SQLITE_ROW {
            rowCount += 1
            do {
                let track = try parseTrackFromRow(statement)
                print("📝 Parsed track: \(track.title) (id: \(track.id ?? -1))")
                let resolvedTrack = resolveTrackPath(track)
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
        
        await MainActor.run {
            tracks = loadedTracks.sorted()
            isLoading = false
        }
        
        print("✅ Loaded \(loadedTracks.count) tracks from database")
        if !failedTracks.isEmpty {
            print("⚠️  \(failedTracks.count) tracks failed to load due to metadata encoding issues")
        }
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
            print("[TrackParse] Track \(id) raw tags data: '\(tagsJson)'")
            do {
                generalTags = try parseGeneralTags(from: tagsJson)
                print("[TrackParse] Track \(id) parsed tags: \(generalTags)")
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
            print("[TrackParse] Track \(id) has NULL tags")
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
            
            throw error
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
    private func resolveTrackPath(_ track: Track) -> Track {
        print("🔍 resolveTrackPath called for track: \(track.title)")
        print("   Original path: \(track.path)")
        print("   Is URL: \(track.isUrl)")
        print("   Collection type: \(activeCollectionDefinition?.type.rawValue ?? "unknown")")
        print("   Root folders: \(localCollectionRootFolders)")
        
        guard let definition = activeCollectionDefinition,
              !track.isUrl else {
            print("   ⚠️ Skipping path resolution (no definition or is URL)")
            return track
        }
        
        var absolutePath: String
        
        switch definition.type {
        case .shared:
            guard let rootPath = definition.rootPath else {
                print("   ⚠️ No root path for shared collection")
                return track
            }
            absolutePath = (rootPath as NSString).appendingPathComponent(track.path)
            print("   📁 Shared collection resolved path: \(absolutePath)")
            
        case .local:
            print("   🔍 Local collection - checking \(localCollectionRootFolders.count) root folders")
            // For local collections, try to find the file in any of the root folders
            var foundPath = false
            absolutePath = "" // Initialize with empty string
            
            for (index, rootFolder) in localCollectionRootFolders.enumerated() {
                let candidatePath = (rootFolder as NSString).appendingPathComponent(track.path)
                print("   📂 Checking folder \(index + 1): \(candidatePath)")
                if FileManager.default.fileExists(atPath: candidatePath) {
                    absolutePath = candidatePath
                    foundPath = true
                    print("   ✅ Found file at: \(absolutePath)")
                    break
                }
            }
            // If not found in any root folder, use the first root folder as fallback
            if localCollectionRootFolders.isEmpty {
                print("   ⚠️ No root folders available")
                return track
            }
            if !foundPath {
                absolutePath = (localCollectionRootFolders[0] as NSString).appendingPathComponent(track.path)
                print("   📁 Using fallback path: \(absolutePath)")
            }
        }
        
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
            path: absolutePath,
            isUrl: track.isUrl,
            duration: track.duration,
            timeMarkers: track.timeMarkers,
            waveformData: track.waveformData,
            rating: track.rating,
            comment: track.comment,
            generalTags: track.generalTags
        )
        
        print("   ✅ Resolved track path: \(track.path) -> \(absolutePath)")
        return resolvedTrack
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
    
    // MARK: - Track Updates
    func updateTrackWaveformData(trackId: Int, waveformData: [Double]) async throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        if isReadOnlyMode { throw CollectionError.queryFailed(message: "Cannot update waveform in read-only mode.") }

        _ = sqlite3_exec(db, "PRAGMA journal_mode = DELETE", nil, nil, nil)

        let encoder = JSONEncoder()
        let data = try encoder.encode(waveformData)
        let json = String(data: data, encoding: .utf8) ?? "[]"

        let sql = "UPDATE \(tableMusic) SET \(columnWaveformData) = ? WHERE \(columnId) = ?"
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        if result != SQLITE_OK { throw CollectionError.queryFailed(message: String(cString: sqlite3_errmsg(db))) }
        sqlite3_bind_text(statement, 1, json, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(trackId))
        if sqlite3_step(statement) != SQLITE_DONE {
            throw CollectionError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }

        await MainActor.run {
            if let index = tracks.firstIndex(where: { $0.id == trackId }) {
                var updated = tracks
                updated[index] = Track(
                    id: updated[index].id,
                    title: updated[index].title,
                    artist: updated[index].artist,
                    album: updated[index].album,
                    albumArtist: updated[index].albumArtist,
                    composer: updated[index].composer,
                    genre: updated[index].genre,
                    year: updated[index].year,
                    trackNumber: updated[index].trackNumber,
                    discNumber: updated[index].discNumber,
                    bpm: updated[index].bpm,
                    path: updated[index].path,
                    isUrl: updated[index].isUrl,
                    duration: updated[index].duration,
                    timeMarkers: updated[index].timeMarkers,
                    waveformData: waveformData,
                    rating: updated[index].rating,
                    comment: updated[index].comment,
                    generalTags: updated[index].generalTags
                )
                tracks = updated
            }
        }
    }
    func updateTrackRating(trackId: Int, newRating: Int) async throws {
        guard let db = database else {
            throw CollectionError.databaseNotOpen
        }
        
        if isReadOnlyMode {
            throw CollectionError.queryFailed(message: "Cannot update ratings in read-only mode. Please ensure the database file is writable.")
        }
        
        // First, ensure we're using DELETE journal mode to avoid permission issues
        let journalResult = sqlite3_exec(db, "PRAGMA journal_mode = DELETE", nil, nil, nil)
        if journalResult != SQLITE_OK {
            print("Warning: Could not set journal mode to DELETE for update operation")
        }
        
        let query = "UPDATE \(tableMusic) SET \(columnRating) = ? WHERE \(columnId) = ?"
        var statement: OpaquePointer?
        
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        
        // Bind parameters
        sqlite3_bind_int(statement, 1, Int32(newRating))
        sqlite3_bind_int(statement, 2, Int32(trackId))
        
        let stepResult = sqlite3_step(statement)
        if stepResult != SQLITE_DONE {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        
        // Update the track in the local array on the main thread
        await MainActor.run {
            if let index = tracks.firstIndex(where: { $0.id == trackId }) {
                var updatedTracks = tracks
                updatedTracks[index] = Track(
                    id: tracks[index].id,
                    title: tracks[index].title,
                    artist: tracks[index].artist,
                    album: tracks[index].album,
                    albumArtist: tracks[index].albumArtist,
                    composer: tracks[index].composer,
                    genre: tracks[index].genre,
                    year: tracks[index].year,
                    trackNumber: tracks[index].trackNumber,
                    discNumber: tracks[index].discNumber,
                    bpm: tracks[index].bpm,
                    path: tracks[index].path,
                    isUrl: tracks[index].isUrl,
                    duration: tracks[index].duration,
                    timeMarkers: tracks[index].timeMarkers,
                    waveformData: tracks[index].waveformData,
                    rating: newRating,
                    comment: tracks[index].comment,
                    generalTags: tracks[index].generalTags
                )
                tracks = updatedTracks
            }
        }
        
        print("Updated rating for track \(trackId) to \(newRating)")
    }

    // MARK: - Global Tags Persistence
    func loadGlobalTags() async throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }

        // 1) Try to load from ui_settings
        var statement: OpaquePointer?
        let selectSQL = "SELECT value FROM \(tableUiSettings) WHERE key = ?"
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
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
            await MainActor.run { self.globalTags = loaded }
            return
        }

        // 2) If nothing stored, bootstrap from the music table directly (do NOT persist empty)
        var derivedNames = Set<String>()
        var stmt2: OpaquePointer?
        let tagsQuery = "SELECT \(columnGeneralTags) FROM \(tableMusic) WHERE \(columnGeneralTags) IS NOT NULL AND LENGTH(TRIM(\(columnGeneralTags))) > 0"
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
            if !isReadOnlyMode {
                try saveGlobalTags(derived)
            } else {
                await MainActor.run { self.globalTags = derived }
            }
        } else {
            await MainActor.run { self.globalTags = [] }
        }
    }

    private func saveGlobalTags(_ tags: [TagDefinition]) throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        if isReadOnlyMode { throw CollectionError.queryFailed(message: "Cannot save UI settings in read-only mode.") }
        let encoder = JSONEncoder()
        let data = try encoder.encode(tags)
        let json = String(data: data, encoding: .utf8) ?? "[]"
        let upsertSQL = "REPLACE INTO \(tableUiSettings) (key, value) VALUES (?, ?)"
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
        Task { @MainActor in self.globalTags = tags }
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

    private func updateTrackTags(trackId: Int, transform: ([String]) -> [String]) async throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        if isReadOnlyMode { throw CollectionError.queryFailed(message: "Cannot update tags in read-only mode.") }
        
        print("[Tags] updateTrackTags: database=\(db != nil), readOnly=\(isReadOnlyMode)")
        
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
        checkDatabaseSchema()
        
        // Get fresh tags from database instead of using potentially stale tracks array
        let currentTags = try await getCurrentTagsFromDatabase(trackId: trackId)
        let newTags = transform(currentTags)
        print("[Tags] updateTrackTags: id=\(trackId) old=\(currentTags) new=\(newTags)")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys // Ensure consistent output
        let data = try encoder.encode(newTags)
        let json = String(data: data, encoding: .utf8) ?? "[]"
        print("[Tags] Encoded JSON data length: \(data.count) bytes")
        print("[Tags] JSON string length: \(json.count) characters")
        // Try direct SQL execution to avoid binding issues
        let directSQL = "UPDATE \(tableMusic) SET \(columnGeneralTags) = '\(json)' WHERE \(columnId) = \(trackId)"
        print("[Tags] Direct SQL: \(directSQL)")
        
        let execResult = sqlite3_exec(db, directSQL, nil, nil, nil)
        print("[Tags] Direct SQL result: \(execResult)")
        if execResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("[Tags] Direct SQL error: \(errorMessage)")
            throw CollectionError.queryFailed(message: errorMessage)
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
                    print("[Tags] SIMPLE VERIFY: Track \(trackId) stored: '\(stored)'")
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
        let testQuery = "SELECT * FROM \(tableMusic) WHERE \(columnId) = ?"
        var testStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, testQuery, -1, &testStatement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(testStatement) }
            sqlite3_bind_int(testStatement, 1, Int32(trackId))
            if sqlite3_step(testStatement) == SQLITE_ROW {
                do {
                    let reloadedTrack = try parseTrackFromRow(testStatement)
                    print("[Tags] RELOAD TEST: Track \(trackId) reloaded successfully - title: '\(reloadedTrack.title)', tags: \(reloadedTrack.generalTags)")
                } catch {
                    print("[Tags] RELOAD TEST: Failed to reload track \(trackId): \(error)")
                }
            } else {
                print("[Tags] RELOAD TEST: Track \(trackId) not found after update!")
            }
        }
        
        // Update the tracks array with fresh data
        await MainActor.run {
            guard let index = tracks.firstIndex(where: { $0.id == trackId }) else { 
                print("[CollectionService] Warning: track \(trackId) not found in tracks array")
                return 
            }
            print("[CollectionService] updating track \(trackId) tags from \(tracks[index].generalTags) to \(newTags)")
            var updatedTracks = tracks
            updatedTracks[index] = Track(
                id: tracks[index].id,
                title: tracks[index].title,
                artist: tracks[index].artist,
                album: tracks[index].album,
                albumArtist: tracks[index].albumArtist,
                composer: tracks[index].composer,
                genre: tracks[index].genre,
                year: tracks[index].year,
                trackNumber: tracks[index].trackNumber,
                discNumber: tracks[index].discNumber,
                bpm: tracks[index].bpm,
                path: tracks[index].path,
                isUrl: tracks[index].isUrl,
                duration: tracks[index].duration,
                timeMarkers: tracks[index].timeMarkers,
                waveformData: tracks[index].waveformData,
                rating: tracks[index].rating,
                comment: tracks[index].comment,
                generalTags: newTags
            )
            tracks = updatedTracks
            print("[CollectionService] track \(trackId) updated, new tags: \(updatedTracks[index].generalTags)")
            print("[CollectionService] tracks array updated, count: \(tracks.count)")
            
            // Force a UI update cycle to ensure the change is propagated
            DispatchQueue.main.async {
                print("[CollectionService] forcing UI update cycle")
            }
        }
    }
    
    // Get current tags directly from database (ensures fresh data)
    private func getCurrentTagsFromDatabase(trackId: Int) async throws -> [String] {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        
        let query = "SELECT \(columnGeneralTags) FROM \(tableMusic) WHERE \(columnId) = ?"
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
                    print("[Tags] getCurrentTagsFromDatabase: id=\(trackId) empty string, returning []")
                    return []
                }
                do {
                    let currentTags = try parseGeneralTags(from: tagsJson)
                    print("[Tags] getCurrentTagsFromDatabase: id=\(trackId) tags=\(currentTags)")
                    return currentTags
                } catch {
                    print("[Tags] getCurrentTagsFromDatabase decode error for id=\(trackId): \(error). Falling back to []")
                    return []
                }
            }
        }
        
        print("[Tags] getCurrentTagsFromDatabase: id=\(trackId) no tags found, returning empty")
        return []
    }

    // Check database schema to see if generalTags column exists
    private func checkDatabaseSchema() {
        guard let db = database else { return }
        
        let schemaQuery = "PRAGMA table_info(\(tableMusic))"
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
    
    /// Attempts to fix corrupted metadata for a specific track
    func fixCorruptedTrackMetadata(trackId: Int) async throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        if isReadOnlyMode { throw CollectionError.queryFailed(message: "Cannot fix metadata in read-only mode.") }
        
        print("🔧 Attempting to fix corrupted metadata for track \(trackId)")
        
        // Get the track's basic info first
        let basicQuery = "SELECT title, artist, album FROM \(tableMusic) WHERE \(columnId) = ?"
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
            UPDATE \(tableMusic) 
            SET \(columnGeneralTags) = '[]',
                \(columnTimeMarkers) = '[]',
                \(columnWaveformData) = NULL
            WHERE \(columnId) = ?
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
        await MainActor.run {
            if let index = tracks.firstIndex(where: { $0.id == trackId }) {
                var updatedTracks = tracks
                updatedTracks[index] = Track(
                    id: tracks[index].id,
                    title: tracks[index].title,
                    artist: tracks[index].artist,
                    album: tracks[index].album,
                    albumArtist: tracks[index].albumArtist,
                    composer: tracks[index].composer,
                    genre: tracks[index].genre,
                    year: tracks[index].year,
                    trackNumber: tracks[index].trackNumber,
                    discNumber: tracks[index].discNumber,
                    bpm: tracks[index].bpm,
                    path: tracks[index].path,
                    isUrl: tracks[index].isUrl,
                    duration: tracks[index].duration,
                    timeMarkers: [],
                    waveformData: nil,
                    rating: tracks[index].rating,
                    comment: tracks[index].comment,
                    generalTags: []
                )
                tracks = updatedTracks
            }
        }
    }
    
    /// Automatically fixes common metadata corruption issues in the database
    func autoFixCorruptedMetadata() async throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        if isReadOnlyMode { throw CollectionError.queryFailed(message: "Cannot fix metadata in read-only mode.") }
        
        print("🔧 Starting automatic metadata corruption fix...")
        
        // Find tracks with problematic metadata
        let problematicQuery = """
            SELECT \(columnId), \(columnTitle), \(columnGeneralTags), \(columnTimeMarkers), \(columnWaveformData)
            FROM \(tableMusic)
            WHERE (\(columnGeneralTags) IS NOT NULL AND \(columnGeneralTags) != '[]' AND \(columnGeneralTags) != '')
               OR (\(columnTimeMarkers) IS NOT NULL AND \(columnTimeMarkers) != '[]' AND \(columnTimeMarkers) != '')
               OR (\(columnWaveformData) IS NOT NULL AND \(columnWaveformData) != '[]' AND \(columnWaveformData) != '')
        """
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, problematicQuery, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
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
                try await fixCorruptedTrackMetadata(trackId: trackId)
                fixedCount += 1
            }
        }
        
        print("✅ Auto-fix completed. Fixed \(fixedCount) tracks.")
    }
    
    /// Scans the database for tracks with corrupted metadata and returns a list
    func scanForCorruptedTracks() async throws -> [(id: Int, title: String, issues: [String])] {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        
        print("🔍 Scanning database for corrupted tracks...")
        
        let query = "SELECT \(columnId), \(columnTitle), \(columnArtist), \(columnGeneralTags), \(columnTimeMarkers), \(columnWaveformData) FROM \(tableMusic)"
        var statement: OpaquePointer?
        
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        if result != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
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
        return corruptedTracks
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
