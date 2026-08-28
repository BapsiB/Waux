import Foundation
import AVFoundation
import SQLite3
import Combine
import SwiftUI
import CryptoKit
import ID3TagEditor

// Note: ID3Tag initializer is internal, so we'll use a different approach

class CollectionService: ObservableObject {
    // MARK: - Constants
    private let databaseVersion = 8
    private let tableMusic = "music"
    private let tablePlaylists = "playlists"
    private let tablePlaylistTracks = "playlist_tracks"
    private let tableLocalRoots = "local_root_folders"
    private let tableUiSettings = "ui_settings"
    private let tableTrackGroups = "track_groups"
    private let tableTrackGroupMembers = "track_group_members"
    private let tableWaveforms = "waveforms"
    
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
    
    // Explicit column selection to guarantee order across different DB schemas.
    // Waveform samples live in `waveforms`; this list is metadata only.
    private var selectTrackColumns: String {
        let t = tableMusic
        return "\(t).\(columnId), \(t).\(columnTitle), \(t).\(columnArtist), \(t).\(columnAlbum), \(t).\(columnAlbumArtist), \(t).\(columnComposer), \(t).\(columnGenre), \(t).\(columnYear), \(t).\(columnTrackNumber), \(t).\(columnDiscNumber), \(t).\(columnBpm), \(t).\(columnPath), \(t).\(columnIsUrl), \(t).\(columnDuration), \(t).\(columnTimeMarkers), \(t).\(columnRating), \(t).\(columnComment), \(t).\(columnGeneralTags), \(t).\(columnDateAdded)"
    }

    private var selectTracksFromMusicSQL: String {
        """
        SELECT \(selectTrackColumns),
               CASE WHEN w.track_id IS NULL THEN 0 WHEN w.bin_count = 0 THEN 1 ELSE 2 END
        FROM \(tableMusic)
        LEFT JOIN \(tableWaveforms) w ON w.track_id = \(tableMusic).\(columnId)
        """
    }

    private let iso8601DateFormatter = ISO8601DateFormatter()
    
    // MARK: - Properties
    private var _tracks: [Track] = []
    private var tracksById: [Int: Track] = [:]
    private let tracksSubject = CurrentValueSubject<[Track], Never>([])
    var tracks: [Track] {
        get { _tracks }
        set {
            _tracks = newValue
            rebuildTracksById()
            tracksSubject.send(newValue)
            refreshMissingWaveformCount()
            objectWillChange.send()
        }
    }

    /// Ordered lookup of in-memory tracks by `music.id`. Missing ids are skipped.
    func tracks(ids: [Int]) -> [Track] {
        ids.compactMap { tracksById[$0] }
    }

    func track(id: Int) -> Track? {
        tracksById[id]
    }

    private func rebuildTracksById() {
        var index: [Int: Track] = [:]
        index.reserveCapacity(_tracks.count)
        for track in _tracks {
            if let id = track.id {
                index[id] = track
            }
        }
        tracksById = index
    }

    func makePlaylistPathLookup() -> PlaylistPathLookup {
        let pairs = _tracks.compactMap { track -> (id: Int, path: String)? in
            guard let id = track.id else { return nil }
            return (id, track.path)
        }
        return PlaylistPathLookup(
            idAndPaths: pairs,
            collectionRootPath: activeCollectionDefinition?.rootPath,
            databasePath: activeCollectionDefinition?.dbPath
        )
    }
    var tracksPublisher: AnyPublisher<[Track], Never> {
        tracksSubject.eraseToAnyPublisher()
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var globalTags: [TagDefinition] = []
    /// Local tracks that still have no waveform (`nil`). Empty arrays are treated as processed (e.g. missing file).
    private(set) var missingWaveformCount = 0
    /// Lightweight per-track waveform completion. Does not republish the full `tracks` array.
    let waveformDidUpdate = PassthroughSubject<(trackId: Int, bins: [Double]), Never>()
    weak var waveformStatus: WaveformStatusModel?
    var pendingWaveformTrackIds: [Int] = []
    
    private var database: OpaquePointer?
    private var activeCollectionDefinition: CollectionDefinition?
    private var localCollectionRootFolders: [String] = []
    private var securityScopedURL: URL?
    private var isReadOnlyMode: Bool = false
    private let supportedExtensions: Set<String> = ["mp3", "wav", "ogg", "m4a", "aac", "flac"]
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    // MARK: - Thread Safety
    private let collectionDatabaseSession = CollectionDatabaseSession()
    var databaseQueue: DispatchQueue { collectionDatabaseSession.queue }
    
    // MARK: - Auto backup (throttled snapshots in Application Support; waveforms stripped in copies)
    private var lastSuccessfulAutoBackupDate: Date?
    private var isPerformingAutoBackup = false
    private static let autoBackupThrottleInterval: TimeInterval = 30 * 60
    private static let autoBackupMaxRotatedFiles = 10
    
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
            sqlite3_update_hook(db, nil, nil)
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
        
        // FULLMUTEX: serialized access so the same connection is safe across databaseQueue, main thread
        // (e.g. searchTracks vs loadAllTracks / VACUUM INTO backup). Without this, libsqlite3 may assert:
        // "illegal multi-threaded access to database connection".
        let openFlagsRW = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openFlagsRO = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        var result = sqlite3_open_v2(cleanPath, &database, openFlagsRW, nil)
        if result != SQLITE_OK {
            print("Read-write mode failed, trying read-only mode")
            result = sqlite3_open_v2(cleanPath, &database, openFlagsRO, nil)
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
        
        // Create performance indexes for track groups
        try createTrackGroupIndexes()
        
        print("Successfully opened database")
        
        // Check and migrate database schema if needed
        try migrateDatabaseSchema()
        
        installAutoBackupMutationHook()
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
        
        // Check if track groups tables exist and create them if needed
        try migrateTrackGroupsTables()

        try migratePlaylistTracksToTrackIds()

        try migrateWaveformsTable()
    }
    
    /// Creates performance indexes for track group operations
    private func createTrackGroupIndexes() throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        
        let indexes = [
            // Index for fast group lookup by main track ID
            "CREATE INDEX IF NOT EXISTS idx_track_groups_main_track_id ON \(tableTrackGroups) (main_track_id)",
            
            // Index for fast member lookup by track ID
            "CREATE INDEX IF NOT EXISTS idx_track_group_members_track_id ON \(tableTrackGroupMembers) (track_id)",
            
            // Index for fast member lookup by group ID
            "CREATE INDEX IF NOT EXISTS idx_track_group_members_group_id ON \(tableTrackGroupMembers) (group_id)",
            
            // Composite index for efficient joins
            "CREATE INDEX IF NOT EXISTS idx_track_group_members_composite ON \(tableTrackGroupMembers) (group_id, track_id)",
            
            // Index for group name searches (if needed for UI)
            "CREATE INDEX IF NOT EXISTS idx_track_groups_name ON \(tableTrackGroups) (name)",
            
            // Index for date-based queries
            "CREATE INDEX IF NOT EXISTS idx_track_groups_date_created ON \(tableTrackGroups) (date_created)"
        ]
        
        for indexSQL in indexes {
            let result = sqlite3_exec(db, indexSQL, nil, nil, nil)
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("⚠️ Failed to create index: \(errorMessage)")
                // Don't throw error as indexes are performance optimizations, not critical
            }
        }
        
        print("✅ Created performance indexes for track groups")
    }
    
    private func migrateTrackGroupsTables() throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        
        // Check if track_groups table exists
        let checkTrackGroupsTableSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='\(tableTrackGroups)'"
        var statement: OpaquePointer?
        
        var trackGroupsTableExists = false
        if sqlite3_prepare_v2(db, checkTrackGroupsTableSQL, -1, &statement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW {
                trackGroupsTableExists = true
            }
        }
        
        if !trackGroupsTableExists {
            print("🔧 Creating track_groups table...")
            let createTrackGroupsSQL = """
            CREATE TABLE \(tableTrackGroups) (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL DEFAULT '',
                main_track_id INTEGER NOT NULL,
                date_created TEXT NOT NULL,
                is_expanded INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (main_track_id) REFERENCES \(tableMusic) (id) ON DELETE CASCADE
            )
            """
            
            if sqlite3_exec(db, createTrackGroupsSQL, nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw CollectionError.queryFailed(message: "Failed to create track_groups table: \(errorMessage)")
            } else {
                print("✅ Successfully created track_groups table")
            }
        }
        
        // Check if track_group_members table exists
        let checkTrackGroupMembersTableSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='\(tableTrackGroupMembers)'"
        var membersStatement: OpaquePointer?
        
        var trackGroupMembersTableExists = false
        if sqlite3_prepare_v2(db, checkTrackGroupMembersTableSQL, -1, &membersStatement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(membersStatement) }
            if sqlite3_step(membersStatement) == SQLITE_ROW {
                trackGroupMembersTableExists = true
            }
        }
        
        if !trackGroupMembersTableExists {
            print("🔧 Creating track_group_members table...")
            let createTrackGroupMembersSQL = """
            CREATE TABLE \(tableTrackGroupMembers) (
                group_id TEXT NOT NULL,
                track_id INTEGER NOT NULL,
                PRIMARY KEY (group_id, track_id),
                FOREIGN KEY (group_id) REFERENCES \(tableTrackGroups) (id) ON DELETE CASCADE,
                FOREIGN KEY (track_id) REFERENCES \(tableMusic) (id) ON DELETE CASCADE
            )
            """
            
            if sqlite3_exec(db, createTrackGroupMembersSQL, nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw CollectionError.queryFailed(message: "Failed to create track_group_members table: \(errorMessage)")
            } else {
                print("✅ Successfully created track_group_members table")
            }
        }
    }

    private func playlistTracksCreateSQL(tableName: String, ifNotExists: Bool) -> String {
        let exists = ifNotExists ? "IF NOT EXISTS " : ""
        return """
        CREATE TABLE \(exists)\(tableName) (
            playlist_id TEXT NOT NULL,
            track_id INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (playlist_id, track_id),
            FOREIGN KEY (playlist_id) REFERENCES \(tablePlaylists)(id) ON DELETE CASCADE,
            FOREIGN KEY (track_id) REFERENCES \(tableMusic)(id) ON DELETE CASCADE
        )
        """
    }

    private func createPlaylistTracksIndex(db: OpaquePointer) throws {
        let sql = "CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_id ON \(tablePlaylistTracks)(playlist_id, sort_order)"
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("⚠️ Failed to create playlist_tracks index: \(errorMessage)")
        }
    }

    /// Idempotent: no-op once `playlist_tracks` has no `track_path` column.
    private func migratePlaylistTracksToTrackIds() throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }

        if !sqliteTableExists(tablePlaylistTracks, db: db) {
            print("🔧 Creating playlist_tracks table with track_id membership...")
            try execSQL(playlistTracksCreateSQL(tableName: tablePlaylistTracks, ifNotExists: true), db: db)
            try createPlaylistTracksIndex(db: db)
            return
        }

        let columns = sqliteColumnNames(table: tablePlaylistTracks, db: db)
        if !columns.contains("track_path") {
            try createPlaylistTracksIndex(db: db)
            return
        }

        print("🔧 Migrating playlist_tracks from track_path to track_id...")

        let musicRows = try loadMusicIdPaths(db: db)
        let lookup = PlaylistPathLookup(
            idAndPaths: musicRows,
            collectionRootPath: activeCollectionDefinition?.rootPath,
            databasePath: activeCollectionDefinition?.dbPath
        )
        let validPlaylistIds = try loadPlaylistIds(db: db)
        let oldRows = try loadLegacyPlaylistTrackPathRows(db: db)

        struct MembershipKey: Hashable {
            let playlistId: String
            let trackId: Int
        }
        var kept: [MembershipKey: Int] = [:]
        var skipped = 0
        for row in oldRows {
            if !validPlaylistIds.contains(row.playlistId) {
                skipped += 1
                print("⚠️ Dropping playlist_tracks row for missing playlist \(row.playlistId)")
                continue
            }
            guard let trackId = lookup.resolve(row.trackPath) else {
                skipped += 1
                print("⚠️ Could not resolve playlist track path to music.id, dropping: \(row.trackPath)")
                continue
            }
            let key = MembershipKey(playlistId: row.playlistId, trackId: trackId)
            if let existingOrder = kept[key] {
                if row.sortOrder < existingOrder {
                    kept[key] = row.sortOrder
                }
            } else {
                kept[key] = row.sortOrder
            }
        }

        let newTable = "playlist_tracks_new"
        sqlite3_exec(db, "PRAGMA foreign_keys = OFF", nil, nil, nil)
        if sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) != SQLITE_OK {
            sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Failed to begin playlist_tracks migration: \(errorMessage)")
        }
        var committed = false
        defer {
            if !committed {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            }
            sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
        }

        _ = sqlite3_exec(db, "DROP TABLE IF EXISTS \(newTable)", nil, nil, nil)
        try execSQL(playlistTracksCreateSQL(tableName: newTable, ifNotExists: false), db: db)

        let insertSQL = "INSERT INTO \(newTable) (playlist_id, track_id, sort_order) VALUES (?, ?, ?)"
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Failed to prepare playlist_tracks insert: \(errorMessage)")
        }
        defer { sqlite3_finalize(insertStmt) }

        let sortedKeys = kept.keys.sorted { lhs, rhs in
            if lhs.playlistId != rhs.playlistId { return lhs.playlistId < rhs.playlistId }
            return (kept[lhs] ?? 0) < (kept[rhs] ?? 0)
        }
        for key in sortedKeys {
            let sortOrder = kept[key] ?? 0
            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)
            sqlite3_bind_text(insertStmt, 1, key.playlistId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(insertStmt, 2, Int64(key.trackId))
            sqlite3_bind_int(insertStmt, 3, Int32(sortOrder))
            guard sqlite3_step(insertStmt) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw CollectionError.queryFailed(message: "Failed to insert migrated playlist track: \(errorMessage)")
            }
        }

        try execSQL("DROP TABLE \(tablePlaylistTracks)", db: db)
        try execSQL("ALTER TABLE \(newTable) RENAME TO \(tablePlaylistTracks)", db: db)
        try createPlaylistTracksIndex(db: db)

        if sqlite3_exec(db, "COMMIT", nil, nil, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Failed to commit playlist_tracks migration: \(errorMessage)")
        }
        committed = true
        print("✅ Migrated playlist_tracks to track_id (\(kept.count) rows kept, \(skipped) dropped)")
    }

    private func waveformsCreateSQL() -> String {
        """
        CREATE TABLE IF NOT EXISTS \(tableWaveforms) (
            track_id INTEGER PRIMARY KEY,
            bins BLOB NOT NULL,
            bin_count INTEGER NOT NULL,
            version INTEGER NOT NULL
        )
        """
    }

    /// Creates `waveforms` and copies legacy JSON `music.waveformData` into Float32 blobs (256 bins).
    private func migrateWaveformsTable() throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }

        try execSQL(waveformsCreateSQL(), db: db)

        let musicExists = sqliteTableExists(tableMusic, db: db)
        guard musicExists else { return }

        let columns = sqliteColumnNames(table: tableMusic, db: db)
        guard columns.contains(columnWaveformData) else { return }

        let selectSQL = """
            SELECT m.\(columnId), m.\(columnWaveformData)
            FROM \(tableMusic) m
            LEFT JOIN \(tableWaveforms) w ON w.track_id = m.\(columnId)
            WHERE w.track_id IS NULL
              AND m.\(columnWaveformData) IS NOT NULL
              AND length(m.\(columnWaveformData)) > 0
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Waveform migration select failed: \(errorMessage)")
        }
        defer { sqlite3_finalize(statement) }

        try execSQL("BEGIN", db: db)
        var migrated = 0
        do {
            let upsertSQL = """
                INSERT INTO \(tableWaveforms) (track_id, bins, bin_count, version)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(track_id) DO UPDATE SET
                    bins = excluded.bins,
                    bin_count = excluded.bin_count,
                    version = excluded.version
                """
            var upsert: OpaquePointer?
            guard sqlite3_prepare_v2(db, upsertSQL, -1, &upsert, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw CollectionError.queryFailed(message: "Waveform migration upsert failed: \(errorMessage)")
            }
            defer { sqlite3_finalize(upsert) }

            while sqlite3_step(statement) == SQLITE_ROW {
                let trackId = Int(sqlite3_column_int64(statement, 0))
                guard sqlite3_column_type(statement, 1) != SQLITE_NULL,
                      let jsonPtr = sqlite3_column_text(statement, 1) else { continue }
                let json = String(cString: jsonPtr)
                let legacy = parseLegacyWaveformJSON(json)
                let bins: [Double]
                if legacy.isEmpty {
                    bins = []
                } else {
                    bins = WaveformCodec.downsample(legacy, to: WaveformCodec.binCount)
                }
                let blob = WaveformCodec.encode(bins)
                sqlite3_reset(upsert)
                sqlite3_clear_bindings(upsert)
                sqlite3_bind_int(upsert, 1, Int32(trackId))
                blob.withUnsafeBytes { raw in
                    sqlite3_bind_blob(upsert, 2, raw.baseAddress, Int32(blob.count), SQLITE_TRANSIENT)
                }
                sqlite3_bind_int(upsert, 3, Int32(bins.count))
                sqlite3_bind_int(upsert, 4, Int32(WaveformCodec.blobVersion))
                if sqlite3_step(upsert) != SQLITE_DONE {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw CollectionError.queryFailed(message: "Waveform migration insert failed: \(errorMessage)")
                }
                migrated += 1
                if migrated % 500 == 0 {
                    print("🔧 Migrated \(migrated) waveform rows to binary store…")
                }
            }

            if migrated > 0 {
                try execSQL("UPDATE \(tableMusic) SET \(columnWaveformData) = NULL WHERE \(columnWaveformData) IS NOT NULL", db: db)
            }
            try execSQL("COMMIT", db: db)
        } catch {
            _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }

        if migrated > 0 {
            print("✅ Migrated \(migrated) waveforms from JSON to \(WaveformCodec.binCount)-bin blobs")
        }
    }

    private func parseLegacyWaveformJSON(_ jsonString: String) -> [Double] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "null" else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Double].self, from: data) else {
            return []
        }
        return decoded
    }

    private func sqliteTableExists(_ name: String, db: OpaquePointer) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func sqliteColumnNames(table: String, db: OpaquePointer) -> Set<String> {
        let sql = "PRAGMA table_info(\(table))"
        var statement: OpaquePointer?
        var names = Set<String>()
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return names }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(statement, 1) {
                names.insert(String(cString: namePtr))
            }
        }
        return names
    }

    private func execSQL(_ sql: String, db: OpaquePointer) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
    }

    private func loadMusicIdPaths(db: OpaquePointer) throws -> [(id: Int, path: String)] {
        let sql = "SELECT \(columnId), \(columnPath) FROM \(tableMusic)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [(id: Int, path: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(statement, 0))
            let path = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            rows.append((id, path))
        }
        return rows
    }

    private func loadPlaylistIds(db: OpaquePointer) throws -> Set<String> {
        guard sqliteTableExists(tablePlaylists, db: db) else { return [] }
        let sql = "SELECT id FROM \(tablePlaylists)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        var ids = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let ptr = sqlite3_column_text(statement, 0) {
                ids.insert(String(cString: ptr))
            }
        }
        return ids
    }

    private func loadLegacyPlaylistTrackPathRows(db: OpaquePointer) throws -> [(playlistId: String, trackPath: String, sortOrder: Int)] {
        let sql = """
            SELECT playlist_id, track_path, sort_order
            FROM \(tablePlaylistTracks)
            ORDER BY playlist_id, sort_order ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [(playlistId: String, trackPath: String, sortOrder: Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let playlistId = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let trackPath = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let sortOrder = Int(sqlite3_column_int(statement, 2))
            rows.append((playlistId, trackPath, sortOrder))
        }
        return rows
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

        let createPlaylistTracksSQL = playlistTracksCreateSQL(tableName: tablePlaylistTracks, ifNotExists: true)

        let createLocalRootsSQL = """
        CREATE TABLE IF NOT EXISTS \(tableLocalRoots) (
            path TEXT PRIMARY KEY
        )
        """

        let createTrackGroupsSQL = """
        CREATE TABLE IF NOT EXISTS \(tableTrackGroups) (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL DEFAULT '',
            main_track_id INTEGER NOT NULL,
            date_created TEXT NOT NULL,
            is_expanded INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (main_track_id) REFERENCES \(tableMusic) (id) ON DELETE CASCADE
        )
        """

        let createTrackGroupMembersSQL = """
        CREATE TABLE IF NOT EXISTS \(tableTrackGroupMembers) (
            group_id TEXT NOT NULL,
            track_id INTEGER NOT NULL,
            PRIMARY KEY (group_id, track_id),
            FOREIGN KEY (group_id) REFERENCES \(tableTrackGroups) (id) ON DELETE CASCADE,
            FOREIGN KEY (track_id) REFERENCES \(tableMusic) (id) ON DELETE CASCADE
        )
        """

        let createWaveformsSQL = waveformsCreateSQL()

        let statements = [createMusicSQL, createPlaylistsSQL, createPlaylistTracksSQL, createLocalRootsSQL, createTrackGroupsSQL, createTrackGroupMembersSQL, createWaveformsSQL]
        for sql in statements {
            print("[DBCreate] Executing SQL: \(sql.replacingOccurrences(of: "\n", with: " "))")
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                let err = String(cString: sqlite3_errmsg(db))
                throw CollectionError.queryFailed(message: "Schema creation failed: \(err)")
            }
        }
        try createPlaylistTracksIndex(db: db)

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
                    
                    let query = self.selectTracksFromMusicSQL
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
                            let id = Int(sqlite3_column_int(statement, 0))
                            let title = String(cString: sqlite3_column_text(statement, 1))
                            let artist = String(cString: sqlite3_column_text(statement, 2))
                            let album = String(cString: sqlite3_column_text(statement, 3))
                            var rawData = "ID: \(id), Title: '\(title)', Artist: '\(artist)', Album: '\(album)'"
                            
                            if sqlite3_column_type(statement, 17) != SQLITE_NULL {
                                let tagsData = String(cString: sqlite3_column_text(statement, 17))
                                rawData += ", Tags: '\(tagsData)'"
                            }
                            if sqlite3_column_type(statement, 14) != SQLITE_NULL {
                                let markersData = String(cString: sqlite3_column_text(statement, 14))
                                rawData += ", Markers: '\(markersData)'"
                            }
                            
                            failedTracks.append((id: id, title: title, error: error.localizedDescription, rawData: rawData))
                            print("❌ Failed to parse track at row \(rowCount): \(error)")
                            print("❌ Track details - \(rawData)")
                        }
                    }
                    
                    if !failedTracks.isEmpty {
                        print("🚨 DATABASE LOADING ERRORS SUMMARY:")
                        print("🚨 Total tracks processed: \(rowCount)")
                        print("🚨 Successfully loaded: \(loadedTracks.count)")
                        print("🚨 Failed to load: \(failedTracks.count)")
                        for failed in failedTracks {
                            print("   - ID: \(failed.id), Title: '\(failed.title)'")
                            print("     Error: \(failed.error)")
                            print("     Raw data: \(failed.rawData)")
                        }
                    }
                    
                    let sortedTracks = loadedTracks.sorted()
                    DispatchQueue.main.async {
                        self.tracks = sortedTracks
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
                            \(self.columnTitle), \(self.columnArtist), \(self.columnAlbum), \(self.columnAlbumArtist), \(self.columnComposer), \(self.columnGenre), \(self.columnYear), \(self.columnTrackNumber), \(self.columnDiscNumber), \(self.columnBpm), \(self.columnPath), \(self.columnIsUrl), \(self.columnDuration), \(self.columnTimeMarkers), \(self.columnRating), \(self.columnComment), \(self.columnGeneralTags), \(self.columnDateAdded)
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, '[]', 0, '', '[]', ?)
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
                        waveformStatus: .missing,
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
        
        // Clean up track group relationships before deleting the track
        try cleanupTrackGroupRelationships(trackId: id)
        deleteWaveformRow(trackId: id, db: db)
        
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
    
    /// Deletes a track from the database and moves the file to trash
    func deleteTrackAndMoveToTrash(_ id: Int) throws {
        // First, get the track information before deleting from database
        guard let track = tracks.first(where: { $0.id == id }) else {
            throw CollectionError.queryFailed(message: "Track with ID \(id) not found")
        }
        
        // Only move local files to trash (not URLs)
        if !track.isUrl {
            let fileURL = URL(fileURLWithPath: track.path)
            
            // Check if file exists before trying to move to trash
            if FileManager.default.fileExists(atPath: track.path) {
                do {
                    try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                    print("✅ Moved file to trash: \(track.path)")
                } catch {
                    print("⚠️ Failed to move file to trash: \(track.path) - \(error)")
                    // Continue with database deletion even if trash operation fails
                }
            } else {
                print("⚠️ File does not exist on disk, skipping trash operation: \(track.path)")
            }
        } else {
            print("ℹ️ Skipping trash operation for URL track: \(track.path)")
        }
        
        // Delete from database
        try deleteTrack(id)
    }
    
    /// Updates published `tracks` after DB deletion without `loadAllTracks()` (avoids global loading spinner and full table reload).
    @MainActor
    func removeTracksFromMemory(trackIds: [Int]) {
        guard !trackIds.isEmpty else { return }
        let idSet = Set(trackIds)
        tracks = tracks.filter { track in
            guard let tid = track.id else { return true }
            return !idSet.contains(tid)
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
        
        let rating = Int(sqlite3_column_int(statement, 15))
        let comment = sqlite3_column_type(statement, 16) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 16)) : ""
        
        // Parse general tags with enhanced error handling
        let generalTags: [String]
        if sqlite3_column_type(statement, 17) != SQLITE_NULL {
            let tagsJson = String(cString: sqlite3_column_text(statement, 17))
            do {
                generalTags = try parseGeneralTags(from: tagsJson)
            } catch {
                print("🚨 Failed to parse general tags for track \(id): \(error)")
                print("🚨 Raw tags data: '\(tagsJson)'")
                throw CollectionError.invalidData
            }
        } else {
            generalTags = []
        }
        
        // Parse dateAdded with fallback to a reasonable default date for existing tracks
        let dateAdded: Date
        if sqlite3_column_type(statement, 18) != SQLITE_NULL {
            let dateString = String(cString: sqlite3_column_text(statement, 18))
            if let parsedDate = iso8601DateFormatter.date(from: dateString) {
                dateAdded = parsedDate
            } else {
                dateAdded = Date().addingTimeInterval(-86400 * 30)
            }
        } else {
            dateAdded = Date().addingTimeInterval(-86400 * 30)
        }

        let waveformStatus = WaveformStatus(rawValue: Int(sqlite3_column_int(statement, 19))) ?? .missing
        
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
            waveformStatus: waveformStatus,
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
            } else {
                // Try parsing as plain comma-separated string (not JSON array)
                let tags = cleanedString.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !tags.isEmpty {
                    print("🔧 Parsed as comma-separated string, found tags: \(tags)")
                    return tags
                }
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
            waveformStatus: track.waveformStatus,
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
            \(selectTracksFromMusicSQL)
            WHERE LOWER(\(tableMusic).title) LIKE ? OR LOWER(\(tableMusic).artist) LIKE ? OR LOWER(\(tableMusic).album) LIKE ? OR LOWER(\(tableMusic).comment) LIKE ?
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

    private func refreshMissingWaveformCount() {
        let count = tracks.reduce(into: 0) { result, track in
            if track.needsWaveformAnalysis {
                result += 1
            }
        }
        if missingWaveformCount != count {
            missingWaveformCount = count
            waveformStatus?.missingCount = count
        }
    }

    func syncMissingWaveformCount() {
        refreshMissingWaveformCount()
        waveformStatus?.missingCount = missingWaveformCount
    }
    
    // MARK: - Track Updates
    func updateTrackWaveformData(trackId: Int, waveformData: [Double]) async throws {
        print("[CollectionService] 💾 Updating waveform data for track \(trackId), data size: \(waveformData.count)")
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    let securityAccess = self.ensureSecurityAccess()
                    defer { if securityAccess { self.stopSecurityAccess() } }
                    
                    guard let db = self.database else {
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    if self.isReadOnlyMode {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot update waveform in read-only mode."))
                        return
                    }

                    try self.upsertWaveformBlob(trackId: trackId, bins: waveformData, db: db)
                    let status: WaveformStatus = waveformData.isEmpty ? .empty : .ready

                    Task { @MainActor in
                        if let index = self._tracks.firstIndex(where: { $0.id == trackId }) {
                            let updated = self._tracks[index].withWaveformStatus(status)
                            self._tracks[index] = updated
                            if let id = updated.id {
                                self.tracksById[id] = updated
                            }
                            self.refreshMissingWaveformCount()
                            self.waveformDidUpdate.send((trackId, waveformData))
                        }
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Loads packed waveform samples for the given track ids. Missing rows are omitted.
    func loadWaveformBins(ids: [Int]) async -> [Int: [Double]] {
        let unique = Array(Set(ids.filter { $0 >= 0 }))
        guard !unique.isEmpty else { return [:] }
        return await withCheckedContinuation { continuation in
            databaseQueue.async {
                continuation.resume(returning: self.fetchWaveformBinsSync(ids: unique))
            }
        }
    }

    private func fetchWaveformBinsSync(ids: [Int]) -> [Int: [Double]] {
        guard let db = database, !ids.isEmpty else { return [:] }
        var result: [Int: [Double]] = [:]
        let chunkSize = 80
        var start = 0
        while start < ids.count {
            let end = min(start + chunkSize, ids.count)
            let chunk = Array(ids[start..<end])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let sql = "SELECT track_id, bins FROM \(tableWaveforms) WHERE track_id IN (\(placeholders))"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                defer { sqlite3_finalize(statement) }
                for (index, id) in chunk.enumerated() {
                    sqlite3_bind_int(statement, Int32(index + 1), Int32(id))
                }
                while sqlite3_step(statement) == SQLITE_ROW {
                    let trackId = Int(sqlite3_column_int64(statement, 0))
                    let byteCount = Int(sqlite3_column_bytes(statement, 1))
                    if byteCount > 0, let ptr = sqlite3_column_blob(statement, 1) {
                        let data = Data(bytes: ptr, count: byteCount)
                        result[trackId] = WaveformCodec.decode(data)
                    } else {
                        result[trackId] = []
                    }
                }
            }
            start = end
        }
        return result
    }

    private func upsertWaveformBlob(trackId: Int, bins: [Double], db: OpaquePointer) throws {
        let blob = WaveformCodec.encode(bins)
        let sql = """
            INSERT INTO \(tableWaveforms) (track_id, bins, bin_count, version)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(track_id) DO UPDATE SET
                bins = excluded.bins,
                bin_count = excluded.bin_count,
                version = excluded.version
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CollectionError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(trackId))
        blob.withUnsafeBytes { raw in
            sqlite3_bind_blob(statement, 2, raw.baseAddress, Int32(blob.count), SQLITE_TRANSIENT)
        }
        sqlite3_bind_int(statement, 3, Int32(bins.count))
        sqlite3_bind_int(statement, 4, Int32(WaveformCodec.blobVersion))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CollectionError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func deleteWaveformRow(trackId: Int, db: OpaquePointer) {
        var statement: OpaquePointer?
        let sql = "DELETE FROM \(tableWaveforms) WHERE track_id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(trackId))
        _ = sqlite3_step(statement)
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
                    
                    // Update the track in the local array on the main thread.
                    // Assign a new array so @Published emits; subscript-only mutation may not notify $tracks subscribers.
                    Task { @MainActor in
                        if let index = self.tracks.firstIndex(where: { $0.id == trackId }) {
                            let updates = ["rating": newRating as Any]
                            var updatedTracks = self.tracks
                            updatedTracks[index] = updatedTracks[index].withUpdates(updates)
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
                    
                    // Update the track in the local array on the main thread.
                    // Assign a new array so @Published emits; subscript-only mutation may not notify $tracks subscribers.
                    Task { @MainActor in
                        if let index = self.tracks.firstIndex(where: { $0.id == trackId }) {
                            var updatedTracks = self.tracks
                            updatedTracks[index] = updatedTracks[index].withUpdates(updates)
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
                    let testQuery = "\(self.selectTracksFromMusicSQL) WHERE \(self.tableMusic).\(self.columnId) = ?"
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
                        // Update track in place using withUpdates method
                        let updates = ["generalTags": newTags as Any]
                        self.tracks[index] = self.tracks[index].withUpdates(updates)
                        print("[CollectionService] track \(trackId) updated, new tags: \(self.tracks[index].generalTags)")
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
                \(self.columnTimeMarkers) = '[]'
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
        deleteWaveformRow(trackId: trackId, db: db)
        
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
                    waveformStatus: .missing,
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
                        SELECT \(self.columnId), \(self.columnTitle), \(self.columnGeneralTags), \(self.columnTimeMarkers)
                        FROM \(self.tableMusic)
                        WHERE (\(self.columnGeneralTags) IS NOT NULL AND \(self.columnGeneralTags) != '[]' AND \(self.columnGeneralTags) != '')
                           OR (\(self.columnTimeMarkers) IS NOT NULL AND \(self.columnTimeMarkers) != '[]' AND \(self.columnTimeMarkers) != '')
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
                    
                    let query = "SELECT \(self.columnId), \(self.columnTitle), \(self.columnArtist), \(self.columnGeneralTags), \(self.columnTimeMarkers) FROM \(self.tableMusic)"
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
                    self.deleteWaveformRow(trackId: trackId, db: db)
                    
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
                                waveformStatus: .missing,
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
    
    /// Clears all waveform data from the database to force regeneration with time-based mapping
    func clearAllWaveformData() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    if self.isReadOnlyMode { 
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot clear waveform data in read-only mode."))
                        return
                    }
                    
                    print("🧹 Clearing all waveform data to regenerate with time-based mapping...")
                    
                    if sqlite3_exec(db, "DELETE FROM \(self.tableWaveforms)", nil, nil, nil) != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    let updatedCount = sqlite3_changes(db)
                    print("✅ Cleared waveform data for \(updatedCount) tracks")
                    
                    // Update all tracks in memory to clear waveform data
                    Task { @MainActor in
                        var updatedTracks = self.tracks
                        for i in 0..<updatedTracks.count {
                            updatedTracks[i] = Track(
                                id: self.tracks[i].id,
                                title: self.tracks[i].title,
                                artist: self.tracks[i].artist,
                                album: self.tracks[i].album,
                                albumArtist: self.tracks[i].albumArtist,
                                composer: self.tracks[i].composer,
                                genre: self.tracks[i].genre,
                                year: self.tracks[i].year,
                                trackNumber: self.tracks[i].trackNumber,
                                discNumber: self.tracks[i].discNumber,
                                bpm: self.tracks[i].bpm,
                                path: self.tracks[i].path,
                                isUrl: self.tracks[i].isUrl,
                                duration: self.tracks[i].duration,
                                timeMarkers: self.tracks[i].timeMarkers,
                                waveformStatus: .missing,
                                rating: self.tracks[i].rating,
                                comment: self.tracks[i].comment,
                                generalTags: self.tracks[i].generalTags,
                                dateAdded: self.tracks[i].dateAdded
                            )
                        }
                        self.tracks = updatedTracks
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
    
    // MARK: - File Renaming
    
    /// Renames a file based on the new title and updates both file metadata and database
    func renameFileForTrack(trackId: Int, newTitle: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    if self.isReadOnlyMode { 
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot rename files in read-only mode."))
                        return
                    }
                    
                    // Get the current track information
                    guard let currentTrack = self.tracks.first(where: { $0.id == trackId }) else {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Track with ID \(trackId) not found"))
                        return
                    }
                    
                    // Only rename local files (not URLs)
                    guard !currentTrack.isUrl else {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot rename URL tracks"))
                        return
                    }
                    
                    print("🔄 [CollectionService] Renaming file for track \(trackId): '\(currentTrack.title)' -> '\(newTitle)'")
                    
                    // Resolve the current absolute path
                    let currentAbsolutePath = self.resolveTrackPathForWaveform(currentTrack)
                    print("🔄 [CollectionService] Current file path: \(currentAbsolutePath)")
                    let currentURL = URL(fileURLWithPath: currentAbsolutePath)
                    
                    // Check if the current file exists
                    guard FileManager.default.fileExists(atPath: currentAbsolutePath) else {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Current file does not exist: \(currentAbsolutePath)"))
                        return
                    }
                    
                    // Generate the new filename
                    let fileExtension = currentURL.pathExtension
                    let sanitizedTitle = self.sanitizeFilename(newTitle)
                    
                    // Ensure we have a valid filename
                    guard !sanitizedTitle.isEmpty else {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Invalid title: cannot create filename from empty or invalid characters"))
                        return
                    }
                    
                    let newFilename = "\(sanitizedTitle).\(fileExtension)"
                    let newURL = currentURL.deletingLastPathComponent().appendingPathComponent(newFilename)
                    
                    // Check if the new filename already exists and generate a unique name if needed
                    let finalURL = self.generateUniqueFilename(baseURL: newURL)
                    let finalPath = finalURL.path
                    
                    print("🔄 [CollectionService] Final file path: \(finalPath)")
                    
                    // Step 1: Update the file metadata first (before moving the file)
                    do {
                        try self.updateFileMetadata(at: currentURL, title: newTitle)
                        print("✅ [CollectionService] Successfully updated file metadata")
                    } catch {
                        print("⚠️ [CollectionService] Failed to update file metadata: \(error)")
                        // Continue with file rename even if metadata update fails
                    }
                    
                    // Step 2: Rename the file
                    do {
                        try FileManager.default.moveItem(at: currentURL, to: finalURL)
                        print("✅ [CollectionService] Successfully renamed file from '\(currentURL.path)' to '\(finalPath)'")
                    } catch {
                        print("❌ [CollectionService] Failed to rename file: \(error)")
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Failed to rename file: \(error.localizedDescription)"))
                        return
                    }
                    
                    // Step 3: Update the database with both new title and new path
                    let newRelativePath = self.convertToRelativePath(finalPath)
                    try self.updateTrackTitleAndPath(trackId: trackId, newTitle: newTitle, newPath: newRelativePath)
                    
                    print("✅ [CollectionService] Successfully updated database title and path for track \(trackId)")
                    
                    // Step 4: Patch in-memory track list (avoids full reload, isLoading spinner, and table churn)
                    DispatchQueue.main.async {
                        self.applyRenamedTrackInMemory(trackId: trackId, newTitle: newTitle, newRelativePath: newRelativePath)
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Updates `tracks` after a DB/file rename so callers do not need `loadAllTracks()` (no loading spinner, minimal UI churn).
    private func applyRenamedTrackInMemory(trackId: Int, newTitle: String, newRelativePath: String) {
        guard let index = tracks.firstIndex(where: { $0.id == trackId }) else {
            print("⚠️ [CollectionService] applyRenamedTrackInMemory: track \(trackId) not in memory")
            return
        }
        let base = tracks[index]
        let withRelativePath = Track(
            id: base.id,
            title: newTitle,
            artist: base.artist,
            album: base.album,
            albumArtist: base.albumArtist,
            composer: base.composer,
            genre: base.genre,
            year: base.year,
            trackNumber: base.trackNumber,
            discNumber: base.discNumber,
            bpm: base.bpm,
            path: newRelativePath,
            isUrl: base.isUrl,
            duration: base.duration,
            timeMarkers: base.timeMarkers,
            waveformStatus: base.waveformStatus,
            rating: base.rating,
            comment: base.comment,
            generalTags: base.generalTags,
            dateAdded: base.dateAdded
        )
        var updatedTracks = tracks
        updatedTracks[index] = resolveTrackPath(withRelativePath)
        tracks = updatedTracks.sorted()
    }
    
    /// Sanitizes a filename by removing invalid characters
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var sanitized = filename.components(separatedBy: invalidCharacters).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ") // Replace multiple spaces with single space
        
        // Remove leading/trailing dots and spaces
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        
        // Ensure the filename doesn't start with a dot (hidden files)
        if sanitized.hasPrefix(".") {
            sanitized = "_" + sanitized
        }
        
        // Limit filename length to avoid filesystem issues
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }
        
        return sanitized
    }
    
    /// Generates a unique filename by appending a number if the file already exists
    private func generateUniqueFilename(baseURL: URL) -> URL {
        var finalURL = baseURL
        var counter = 1
        
        while FileManager.default.fileExists(atPath: finalURL.path) {
            let filename = baseURL.deletingPathExtension().lastPathComponent
            let fileExtension = baseURL.pathExtension
            let newFilename = "\(filename) (\(counter)).\(fileExtension)"
            finalURL = baseURL.deletingLastPathComponent().appendingPathComponent(newFilename)
            counter += 1
        }
        
        return finalURL
    }
    
    /// Updates the file metadata (ID3 tags) with the new title
    private func updateFileMetadata(at url: URL, title: String) throws {
        print("🔄 [CollectionService] Updating file metadata for: \(url.lastPathComponent)")
        print("🔄 [CollectionService] New title: \(title)")
        
        // Check if the file is writable by checking file permissions
        guard FileManager.default.isWritableFile(atPath: url.path) else {
            print("⚠️ [CollectionService] File is not writable, skipping metadata update")
            return
        }
        
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "mp3":
            // Use ID3TagEditor for MP3 files
            try updateMP3Metadata(at: url, title: title)
        case "m4a", "aac", "wav", "aiff":
            // Use AVFoundation for other formats
            try updateAVFoundationMetadata(at: url, title: title)
        default:
            print("⚠️ [CollectionService] Unsupported file format for metadata update: \(fileExtension)")
            return
        }
    }
    
    /// Updates MP3 metadata using ID3TagEditor
    private func updateMP3Metadata(at url: URL, title: String) throws {
        print("🔄 [CollectionService] Updating MP3 metadata using ID3TagEditor")
        
        let id3TagEditor = ID3TagEditor()
        
        do {
            // Read existing metadata
            let existingTag = try id3TagEditor.read(from: url.path)
            
            if let existingTag = existingTag {
                // Update existing tag with new title
                var updatedTag = existingTag
                updatedTag.frames[.title] = ID3FrameWithStringContent(content: title)
                try id3TagEditor.write(tag: updatedTag, to: url.path)
                print("✅ [CollectionService] Successfully updated existing MP3 metadata")
            } else {
                // Cannot create new tags due to internal initializer access
                print("⚠️ [CollectionService] No existing MP3 metadata found - cannot create new tags due to library limitations")
                print("⚠️ [CollectionService] File will be renamed but metadata won't be created")
            }
            
        } catch {
            print("❌ [CollectionService] Failed to update MP3 metadata: \(error)")
            // Don't throw error - file renaming should still work even if metadata update fails
            print("⚠️ [CollectionService] Continuing with file rename despite metadata update failure")
        }
    }
    
    /// Updates metadata for non-MP3 files using AVFoundation
    private func updateAVFoundationMetadata(at url: URL, title: String) throws {
        print("🔄 [CollectionService] Updating metadata using AVFoundation")
        
        // Use AVFoundation to update file metadata
        let asset = AVURLAsset(url: url)
        
        // Create a mutable metadata item for the title
        let titleMetadata = AVMutableMetadataItem()
        titleMetadata.identifier = .commonIdentifierTitle
        titleMetadata.value = title as NSString
        titleMetadata.locale = Locale.current
        
        // Get existing metadata and update it
        var metadata = asset.metadata
        metadata.removeAll { item in
            item.identifier == .commonIdentifierTitle
        }
        metadata.append(titleMetadata)
        
        // Create export session to write the metadata
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            print("⚠️ [CollectionService] Could not create export session for metadata update")
            return
        }
        
        // Create temporary file for the export
        let tempURL = url.appendingPathExtension("temp")
        exportSession.outputURL = tempURL
        
        // Determine the correct file type based on the original file extension
        let fileExtension = url.pathExtension.lowercased()
        let outputFileType: AVFileType
        switch fileExtension {
        case "m4a", "aac":
            outputFileType = .m4a
        case "wav":
            outputFileType = .wav
        case "aiff":
            outputFileType = .aiff
        default:
            print("⚠️ [CollectionService] Unsupported file format for AVFoundation metadata update: \(fileExtension)")
            return
        }
        
        exportSession.outputFileType = outputFileType
        exportSession.metadata = metadata
        
        // Use a semaphore to make this synchronous
        let semaphore = DispatchSemaphore(value: 0)
        var exportError: Error?
        
        exportSession.exportAsynchronously {
            if exportSession.status == .completed {
                // Replace original file with the updated one
                do {
                    _ = try FileManager.default.replaceItem(at: url, withItemAt: tempURL, backupItemName: nil, options: [], resultingItemURL: nil)
                    print("✅ [CollectionService] Successfully updated file metadata")
                } catch {
                    print("❌ [CollectionService] Failed to replace file with updated metadata: \(error)")
                    exportError = error
                }
            } else {
                print("❌ [CollectionService] Export failed with status: \(exportSession.status.rawValue)")
                if let error = exportSession.error {
                    print("❌ [CollectionService] Export error: \(error)")
                    exportError = error
                }
            }
            semaphore.signal()
        }
        
        // Wait for export to complete (with timeout)
        let result = semaphore.wait(timeout: .now() + 30)
        if result == .timedOut {
            exportSession.cancelExport()
            throw CollectionError.queryFailed(message: "Metadata update timed out")
        }
        
        if let error = exportError {
            throw error
        }
    }
    
    /// Fixes corrupted tag data in the database by converting comma-separated strings to JSON
    func fixCorruptedTagData() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else { 
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    if self.isReadOnlyMode { 
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot fix corrupted data in read-only mode."))
                        return
                    }
                    
                    print("🔧 [CollectionService] Fixing corrupted tag data...")
                    
                    // Find tracks with comma-separated tags (not JSON)
                    let query = "SELECT \(self.columnId), \(self.columnGeneralTags) FROM \(self.tableMusic) WHERE \(self.columnGeneralTags) IS NOT NULL AND \(self.columnGeneralTags) != '[]' AND \(self.columnGeneralTags) != ''"
                    var statement: OpaquePointer?
                    
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    var fixedCount = 0
                    
                    while sqlite3_step(statement) == SQLITE_ROW {
                        let trackId = Int(sqlite3_column_int(statement, 0))
                        let tagsData = String(cString: sqlite3_column_text(statement, 1))
                        
                        // Check if this is comma-separated data (not JSON)
                        if !tagsData.hasPrefix("[") || !tagsData.hasSuffix("]") {
                            // Convert comma-separated string to JSON array
                            let tags = tagsData.components(separatedBy: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            
                            if !tags.isEmpty {
                                let encoder = JSONEncoder()
                                let jsonData = try encoder.encode(tags)
                                let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
                                
                                // Update the database
                                let updateSQL = "UPDATE \(self.tableMusic) SET \(self.columnGeneralTags) = ? WHERE \(self.columnId) = ?"
                                var updateStatement: OpaquePointer?
                                
                                if sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK {
                                    defer { sqlite3_finalize(updateStatement) }
                                    sqlite3_bind_text(updateStatement, 1, jsonString, -1, self.SQLITE_TRANSIENT)
                                    sqlite3_bind_int(updateStatement, 2, Int32(trackId))
                                    
                                    if sqlite3_step(updateStatement) == SQLITE_DONE {
                                        print("🔧 [CollectionService] Fixed tags for track \(trackId): '\(tagsData)' -> '\(jsonString)'")
                                        fixedCount += 1
                                    }
                                }
                            }
                        }
                    }
                    
                    print("✅ [CollectionService] Fixed \(fixedCount) tracks with corrupted tag data")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Updates both the title and path in the database
    private func updateTrackTitleAndPath(trackId: Int, newTitle: String, newPath: String) throws {
        guard let db = self.database else { throw CollectionError.databaseNotOpen }
        if self.isReadOnlyMode { throw CollectionError.queryFailed(message: "Cannot update in read-only mode.") }
        
        var stmt: OpaquePointer?
        let sql = "UPDATE \(self.tableMusic) SET \(self.columnTitle) = ?, \(self.columnPath) = ? WHERE \(self.columnId) = ?"
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: err)
        }
        defer { sqlite3_finalize(stmt) }
        
        // Bind parameters
        sqlite3_bind_text(stmt, 1, newTitle, -1, self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, newPath, -1, self.SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 3, Int32(trackId))
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let err = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: err)
        }
        
        print("✅ [CollectionService] Updated database: title='\(newTitle)', path='\(newPath)' for track \(trackId)")
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
    
    // MARK: - Track Data Refresh
    
    func refreshTrackData(trackId: Int) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else {
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    
                    // Get the track to refresh
                    let trackQuery = "SELECT * FROM \(self.tableMusic) WHERE \(self.columnId) = ?"
                    var statement: OpaquePointer?
                    
                    guard sqlite3_prepare_v2(db, trackQuery, -1, &statement, nil) == SQLITE_OK else {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    defer { sqlite3_finalize(statement) }
                    
                    sqlite3_bind_int(statement, 1, Int32(trackId))
                    
                    guard sqlite3_step(statement) == SQLITE_ROW else {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Track not found with ID: \(trackId)"))
                        return
                    }
                    
                    // Extract track data
                    let path = String(cString: sqlite3_column_text(statement, 11)) // columnPath
                    let isUrl = sqlite3_column_int(statement, 12) != 0 // columnIsUrl
                    
                    // Only refresh local files
                    guard !isUrl else {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Cannot refresh URL tracks"))
                        return
                    }
                    
                    // Create a temporary Track object for path resolution
                    let tempTrack = Track(
                        id: trackId,
                        title: String(cString: sqlite3_column_text(statement, 1)), // columnTitle
                        artist: String(cString: sqlite3_column_text(statement, 2)), // columnArtist
                        album: String(cString: sqlite3_column_text(statement, 3)), // columnAlbum
                        albumArtist: sqlite3_column_type(statement, 4) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 4)) : nil, // columnAlbumArtist
                        composer: sqlite3_column_type(statement, 5) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 5)) : nil, // columnComposer
                        genre: sqlite3_column_type(statement, 6) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 6)) : nil, // columnGenre
                        year: sqlite3_column_type(statement, 7) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 7)) : nil, // columnYear
                        trackNumber: sqlite3_column_type(statement, 8) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 8)) : nil, // columnTrackNumber
                        discNumber: sqlite3_column_type(statement, 9) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 9)) : nil, // columnDiscNumber
                        bpm: sqlite3_column_type(statement, 10) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 10)) : nil, // columnBpm
                        path: path,
                        isUrl: isUrl,
                        duration: Int(sqlite3_column_int(statement, 13)), // columnDuration
                        timeMarkers: [], // We'll keep existing markers
                        waveformStatus: .missing, // Will be cleared
                        rating: Int(sqlite3_column_int(statement, 16)), // columnRating
                        comment: sqlite3_column_type(statement, 17) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 17)) : "", // columnComment
                        generalTags: [], // We'll keep existing tags
                        dateAdded: Date() // We'll use current date for refreshed tracks
                    )
                    
                    // Resolve the absolute path
                    let absolutePath = self.resolveTrackPathForWaveform(tempTrack)
                    let fm = FileManager.default
                    guard fm.fileExists(atPath: absolutePath) else {
                        continuation.resume(throwing: CollectionError.queryFailed(message: "File not found at path: \(absolutePath)"))
                        return
                    }
                    
                    // Compute new duration and extract metadata via AVFoundation
                    let url = URL(fileURLWithPath: absolutePath)
                    let asset = AVURLAsset(url: url)
                    let durationSeconds = CMTimeGetSeconds(asset.duration)
                    let durationMs = durationSeconds.isFinite && durationSeconds > 0 ? Int(durationSeconds * 1000) : 0
                    let meta = self.extractAudioMetadata(from: asset)
                    
                    // Update the track with new duration and metadata
                    let updateSQL = """
                        UPDATE \(self.tableMusic) SET
                            \(self.columnTitle) = ?,
                            \(self.columnArtist) = ?,
                            \(self.columnAlbum) = ?,
                            \(self.columnAlbumArtist) = ?,
                            \(self.columnComposer) = ?,
                            \(self.columnGenre) = ?,
                            \(self.columnYear) = ?,
                            \(self.columnTrackNumber) = ?,
                            \(self.columnDiscNumber) = ?,
                            \(self.columnBpm) = ?,
                            \(self.columnDuration) = ?
                        WHERE \(self.columnId) = ?
                    """
                    
                    var updateStatement: OpaquePointer?
                    guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK else {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    defer { sqlite3_finalize(updateStatement) }
                    
                    // Bind parameters
                    let filenameTitle = URL(fileURLWithPath: absolutePath).deletingPathExtension().lastPathComponent
                    let title = meta.title ?? filenameTitle
                    
                    // 1 title
                    title.withCString { sqlite3_bind_text(updateStatement, 1, $0, -1, self.SQLITE_TRANSIENT) }
                    // 2 artist
                    if let v = meta.artist { v.withCString { sqlite3_bind_text(updateStatement, 2, $0, -1, self.SQLITE_TRANSIENT) } } else { "Unknown".withCString { sqlite3_bind_text(updateStatement, 2, $0, -1, self.SQLITE_TRANSIENT) } }
                    // 3 album
                    if let v = meta.album { v.withCString { sqlite3_bind_text(updateStatement, 3, $0, -1, self.SQLITE_TRANSIENT) } } else { "Unknown".withCString { sqlite3_bind_text(updateStatement, 3, $0, -1, self.SQLITE_TRANSIENT) } }
                    // 4 albumArtist
                    if let v = meta.albumArtist { v.withCString { sqlite3_bind_text(updateStatement, 4, $0, -1, self.SQLITE_TRANSIENT) } } else { sqlite3_bind_null(updateStatement, 4) }
                    // 5 composer
                    if let v = meta.composer { v.withCString { sqlite3_bind_text(updateStatement, 5, $0, -1, self.SQLITE_TRANSIENT) } } else { sqlite3_bind_null(updateStatement, 5) }
                    // 6 genre
                    if let v = meta.genre { v.withCString { sqlite3_bind_text(updateStatement, 6, $0, -1, self.SQLITE_TRANSIENT) } } else { sqlite3_bind_null(updateStatement, 6) }
                    // 7 year
                    if let v = meta.year { sqlite3_bind_int(updateStatement, 7, Int32(v)) } else { sqlite3_bind_null(updateStatement, 7) }
                    // 8 trackNumber
                    if let v = meta.trackNumber { sqlite3_bind_int(updateStatement, 8, Int32(v)) } else { sqlite3_bind_null(updateStatement, 8) }
                    // 9 discNumber
                    if let v = meta.discNumber { sqlite3_bind_int(updateStatement, 9, Int32(v)) } else { sqlite3_bind_null(updateStatement, 9) }
                    // 10 bpm
                    if let v = meta.bpm { sqlite3_bind_int(updateStatement, 10, Int32(v)) } else { sqlite3_bind_null(updateStatement, 10) }
                    // 11 duration
                    sqlite3_bind_int(updateStatement, 11, Int32(durationMs))
                    // 12 trackId
                    sqlite3_bind_int(updateStatement, 12, Int32(trackId))
                    
                    guard sqlite3_step(updateStatement) == SQLITE_DONE else {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    self.deleteWaveformRow(trackId: trackId, db: db)
                    
                    print("✅ [CollectionService] Refreshed track data for ID \(trackId): duration=\(durationMs)ms")
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Update the track in memory on the main thread after database operations complete
        await MainActor.run {
            if let index = self.tracks.firstIndex(where: { $0.id == trackId }) {
                // Create updated track with cleared waveform data
                let updatedTrack = Track(
                    id: self.tracks[index].id,
                    title: self.tracks[index].title, // Keep existing title for now, will be updated when tracks reload
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
                    duration: self.tracks[index].duration, // Will be updated when tracks reload
                    timeMarkers: self.tracks[index].timeMarkers,
                    waveformStatus: .missing, // Clear waveform data to show "Analyzing..."
                    rating: self.tracks[index].rating,
                    comment: self.tracks[index].comment,
                    generalTags: self.tracks[index].generalTags,
                    dateAdded: self.tracks[index].dateAdded
                )
                self.tracks[index] = updatedTrack
                print("🔄 [CollectionService] Updated track in memory for ID \(trackId) with cleared waveform data")
            }
        }
    }
    
    // MARK: - Track Group Database Operations
    
    /// Load all track groups from the database
    func loadTrackGroups() async throws -> [TrackGroup] {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else {
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    
                    let query = """
                    SELECT tg.id, tg.name, tg.main_track_id, tg.date_created, tg.is_expanded,
                           GROUP_CONCAT(tgm.track_id) as track_ids
                    FROM \(self.tableTrackGroups) tg
                    LEFT JOIN \(self.tableTrackGroupMembers) tgm ON tg.id = tgm.group_id
                    GROUP BY tg.id, tg.name, tg.main_track_id, tg.date_created, tg.is_expanded
                    """
                    
                    var statement: OpaquePointer?
                    let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
                    defer { sqlite3_finalize(statement) }
                    
                    if result != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    var groups: [TrackGroup] = []
                    while sqlite3_step(statement) == SQLITE_ROW {
                        let id = String(cString: sqlite3_column_text(statement, 0))
                        let name = String(cString: sqlite3_column_text(statement, 1))
                        let mainTrackId = Int(sqlite3_column_int(statement, 2))
                        let dateCreatedString = String(cString: sqlite3_column_text(statement, 3))
                        let isExpanded = sqlite3_column_int(statement, 4) != 0
                        
                        // Parse track IDs
                        var trackIds: Set<Int> = []
                        if sqlite3_column_type(statement, 5) != SQLITE_NULL {
                            let trackIdsString = String(cString: sqlite3_column_text(statement, 5))
                            trackIds = Set(trackIdsString.split(separator: ",").compactMap { Int($0) })
                        }
                        
                        // Parse date
                        let dateFormatter = ISO8601DateFormatter()
                        let dateCreated = dateFormatter.date(from: dateCreatedString) ?? Date()
                        
                        let group = TrackGroup(
                            id: id,
                            name: name,
                            mainTrackId: mainTrackId,
                            trackIds: trackIds,
                            dateCreated: dateCreated,
                            isExpanded: isExpanded
                        )
                        groups.append(group)
                    }
                    
                    continuation.resume(returning: groups)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Save a track group to the database
    func saveTrackGroup(_ group: TrackGroup) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else {
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    
                    // Begin transaction
                    if sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: "Failed to begin transaction: \(errorMessage)"))
                        return
                    }
                    
                    // Insert or replace track group
                    let dateFormatter = ISO8601DateFormatter()
                    let dateString = dateFormatter.string(from: group.dateCreated)
                    
                    let insertGroupSQL = """
                    INSERT OR REPLACE INTO \(self.tableTrackGroups) 
                    (id, name, main_track_id, date_created, is_expanded) 
                    VALUES (?, ?, ?, ?, ?)
                    """
                    
                    var groupStatement: OpaquePointer?
                    if sqlite3_prepare_v2(db, insertGroupSQL, -1, &groupStatement, nil) != SQLITE_OK {
                        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    defer { sqlite3_finalize(groupStatement) }
                    
                    sqlite3_bind_text(groupStatement, 1, group.id, -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_text(groupStatement, 2, group.name, -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_int(groupStatement, 3, Int32(group.mainTrackId))
                    sqlite3_bind_text(groupStatement, 4, dateString, -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_int(groupStatement, 5, group.isExpanded ? 1 : 0)
                    
                    if sqlite3_step(groupStatement) != SQLITE_DONE {
                        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    // Delete existing members
                    let deleteMembersSQL = "DELETE FROM \(self.tableTrackGroupMembers) WHERE group_id = ?"
                    var deleteStatement: OpaquePointer?
                    if sqlite3_prepare_v2(db, deleteMembersSQL, -1, &deleteStatement, nil) != SQLITE_OK {
                        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    defer { sqlite3_finalize(deleteStatement) }
                    
                    sqlite3_bind_text(deleteStatement, 1, group.id, -1, self.SQLITE_TRANSIENT)
                    if sqlite3_step(deleteStatement) != SQLITE_DONE {
                        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    // Insert new members
                    let insertMemberSQL = "INSERT INTO \(self.tableTrackGroupMembers) (group_id, track_id) VALUES (?, ?)"
                    for trackId in group.trackIds {
                        var memberStatement: OpaquePointer?
                        if sqlite3_prepare_v2(db, insertMemberSQL, -1, &memberStatement, nil) != SQLITE_OK {
                            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                            let errorMessage = String(cString: sqlite3_errmsg(db))
                            continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                            return
                        }
                        defer { sqlite3_finalize(memberStatement) }
                        
                        sqlite3_bind_text(memberStatement, 1, group.id, -1, self.SQLITE_TRANSIENT)
                        sqlite3_bind_int(memberStatement, 2, Int32(trackId))
                        
                        if sqlite3_step(memberStatement) != SQLITE_DONE {
                            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                            let errorMessage = String(cString: sqlite3_errmsg(db))
                            continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                            return
                        }
                    }
                    
                    // Commit transaction
                    if sqlite3_exec(db, "COMMIT", nil, nil, nil) != SQLITE_OK {
                        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    continuation.resume()
                } catch {
                    sqlite3_exec(self.database, "ROLLBACK", nil, nil, nil)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Delete a track group from the database
    func deleteTrackGroup(id: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else {
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    
                    // Delete group (cascade will handle members)
                    let deleteSQL = "DELETE FROM \(self.tableTrackGroups) WHERE id = ?"
                    var statement: OpaquePointer?
                    
                    if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    defer { sqlite3_finalize(statement) }
                    
                    sqlite3_bind_text(statement, 1, id, -1, self.SQLITE_TRANSIENT)
                    
                    if sqlite3_step(statement) != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Update the main track for a group
    func updateTrackGroupMainTrack(groupId: String, mainTrackId: Int) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    guard let db = self.database else {
                        continuation.resume(throwing: CollectionError.databaseNotOpen)
                        return
                    }
                    
                    let updateSQL = "UPDATE \(self.tableTrackGroups) SET main_track_id = ? WHERE id = ?"
                    var statement: OpaquePointer?
                    
                    if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) != SQLITE_OK {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    defer { sqlite3_finalize(statement) }
                    
                    sqlite3_bind_int(statement, 1, Int32(mainTrackId))
                    sqlite3_bind_text(statement, 2, groupId, -1, self.SQLITE_TRANSIENT)
                    
                    if sqlite3_step(statement) != SQLITE_DONE {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: CollectionError.queryFailed(message: errorMessage))
                        return
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Cleans up track group relationships when a track is deleted
    /// This method handles:
    /// - Removing the track from group membership
    /// - Dissolving groups that would have only 1 track remaining
    /// - Reassigning main track if the deleted track was the main track
    private func cleanupTrackGroupRelationships(trackId: Int) throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        
        // Find groups that contain this track
        let findGroupsSQL = """
            SELECT tg.id, tg.main_track_id, COUNT(tgm.track_id) as member_count
            FROM \(tableTrackGroups) tg
            JOIN \(tableTrackGroupMembers) tgm ON tg.id = tgm.group_id
            WHERE tg.id IN (
                SELECT group_id FROM \(tableTrackGroupMembers) WHERE track_id = ?
            )
            GROUP BY tg.id, tg.main_track_id
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, findGroupsSQL, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Failed to prepare group cleanup query: \(errorMessage)")
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(trackId))
        
        var groupsToProcess: [(id: String, mainTrackId: Int, memberCount: Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let groupId = String(cString: sqlite3_column_text(statement, 0))
            let mainTrackId = Int(sqlite3_column_int(statement, 1))
            let memberCount = Int(sqlite3_column_int(statement, 2))
            groupsToProcess.append((id: groupId, mainTrackId: mainTrackId, memberCount: memberCount))
        }
        
        // Process each affected group
        for group in groupsToProcess {
            if group.memberCount <= 2 {
                // Group will have 1 or fewer tracks after deletion, so dissolve it
                try dissolveTrackGroup(groupId: group.id)
                print("Dissolved group \(group.id) due to insufficient tracks after deletion of track \(trackId)")
            } else if group.mainTrackId == trackId {
                // Need to reassign main track
                try reassignMainTrackForGroup(groupId: group.id, excludeTrackId: trackId)
                print("Reassigned main track for group \(group.id) after deletion of main track \(trackId)")
            }
            // Note: The track will be automatically removed from group membership
            // due to foreign key cascade constraints
        }
    }
    
    /// Dissolves a track group by deleting it from the database
    private func dissolveTrackGroup(groupId: String) throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        
        // Delete group (cascade constraints will handle member cleanup)
        let deleteSQL = "DELETE FROM \(tableTrackGroups) WHERE id = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Failed to prepare group dissolution: \(errorMessage)")
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, groupId, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Failed to dissolve group: \(errorMessage)")
        }
    }
    
    /// Reassigns the main track for a group when the current main track is being deleted
    private func reassignMainTrackForGroup(groupId: String, excludeTrackId: Int) throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        
        // Find the first available track in the group (excluding the one being deleted)
        let findTrackSQL = """
            SELECT track_id FROM \(tableTrackGroupMembers) 
            WHERE group_id = ? AND track_id != ? 
            LIMIT 1
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, findTrackSQL, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Failed to prepare main track reassignment query: \(errorMessage)")
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, groupId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(excludeTrackId))
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            // No other tracks found, this shouldn't happen if we checked member count correctly
            throw CollectionError.queryFailed(message: "No alternative main track found for group \(groupId)")
        }
        
        let newMainTrackId = Int(sqlite3_column_int(statement, 0))
        
        // Update the group's main track
        let updateSQL = "UPDATE \(tableTrackGroups) SET main_track_id = ? WHERE id = ?"
        var updateStatement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Failed to prepare main track update: \(errorMessage)")
        }
        defer { sqlite3_finalize(updateStatement) }
        
        sqlite3_bind_int(updateStatement, 1, Int32(newMainTrackId))
        sqlite3_bind_text(updateStatement, 2, groupId, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(updateStatement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw CollectionError.queryFailed(message: "Failed to update main track: \(errorMessage)")
        }
    }
    
    // MARK: - Auto backup & restore
    
    private static let autoBackupUpdateHook: @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<Int8>?, UnsafePointer<Int8>?, sqlite3_int64) -> Void = { ctx, _, _, _, _ in
        guard let ctx = ctx else { return }
        Unmanaged<CollectionService>.fromOpaque(ctx).takeUnretainedValue().enqueueAutoBackupAfterMutation()
    }
    
    private func installAutoBackupMutationHook() {
        guard let db = database else { return }
        sqlite3_update_hook(db, CollectionService.autoBackupUpdateHook, Unmanaged.passUnretained(self).toOpaque())
    }
    
    private func enqueueAutoBackupAfterMutation() {
        if isPerformingAutoBackup { return }
        databaseQueue.async { [weak self] in
            self?.runThrottledAutoBackupIfNeeded()
        }
    }
    
    private func runThrottledAutoBackupIfNeeded() {
        guard let definition = activeCollectionDefinition, !isReadOnlyMode, database != nil else { return }
        let now = Date()
        if let last = lastSuccessfulAutoBackupDate, now.timeIntervalSince(last) < Self.autoBackupThrottleInterval {
            return
        }
        do {
            try performAutoBackupSnapshot(for: definition)
            lastSuccessfulAutoBackupDate = now
            print("[AutoBackup] Snapshot saved (waveforms stripped in backup file).")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .vauxAutoBackupDidComplete, object: nil)
            }
        } catch {
            print("[AutoBackup] Failed: \(error.localizedDescription)")
        }
    }
    
    private func applicationSupportRoot() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CollectionError.backupOperationFailed(reason: "Could not resolve Application Support directory.")
        }
        return base.appendingPathComponent("VAUX", isDirectory: true)
    }
    
    private static func stableBackupFolderName(forDbPath path: String) -> String {
        let hash = SHA256.hash(data: Data(path.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Directory where automatic backups for the active database are stored (Application Support).
    func autoBackupDirectoryURL() throws -> URL {
        guard let definition = activeCollectionDefinition else {
            throw CollectionError.backupOperationFailed(reason: "No collection is open.")
        }
        let root = try applicationSupportRoot()
        let sub = Self.stableBackupFolderName(forDbPath: definition.dbPath)
        return root.appendingPathComponent("DatabaseBackups", isDirectory: true).appendingPathComponent(sub, isDirectory: true)
    }
    
    /// Auto-backup `.sqlite` files for the active database, **newest first** (same folder as rotation uses).
    func sortedAutoBackupFileURLs() throws -> [URL] {
        let backupDir = try autoBackupDirectoryURL()
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupDir.path) else { return [] }
        let urls = try fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        let sqliteFiles = urls.filter { $0.pathExtension.lowercased() == "sqlite" }
        return try sqliteFiles.sorted { a, b in
            let da = try a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let db = try b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return da > db
        }
    }
    
    private func performAutoBackupSnapshot(for definition: CollectionDefinition) throws {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        if isPerformingAutoBackup { return }
        isPerformingAutoBackup = true
        defer { isPerformingAutoBackup = false }
        
        let backupDir = try autoBackupDirectoryURL()
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destURL = backupDir.appendingPathComponent("backup-\(stamp).sqlite")
        let destPath = destURL.path.replacingOccurrences(of: "\\", with: "/")
        
        try exportConsistentDatabaseCopy(from: db, to: destURL)
        try stripWaveformColumnInDatabaseFile(at: destPath)
        try rotateAutoBackups(in: backupDir, keeping: Self.autoBackupMaxRotatedFiles)
    }
    
    /// Copies the open database to `destURL` using SQLite APIs (falls back to file copy).
    private func exportConsistentDatabaseCopy(from db: OpaquePointer, to destURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        let destPath = destURL.path.replacingOccurrences(of: "\\", with: "/")
        let escaped = destPath.replacingOccurrences(of: "'", with: "''")
        let vacuumSQL = "VACUUM INTO '\(escaped)'"
        if sqlite3_exec(db, vacuumSQL, nil, nil, nil) == SQLITE_OK {
            return
        }
        let msg = String(cString: sqlite3_errmsg(db))
        print("[AutoBackup] VACUUM INTO failed (\(msg)); trying sqlite3_backup…")
        var dest: OpaquePointer?
        guard sqlite3_open_v2(destPath, &dest, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let destDb = dest else {
            throw CollectionError.backupOperationFailed(reason: "Could not create backup file.")
        }
        defer { sqlite3_close(destDb) }
        guard let backup = sqlite3_backup_init(destDb, "main", db, "main") else {
            throw CollectionError.backupOperationFailed(reason: "sqlite3_backup_init failed.")
        }
        defer { sqlite3_backup_finish(backup) }
        var rc = SQLITE_OK
        while rc == SQLITE_OK || rc == SQLITE_BUSY || rc == SQLITE_LOCKED {
            rc = sqlite3_backup_step(backup, -1)
        }
        if rc != SQLITE_DONE {
            try? fm.removeItem(at: destURL)
            throw CollectionError.backupOperationFailed(reason: "sqlite3_backup_step failed (code \(rc)).")
        }
    }
    
    /// Drops waveform samples from a standalone DB file (minimizes backup size).
    private func stripWaveformColumnInDatabaseFile(at path: String) throws {
        var db: OpaquePointer?
        let clean = path.replacingOccurrences(of: "\\", with: "/")
        guard sqlite3_open_v2(clean, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let handle = db else {
            throw CollectionError.backupOperationFailed(reason: "Could not open backup to strip waveforms.")
        }
        defer { sqlite3_close(handle) }
        _ = sqlite3_exec(handle, "DELETE FROM \(tableWaveforms)", nil, nil, nil)
        let columns = sqliteColumnNames(table: tableMusic, db: handle)
        if columns.contains(columnWaveformData) {
            let sql = "UPDATE \(tableMusic) SET \(columnWaveformData) = NULL"
            if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
                let err = String(cString: sqlite3_errmsg(handle))
                throw CollectionError.backupOperationFailed(reason: "Strip waveforms failed: \(err)")
            }
        }
    }
    
    private func rotateAutoBackups(in directory: URL, keeping maxFiles: Int) throws {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        let sqliteFiles = urls.filter { $0.pathExtension.lowercased() == "sqlite" }
        let sorted = try sqliteFiles.sorted { a, b in
            let da = try a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let db = try b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return da > db
        }
        guard sorted.count > maxFiles else { return }
        for url in sorted.dropFirst(maxFiles) {
            try? fm.removeItem(at: url)
        }
    }
    
    private struct WaveformBackupPayload {
        let bins: Data
        let binCount: Int
        let version: Int
    }

    private func exportWaveformPayloadsByPathFromLiveDatabase() throws -> [String: WaveformBackupPayload] {
        guard let db = database else { throw CollectionError.databaseNotOpen }
        var result: [String: WaveformBackupPayload] = [:]
        let sql = """
            SELECT m.\(columnPath), w.bins, w.bin_count, w.version
            FROM \(tableWaveforms) w
            JOIN \(tableMusic) m ON m.\(columnId) = w.track_id
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CollectionError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let pathPtr = sqlite3_column_text(stmt, 0) else { continue }
            let path = String(cString: pathPtr)
            let byteCount = Int(sqlite3_column_bytes(stmt, 1))
            let data: Data
            if byteCount > 0, let ptr = sqlite3_column_blob(stmt, 1) {
                data = Data(bytes: ptr, count: byteCount)
            } else {
                data = Data()
            }
            result[path] = WaveformBackupPayload(
                bins: data,
                binCount: Int(sqlite3_column_int(stmt, 2)),
                version: Int(sqlite3_column_int(stmt, 3))
            )
        }
        return result
    }
    
    private func applyWaveformPayloads(_ payloads: [String: WaveformBackupPayload], toDatabaseAt path: String) throws {
        guard !payloads.isEmpty else { return }
        var db: OpaquePointer?
        let clean = path.replacingOccurrences(of: "\\", with: "/")
        guard sqlite3_open_v2(clean, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let handle = db else {
            throw CollectionError.backupOperationFailed(reason: "Could not open restored copy for waveform merge.")
        }
        defer { sqlite3_close(handle) }
        _ = sqlite3_exec(handle, waveformsCreateSQL(), nil, nil, nil)
        let sql = """
            INSERT INTO \(tableWaveforms) (track_id, bins, bin_count, version)
            SELECT \(columnId), ?, ?, ? FROM \(tableMusic) WHERE \(columnPath) = ?
            ON CONFLICT(track_id) DO UPDATE SET
                bins = excluded.bins,
                bin_count = excluded.bin_count,
                version = excluded.version
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CollectionError.backupOperationFailed(reason: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        for (pathKey, payload) in payloads {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            payload.bins.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, 1, raw.baseAddress, Int32(payload.bins.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_int(stmt, 2, Int32(payload.binCount))
            sqlite3_bind_int(stmt, 3, Int32(payload.version))
            sqlite3_bind_text(stmt, 4, pathKey, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
    }
    
    /// Replaces the live database with the selected backup; copies current waveforms into the backup copy by track path when possible.
    func restoreFromBackup(backupFileURL: URL) async throws {
        let definition = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CollectionDefinition, Error>) in
            databaseQueue.sync {
                guard let def = self.activeCollectionDefinition else {
                    cont.resume(throwing: CollectionError.databaseNotOpen)
                    return
                }
                if self.isReadOnlyMode {
                    cont.resume(throwing: CollectionError.backupOperationFailed(reason: "Cannot restore while the database is open read-only."))
                    return
                }
                cont.resume(returning: def)
            }
        }
        let livePath = definition.dbPath.replacingOccurrences(of: "\\", with: "/")
        guard FileManager.default.fileExists(atPath: backupFileURL.path) else {
            throw CollectionError.backupOperationFailed(reason: "Backup file not found.")
        }
        let waveformPayloads = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: WaveformBackupPayload], Error>) in
            databaseQueue.async {
                do {
                    let map = try self.exportWaveformPayloadsByPathFromLiveDatabase()
                    cont.resume(returning: map)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vaux-restore-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: backupFileURL, to: tempURL)
        do {
            try applyWaveformPayloads(waveformPayloads, toDatabaseAt: tempURL.path)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        closeCollection()
        let liveURL = URL(fileURLWithPath: livePath)
        do {
            _ = try FileManager.default.replaceItemAt(liveURL, withItemAt: tempURL, backupItemName: "pre-restore-\(UUID().uuidString.prefix(8)).sqlite", options: [])
        } catch {
            throw CollectionError.backupOperationFailed(reason: error.localizedDescription)
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
    case backupOperationFailed(reason: String)
    
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
        case .backupOperationFailed(let reason):
            return reason
        }
    }
}

extension Notification.Name {
    static let vauxAutoBackupDidComplete = Notification.Name("com.vaux.AutoBackupDidComplete")
}
