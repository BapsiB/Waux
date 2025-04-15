import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart'; // For Color
import 'package:path/path.dart' as pathLib; // Use alias
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../services/audio_service.dart';

enum TrackSource { local, url, youtube }

class Track {
  final int? id;
  final String title;
  final String artist;
  final String album;
  // NOTE: This path can be ABSOLUTE (for local) or RELATIVE (for shared)
  final String path;
  final bool isUrl; // URLs are always treated as absolute
  final int duration; // in milliseconds
  final List<TimeMarker> timeMarkers; // Time-based markers
  final List<double>? waveformData; // Store waveform data
  final int rating; // 0-5 stars
  final String comment; // User comments
  final List<String> generalTags; // General tags for the whole track

  Track({
    this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.path,
    required this.isUrl,
    required this.duration,
    // --- MODIFIED: Default value is now an empty list ---
    this.timeMarkers = const [],
    // --- END MODIFIED ---
    this.waveformData,
    this.rating = 0,
    this.comment = '',
    this.generalTags = const [],
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    var jsonM = json['timeMarkers'];
    var decoded;
    if (jsonM != null) {
      decoded = jsonDecode(json['timeMarkers']);
    }

    return Track(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      album: json['album'],
      path: json['path'],
      // Ensure isUrl is handled correctly (might be stored as 0/1)
      isUrl:
          json['isUrl'] is bool
              ? json['isUrl']
              : (json['isUrl'] == 1), // Handle integer bool
      duration: json['duration'],
      timeMarkers:
          (json['timeMarkers'] != null)
              ? _parseTimeMarkersJson(
                json['timeMarkers'],
              ) // Use a helper function
              : [],
      waveformData:
          json['waveformData'] != null
              ? List<double>.from(jsonDecode(json['waveformData']))
              : null,
      rating: json['rating'] ?? 0,
      comment: json['comment'] ?? '',
      generalTags:
          json['generalTags'] != null
              ? List<String>.from(jsonDecode(json['generalTags']))
              : [],
    );
  }

  static List<TimeMarker> _parseTimeMarkersJson(dynamic markersJsonInput) {
    try {
      // First, decode if it's a string
      final dynamic decodedJson =
          (markersJsonInput is String)
              ? jsonDecode(markersJsonInput)
              : markersJsonInput; // Assume already decoded if not string

      // Check if the decoded result is a List
      if (decodedJson is List) {
        return decodedJson
            .map((markerJson) {
              // Ensure each item in the list is a map before parsing
              if (markerJson is Map<String, dynamic>) {
                return TimeMarker.fromJson(markerJson);
              } else {
                print(
                  "Warning: Found non-map item in timeMarkers list: $markerJson",
                );
                return null; // Or throw an error, or return a default marker
              }
            })
            .whereType<TimeMarker>() // Filter out any nulls from bad data
            .toList();
      } else {
        // If it's not a list (e.g., it's a Map like {}), return an empty list
        print(
          "Warning: Expected List for timeMarkers, but got ${decodedJson.runtimeType}. Defaulting to empty list.",
        );
        return [];
      }
    } catch (e) {
      // Handle potential jsonDecode errors or other issues
      print(
        "Error parsing timeMarkers JSON: $e. Input: $markersJsonInput. Defaulting to empty list.",
      );
      return [];
    }
  }

  // toJson remains the same
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'path': path, // Store the path as is (absolute or relative)
      'isUrl': isUrl ? 1 : 0,
      'duration': duration,
      // --- MODIFIED: Encode List<TimeMarker> to JSON string ---
      'timeMarkers': jsonEncode(
        timeMarkers.map((marker) => marker.toJson()).toList(),
      ),
      // --- END MODIFIED ---
      'waveformData': waveformData != null ? jsonEncode(waveformData) : null,
      'rating': rating,
      'comment': comment,
      'generalTags': jsonEncode(generalTags),
    };
  }

  // copyWith remains the same
  Track copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    String? path,
    bool? isUrl,
    int? duration,
    // --- MODIFIED: Type is List<TimeMarker> ---
    List<TimeMarker>? timeMarkers,
    // --- END MODIFIED ---
    List<double>? waveformData,
    int? rating,
    String? comment,
    List<String>? generalTags,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      path: path ?? this.path,
      isUrl: isUrl ?? this.isUrl,
      duration: duration ?? this.duration,
      // --- MODIFIED: Assign tags ---
      timeMarkers: timeMarkers ?? this.timeMarkers,
      // --- END MODIFIED ---
      waveformData: waveformData ?? this.waveformData,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      generalTags: generalTags ?? this.generalTags,
    );
  }

  TrackSource get sourceType {
    if (!isUrl) {
      return TrackSource.local;
    } else {
      // Basic check for YouTube URLs (adjust patterns if needed)
      if (path.contains('youtube.com') || path.contains('youtu.be')) {
        return TrackSource.youtube;
      } else {
        return TrackSource.url;
      }
    }
  }
}

// Tag model remains the same (global tags stored in SharedPreferences)
class Tag {
  final String name;
  final int? colorValue; // Store color as int

  Tag({required this.name, this.colorValue});

  Map<String, dynamic> toJson() => {'name': name, 'colorValue': colorValue};

  factory Tag.fromJson(Map<String, dynamic> json) =>
      Tag(name: json['name'], colorValue: json['colorValue']);

  Color? get color => colorValue == null ? null : Color(colorValue!);
}

// --- NEW: Collection Definition ---
enum CollectionType { local, shared }

class CollectionDefinition {
  final String id; // Unique ID for managing definitions
  final String name;
  final CollectionType type;
  final String dbPath; // Path to the database file
  final String? rootPath; // ONLY for shared collections (the single root)

  CollectionDefinition({
    required this.id,
    required this.name,
    required this.type,
    required this.dbPath,
    this.rootPath, // Nullable, only set for shared type
  }) {
    // Ensure rootPath is provided for shared collections
    if (type == CollectionType.shared &&
        (rootPath == null || rootPath!.isEmpty)) {
      throw ArgumentError('Shared collections must have a non-empty rootPath.');
    }
    // Ensure rootPath is null for local collections
    if (type == CollectionType.local && rootPath != null) {
      throw ArgumentError('Local collections should not have a rootPath.');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name, // Store enum name as string
    'dbPath': dbPath,
    'rootPath': rootPath,
  };

  factory CollectionDefinition.fromJson(Map<String, dynamic> json) =>
      CollectionDefinition(
        id: json['id'],
        name: json['name'],
        type: CollectionType.values.firstWhere(
          (e) => e.name == json['type'],
        ), // Get enum from name
        dbPath: json['dbPath'],
        rootPath: json['rootPath'],
      );
}

// --- Collection Service ---

class CollectionService {
  // --- Constants ---
  static const int _databaseVersion =
      3; // Keep DB version (or increment if needed for playlist tables)
  static const String tableMusic = 'music';
  static const String tablePlaylists = 'playlists'; // <<< NEW
  static const String tablePlaylistTracks = 'playlist_tracks'; // <<< NEW
  static const String tableLocalRoots =
      'local_root_folders'; // <<< Renamed for clarity

  // Column names remain the same for music table
  static const String columnId = 'id';
  static const String columnTitle = 'title';
  static const String columnArtist = 'artist';
  static const String columnAlbum = 'album';
  static const String columnPath = 'path'; // Holds absolute OR relative path
  static const String columnIsUrl = 'isUrl';
  static const String columnDuration = 'duration';
  static const String columnTimeMarkers = 'timeMarkers'; // Time-based tags
  static const String columnWaveformData = 'waveformData';
  static const String columnRating = 'rating';
  static const String columnComment = 'comment';
  static const String columnGeneralTags = 'generalTags';
  final _yt = YoutubeExplode();

  // Playlist table columns <<< NEW
  static const String columnPlaylistId = 'id';
  static const String columnPlaylistName = 'name';

  // Playlist tracks table columns <<< NEW
  static const String columnPlaylistTracksPlaylistId = 'playlist_id';
  static const String columnPlaylistTracksTrackPath =
      'track_path'; // Relative/Absolute based on collection
  static const String columnPlaylistTracksSortOrder = 'sort_order';

  // SharedPreferences Keys
  static const String _collectionDefinitionsKey = 'collection_definitions_list';
  static const String _generalTagsKey = 'general_tags_list'; // Global tags
  static const String _lastActiveCollectionIdKey = 'last_active_collection_id';

  // --- State ---
  Database? _database; // Connection to the *active* database
  CollectionDefinition?
  _activeCollectionDefinition; // Info about the active collection
  List<String> _localCollectionRootFolders =
      []; // Root folders for the *active* local collection

  // Keep loading state stream
  final _loadingController = StreamController<bool>.broadcast();
  Stream<bool> get loadingStream => _loadingController.stream;
  bool _isLoading = false;

  // Keep AudioService if needed
  // final AudioService _audioService = AudioService();

  // --- Collection Definition Management (using SharedPreferences) ---
  // (Methods: loadCollectionDefinitions, _saveCollectionDefinitions, addCollectionDefinition, removeCollectionDefinition)
  // ... (Keep existing methods from previous step) ...
  Future<List<CollectionDefinition>> loadCollectionDefinitions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_collectionDefinitionsKey);
      if (jsonString != null) {
        final List<dynamic> decodedList = jsonDecode(jsonString);
        return decodedList
            .map(
              (jsonItem) => CollectionDefinition.fromJson(
                jsonItem as Map<String, dynamic>,
              ),
            )
            .toList();
      }
    } catch (e) {
      print('Error loading collection definitions: $e');
    }
    return []; // Return empty list on error or if none exist
  }

  Future<void> _saveCollectionDefinitions(
    List<CollectionDefinition> definitions,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList =
          definitions.map((def) => def.toJson()).toList();
      await prefs.setString(_collectionDefinitionsKey, jsonEncode(jsonList));
    } catch (e) {
      print('Error saving collection definitions: $e');
    }
  }

  Future<bool> deleteFolderFromDisk(String folderPath) async {
    print("[deleteFolderFromDisk] Attempting to delete: '$folderPath'");
    try {
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        print("[deleteFolderFromDisk] Successfully deleted: '$folderPath'");
        return true;
      } else {
        print("[deleteFolderFromDisk] Folder not found on disk: '$folderPath'");
        return false;
      }
    } catch (e) {
      print("[deleteFolderFromDisk] ERROR deleting '$folderPath': $e");
      return false;
    }
  }

  Future<List<Track>> getTracksInFolder(String folderPath) async {
    if (_database == null || !_database!.isOpen) return [];
    final activeDef = _activeCollectionDefinition;
    if (activeDef == null) return [];

    List<Track> tracksInFolder = [];
    // Get tracks with resolved absolute paths
    final allTracks = await getAllTracks();

    // --- Normalize the target folder path ---
    // Assuming folderPath is intended to be an absolute path from the UI
    final normalizedTargetFolderPath = pathLib.normalize(folderPath);
    print(
      "[getTracksInFolder] Normalized Target Path: '$normalizedTargetFolderPath'",
    );

    for (final track in allTracks) {
      // Skip URLs
      if (!track.isUrl) {
        // Track path should be absolute here due to _resolveTrackPath in getAllTracks
        final normalizedTrackPath = pathLib.normalize(track.path);
        // Get the directory containing the track file
        final trackDirectory = pathLib.dirname(normalizedTrackPath);

        // --- Log paths being compared ---
        print("  [Checking Track] ID: ${track.id}, Title: ${track.title}");
        print("    Track Path (Normalized): '$normalizedTrackPath'");
        print("    Track Dir  (Normalized): '$trackDirectory'");

        // --- Robust Comparison ---
        // Use pathLib.equals for exact directory match
        // Use pathLib.isWithin for checking subdirectories
        if (pathLib.equals(trackDirectory, normalizedTargetFolderPath) ||
            pathLib.isWithin(normalizedTargetFolderPath, trackDirectory)) {
          print("    --> MATCH FOUND!");
          tracksInFolder.add(track);
        }
      }
    }
    print(
      "[getTracksInFolder] Found ${tracksInFolder.length} tracks for folder '$folderPath'",
    );
    return tracksInFolder;
  }

  Future<String?> loadLastActiveCollectionId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastActiveCollectionIdKey);
    } catch (e) {
      print('Error loading last active collection ID: $e');
      return null;
    }
  }

  Future<void> saveLastActiveCollectionId(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id != null && id.isNotEmpty) {
        await prefs.setString(_lastActiveCollectionIdKey, id);
        print('Saved last active collection ID: $id');
      } else {
        await prefs.remove(_lastActiveCollectionIdKey);
        print('Cleared last active collection ID.');
      }
    } catch (e) {
      print('Error saving last active collection ID: $e');
    }
  }

  Future<void> addCollectionDefinition(CollectionDefinition definition) async {
    final definitions = await loadCollectionDefinitions();
    // Avoid adding duplicates by ID or potentially Name/Path
    if (!definitions.any((def) => def.id == definition.id)) {
      definitions.add(definition);
      await _saveCollectionDefinitions(definitions);
      print('Added collection definition: ${definition.name}');
    } else {
      print('Collection definition with ID ${definition.id} already exists.');
      // Optionally update if needed?
    }
  }

  Future<void> removeCollectionDefinition(String id) async {
    final definitions = await loadCollectionDefinitions();
    final initialLength = definitions.length;
    definitions.removeWhere((def) => def.id == id);
    if (definitions.length < initialLength) {
      await _saveCollectionDefinitions(definitions);
      print('Removed collection definition with ID: $id');
      // Note: This does NOT delete the actual database file
    }
  }

  // --- Service Lifecycle & Collection Switching ---
  // (Methods: initialize, openCollection, closeCollection, getActiveCollection)
  // ... (Keep existing methods from previous step) ...
  Future<void> initialize() async {
    print("CollectionService initialized. Ready to open a collection.");
  }

  Future<void> openCollection(CollectionDefinition definition) async {
    setLoading(true);
    print("Opening collection: ${definition.name} (${definition.type.name})");
    try {
      await closeCollection();
      _activeCollectionDefinition = definition;
      String dbFilePath = definition.dbPath;
      if (definition.type == CollectionType.shared) {
        final dbDir = Directory(definition.rootPath!);
        if (!await dbDir.exists()) {
          throw Exception(
            "Shared collection root directory does not exist: ${definition.rootPath}",
          );
        }
      } else {
        final dbDir = Directory(pathLib.dirname(dbFilePath));
        if (!await dbDir.exists()) {
          await dbDir.create(recursive: true);
        }
      }
      _database = await _initDatabase(dbFilePath);
      print("Database opened at: $dbFilePath");
      if (definition.type == CollectionType.local) {
        await _loadLocalCollectionRootFolders();
      } else {
        _localCollectionRootFolders = [];
      }
      print("Collection ${definition.name} opened successfully.");
    } catch (e, stackTrace) {
      print("Error opening collection ${definition.name}: $e");
      print(stackTrace);
      _activeCollectionDefinition = null;
      _database = null;
      _localCollectionRootFolders = [];
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  Future<void> closeCollection() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      print(
        "Closed database for collection: ${_activeCollectionDefinition?.name}",
      );
    }
    _database = null;
    _activeCollectionDefinition = null;
    _localCollectionRootFolders = [];
  }

  CollectionDefinition? getActiveCollection() {
    return _activeCollectionDefinition;
  }

  // <<< NEW: Helper to get the active DB connection >>>
  Database? getActiveDatabase() {
    // Ensure DB is open before returning
    if (_database != null && _database!.isOpen) {
      return _database;
    }
    print("Warning: getActiveDatabase called but database is null or closed.");
    return null;
  }

  // Modified: Initializes or opens database at a specific path
  Future<Database> _initDatabase(String dbPath) async {
    final dbDir = Directory(pathLib.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
      print("Created database directory: ${dbDir.path}");
    }
    return await openDatabase(
      dbPath,
      version: _databaseVersion, // Use the constant
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      // Enable foreign keys for cascade delete
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // --- MODIFIED: _onCreate includes playlist tables ---
  Future _onCreate(Database db, int version) async {
    // Music Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableMusic (
        $columnId INTEGER PRIMARY KEY,
        $columnTitle TEXT NOT NULL,
        $columnArtist TEXT NOT NULL,
        $columnAlbum TEXT NOT NULL,
        $columnPath TEXT NOT NULL,
        $columnIsUrl INTEGER NOT NULL,
        $columnDuration INTEGER NOT NULL,
        $columnTimeMarkers TEXT,
        $columnWaveformData TEXT,
        $columnRating INTEGER DEFAULT 0,
        $columnComment TEXT DEFAULT '',
        $columnGeneralTags TEXT
      )
    ''');
    // Local Root Folders Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableLocalRoots (
        path TEXT PRIMARY KEY
      )
    ''');
    // --- Playlist Tables ---
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablePlaylists (
        $columnPlaylistId TEXT PRIMARY KEY,
        $columnPlaylistName TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablePlaylistTracks (
        $columnPlaylistTracksPlaylistId TEXT NOT NULL,
        $columnPlaylistTracksTrackPath TEXT NOT NULL,
        $columnPlaylistTracksSortOrder INTEGER,
        FOREIGN KEY ($columnPlaylistTracksPlaylistId) REFERENCES $tablePlaylists ($columnPlaylistId) ON DELETE CASCADE
      )
    ''');
    // Add index for faster track lookup in playlists
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_id
      ON $tablePlaylistTracks ($columnPlaylistTracksPlaylistId)
    ''');
  }

  // --- MODIFIED: _onUpgrade potentially adds playlist tables if upgrading ---
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          'ALTER TABLE $tableMusic ADD COLUMN $columnWaveformData TEXT',
        );
      } catch (e) {
        print("Could not add $columnWaveformData: $e");
      }

      // Add new columns for version 2 to music table
      try {
        await db.execute(
          'ALTER TABLE $tableMusic ADD COLUMN $columnWaveformData TEXT',
        );
      } catch (e) {
        print("Could not add $columnWaveformData: $e");
      }
      try {
        await db.execute(
          'ALTER TABLE $tableMusic ADD COLUMN $columnRating INTEGER DEFAULT 0',
        );
      } catch (e) {
        print("Could not add $columnRating: $e");
      }
      try {
        await db.execute(
          'ALTER TABLE $tableMusic ADD COLUMN $columnComment TEXT DEFAULT ""',
        );
      } catch (e) {
        print("Could not add $columnComment: $e");
      }
      try {
        await db.execute(
          'ALTER TABLE $tableMusic ADD COLUMN $columnGeneralTags TEXT',
        );
      } catch (e) {
        print("Could not add $columnGeneralTags: $e");
      }
      // Add tables introduced in v2 (local roots, playlists)
      try {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS $tableLocalRoots (path TEXT PRIMARY KEY)',
        );
      } catch (e) {
        print("Could not add $tableLocalRoots table: $e");
      }
      try {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS $tablePlaylists ($columnPlaylistId TEXT PRIMARY KEY, $columnPlaylistName TEXT NOT NULL)',
        );
      } catch (e) {
        print("Could not add $tablePlaylists table: $e");
      }
      try {
        await db.execute('''
              CREATE TABLE IF NOT EXISTS $tablePlaylistTracks (
                $columnPlaylistTracksPlaylistId TEXT NOT NULL,
                $columnPlaylistTracksTrackPath TEXT NOT NULL,
                $columnPlaylistTracksSortOrder INTEGER,
                FOREIGN KEY ($columnPlaylistTracksPlaylistId) REFERENCES $tablePlaylists ($columnPlaylistId) ON DELETE CASCADE
              )
            ''');
        await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_id
              ON $tablePlaylistTracks ($columnPlaylistTracksPlaylistId)
            ''');
      } catch (e) {
        print("Could not add $tablePlaylistTracks table/index: $e");
      }
    }
    // --- NEW: v2 -> v3 upgrade (Rename tags column) ---
    if (oldVersion < 3) {
      print("Applying v2 -> v3 upgrades...");
      try {
        // Define the OLD column name explicitly here for the migration
        const String oldColumnTags =
            'tags'; // Or whatever the old constant was named
        await db.execute(
          'ALTER TABLE $tableMusic RENAME COLUMN $oldColumnTags TO $columnTimeMarkers',
        );
        print("Renamed column '$oldColumnTags' to '$columnTimeMarkers'.");
      } catch (e) {
        print("Error renaming 'tags' column to '$columnTimeMarkers': $e");
        // Handle potential errors, e.g., if the old column doesn't exist
        // You might need more robust error checking or alternative strategies if rename fails.
        // For example, add the new column and try to copy data if possible (though format differs here).
      }
      print("Finished v2 -> v3 upgrades.");
    }
  }

  // --- Root Folder Management (Revised) ---
  // (Methods: _loadLocalCollectionRootFolders, addRootFolder, removeRootFolder, getRootFolders)
  // ... (Keep existing methods from previous step) ...
  Future<void> _loadLocalCollectionRootFolders() async {
    if (_database == null ||
        !_database!.isOpen ||
        _activeCollectionDefinition?.type != CollectionType.local) {
      _localCollectionRootFolders = [];
      return;
    }
    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        tableLocalRoots,
      );
      _localCollectionRootFolders =
          maps.map((map) => map['path'] as String).toList();
      print(
        'Loaded ${_localCollectionRootFolders.length} root folders for local collection: ${_activeCollectionDefinition?.name}',
      );
    } catch (e) {
      print('Error loading local root folders: $e');
      _localCollectionRootFolders = [];
    }
  }

  Future<void> addRootFolder(String folderPath) async {
    if (_activeCollectionDefinition?.type != CollectionType.local) {
      print('Cannot add root folders to non-local collections.');
      return;
    }
    if (_database == null || !_database!.isOpen) {
      print('Error: Database not open in addRootFolder');
      return;
    }
    final normalizedPath = folderPath.replaceAll('\\', '/');
    if (!_localCollectionRootFolders.contains(normalizedPath)) {
      try {
        await _database!.insert(tableLocalRoots, {
          'path': normalizedPath,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        _localCollectionRootFolders.add(normalizedPath);
        print('Added root folder to local collection: $normalizedPath');
      } catch (e) {
        print('Error adding local root folder to DB: $e');
      }
    }
  }

  Future<void> removeRootFolder(String folderPath) async {
    if (_activeCollectionDefinition?.type != CollectionType.local) {
      print('Cannot remove root folders from non-local collections.');
      return;
    }
    if (_database == null || !_database!.isOpen) {
      print('Error: Database not open in removeRootFolder');
      return;
    }
    final normalizedPath = folderPath.replaceAll('\\', '/');
    try {
      final count = await _database!.delete(
        tableLocalRoots,
        where: 'path = ?',
        whereArgs: [normalizedPath],
      );
      if (count > 0) {
        _localCollectionRootFolders.remove(normalizedPath);
        print('Removed root folder from local collection: $normalizedPath');
      }
    } catch (e) {
      print('Error removing local root folder from DB: $e');
    }
  }

  List<String> getRootFolders() {
    if (_activeCollectionDefinition?.type == CollectionType.shared) {
      return [_activeCollectionDefinition!.rootPath!];
    } else if (_activeCollectionDefinition?.type == CollectionType.local) {
      return List<String>.unmodifiable(_localCollectionRootFolders);
    } else {
      return [];
    }
  }

  Future<void> updateTrackMarkers(int trackId, List<TimeMarker> markers) async {
    if (_database == null || !_database!.isOpen) {
      throw Exception("Database not open");
    }
    try {
      final String markersJson = jsonEncode(
        markers.map((marker) => marker.toJson()).toList(),
      );
      final count = await _database!.update(
        tableMusic,
        {columnTimeMarkers: markersJson}, // Update only the 'tags' column
        where: '$columnId = ?',
        whereArgs: [trackId],
      );
      if (count == 0) {
        print("Warning: updateTrackMarkers - Track ID $trackId not found.");
      } else {
        print("Successfully updated markers for track ID $trackId.");
      }
    } catch (e) {
      print("Error updating track markers for ID $trackId: $e");
      rethrow; // Re-throw the error to be caught by the BLoC
    }
  }

  // --- Track CRUD Operations (Revised for Path Handling) ---
  // (Helpers: _resolveTrackPath, _prepareTrackForDb)
  // (Methods: addTrack, updateTrack, deleteTrack, getTrack, getTrackByPath, getAllTracks, searchTracks)
  Track _resolveTrackPath(Track track) {
    if (_activeCollectionDefinition?.type == CollectionType.shared &&
        !track.isUrl &&
        _activeCollectionDefinition?.rootPath != null) {
      try {
        final absolutePath = pathLib.join(
          _activeCollectionDefinition!.rootPath!,
          track.path,
        );
        return track.copyWith(path: absolutePath);
      } catch (e) {
        print(
          "Error resolving relative path ${track.path} with root ${_activeCollectionDefinition!.rootPath}: $e",
        );
        // Return original track if resolution fails
        return track;
      }
    }
    return track;
  }

  Map<String, dynamic> _prepareTrackForDb(Track track) {
    String pathToStore = track.path;
    if (_activeCollectionDefinition?.type == CollectionType.shared &&
        !track.isUrl &&
        _activeCollectionDefinition?.rootPath != null) {
      try {
        // Ensure paths are absolute before making relative
        if (!pathLib.isAbsolute(track.path)) {
          print(
            "Warning: Trying to make non-absolute path relative: ${track.path}",
          );
          // Decide on fallback: store as is, or throw error? Storing as is for now.
        } else if (!pathLib.isAbsolute(
          _activeCollectionDefinition!.rootPath!,
        )) {
          print(
            "Warning: Root path is not absolute: ${_activeCollectionDefinition!.rootPath}",
          );
        } else {
          pathToStore = pathLib.relative(
            track.path,
            from: _activeCollectionDefinition!.rootPath!,
          );
        }
      } catch (e) {
        print(
          "Warning: Could not make path relative for ${track.path} against root ${_activeCollectionDefinition!.rootPath}. Storing absolute path. Error: $e",
        );
        pathToStore = track.path;
      }
    }
    return track.copyWith(path: pathToStore).toJson();
  }

  Future<int> addTrack(Track track) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    final data = _prepareTrackForDb(track);
    return await _database!.insert(tableMusic, data);
  }

  Future<int> updateTrack(Track track) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    final data = _prepareTrackForDb(track);
    return await _database!.update(
      tableMusic,
      data,
      where: '$columnId = ?',
      whereArgs: [track.id],
    );
  }

  Future<int> deleteTrack(int id) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    return await _database!.delete(
      tableMusic,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  Future<Track?> getTrack(int id) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: '$columnId = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      final track = Track.fromJson(maps.first);
      return _resolveTrackPath(track);
    }
    return null;
  }

  Future<Track?> getTrackByPath(String absolutePath) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    String pathQuery = absolutePath;
    if (_activeCollectionDefinition?.type == CollectionType.shared &&
        _activeCollectionDefinition?.rootPath != null) {
      try {
        if (pathLib.isAbsolute(absolutePath) &&
            pathLib.isWithin(
              _activeCollectionDefinition!.rootPath!,
              absolutePath,
            )) {
          pathQuery = pathLib.relative(
            absolutePath,
            from: _activeCollectionDefinition!.rootPath!,
          );
        } else if (!pathLib.isAbsolute(absolutePath)) {
          // If input is already relative maybe? Less likely scenario. Query as is.
          pathQuery = absolutePath;
          print(
            "Warning: getTrackByPath received potentially relative path for shared collection: $absolutePath",
          );
        } else {
          return null;
        }
      } catch (e) {
        print(
          "Warning: Could not make search path relative. Querying absolute path. Error: $e",
        );
        pathQuery = absolutePath;
      }
    }
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: '$columnPath = ?',
      whereArgs: [pathQuery],
    );
    if (maps.isNotEmpty) {
      final track = Track.fromJson(maps.first);
      return _resolveTrackPath(track);
    }
    return null;
  }

  Future<List<Track>> getAllTracks() async {
    if (_database == null || !_database!.isOpen) return [];
    final List<Map<String, dynamic>> maps = await _database!.query(tableMusic);
    return maps.map((map) => _resolveTrackPath(Track.fromJson(map))).toList();
  }

  Future<List<Track>> searchTracks(String query) async {
    if (_database == null || !_database!.isOpen) return [];
    final String lowercaseQuery = query.toLowerCase();
    final String wildcardQuery = '%$lowercaseQuery%';
    String whereClause = '''
      LOWER($columnTitle) LIKE ? OR
      LOWER($columnArtist) LIKE ? OR
      LOWER($columnAlbum) LIKE ? OR
      LOWER($columnComment) LIKE ? OR
      LOWER($columnGeneralTags) LIKE ? OR
      LOWER($columnPath) LIKE ?
    ''';
    List<dynamic> whereArgs = [
      wildcardQuery,
      wildcardQuery,
      wildcardQuery,
      wildcardQuery,
      wildcardQuery,
      wildcardQuery,
    ];
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: whereClause,
      whereArgs: whereArgs,
    );
    return maps.map((map) => _resolveTrackPath(Track.fromJson(map))).toList();
  }

  // --- Metadata Update Methods ---
  // (Methods: updateRating, updateComment, addGeneralTag, removeGeneralTag)
  // ... (Keep existing methods from previous step) ...
  Future<void> updateRating(int trackId, int rating) async {
    final track = await getTrack(trackId);
    if (track != null) {
      final updatedTrack = track.copyWith(rating: rating);
      await updateTrack(updatedTrack);
    }
  }

  Future<void> updateComment(int trackId, String comment) async {
    final track = await getTrack(trackId);
    if (track != null) {
      final updatedTrack = track.copyWith(comment: comment);
      await updateTrack(updatedTrack);
    }
  }

  Future<void> addGeneralTag(int trackId, String tag) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    if (maps.isEmpty) return;
    final trackFromDb = Track.fromJson(maps.first);
    final tags = List<String>.from(trackFromDb.generalTags);
    if (!tags.contains(tag)) {
      tags.add(tag);
      final updatedTrack = trackFromDb.copyWith(generalTags: tags);
      await updateTrack(updatedTrack); // Handles path prep
    }
  }

  Future<void> removeGeneralTag(int trackId, String tag) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    if (maps.isEmpty) return;
    final trackFromDb = Track.fromJson(maps.first);
    final tags = List<String>.from(trackFromDb.generalTags);
    tags.remove(tag);
    final updatedTrack = trackFromDb.copyWith(generalTags: tags);
    await updateTrack(updatedTrack); // Handles path prep
  }

  // --- Tag Definition Management (Global via SharedPreferences - Unchanged) ---
  // (Methods: getAllTags, _saveAllTags, addTag, removeTag, updateTag)
  // ... (Keep existing methods from previous step) ...
  Future<List<Tag>> getAllTags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? tagsJsonString = prefs.getString(_generalTagsKey);
      if (tagsJsonString != null) {
        final List<dynamic> decodedList = jsonDecode(tagsJsonString);
        return decodedList.map((jsonItem) => Tag.fromJson(jsonItem)).toList();
      }
    } catch (e) {
      print('Error loading general tags: $e');
    }
    return [];
  }

  Future<bool> _saveAllTags(List<Tag> tags) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> tagsJsonList =
          tags.map((tag) => tag.toJson()).toList();
      final String tagsJsonString = jsonEncode(tagsJsonList);
      return await prefs.setString(_generalTagsKey, tagsJsonString);
    } catch (e) {
      print('Error saving general tags: $e');
      return false;
    }
  }

  Future<void> addTag(Tag newTag) async {
    final currentTags = await getAllTags();
    if (!currentTags.any(
      (tag) => tag.name.toLowerCase() == newTag.name.toLowerCase(),
    )) {
      currentTags.add(newTag);
      await _saveAllTags(currentTags);
      print('Added general tag: ${newTag.name}');
    } else {
      print('General tag "${newTag.name}" already exists.');
    }
  }

  Future<void> removeTag(String tagName) async {
    final currentTags = await getAllTags();
    final originalLength = currentTags.length;
    currentTags.removeWhere((tag) => tag.name == tagName);
    if (currentTags.length < originalLength) {
      await _saveAllTags(currentTags);
      print('Removed general tag: $tagName');
    } else {
      print('General tag "$tagName" not found for removal.');
    }
  }

  Future<void> updateTag(Tag updatedTag) async {
    final currentTags = await getAllTags();
    final index = currentTags.indexWhere((tag) => tag.name == updatedTag.name);
    if (index != -1) {
      currentTags[index] = updatedTag;
      await _saveAllTags(currentTags);
      print('Updated general tag: ${updatedTag.name}');
    } else {
      print('General tag "${updatedTag.name}" not found for update.');
    }
  }

  // --- Utility Methods ---
  // (Methods: setLoading, isLoading, dispose)
  // ... (Keep existing methods from previous step) ...
  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      _loadingController.add(_isLoading);
    }
  }

  bool get isLoading => _isLoading;
  Future<void> dispose() async {
    await closeCollection();
    await _loadingController.close();
    print("CollectionService disposed.");
  }

  // --- Methods needing review/implementation based on AudioService ---
  // (Methods: addLocalFile, addUrl, importFromFile, exportToFile)
  // ... (Keep existing methods from previous step, ensure they use helpers) ...
  Future<Track> addLocalFile(String filePath) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    if (_activeCollectionDefinition == null)
      throw Exception("No active collection");
    final existingTrack = await getTrackByPath(filePath);
    if (existingTrack != null) {
      print('Track already exists in database: ${existingTrack.title}');
      return existingTrack;
    }
    final filename = pathLib.basename(filePath);
    final title = pathLib.basenameWithoutExtension(filePath);
    List<double>? waveformData; // Placeholder
    final track = Track(
      title: title,
      artist: 'Unknown',
      album: 'Unknown',
      path: filePath,
      isUrl: false,
      duration: 0,
      waveformData: waveformData,
      rating: 0,
      comment: '',
      generalTags: [],
    );
    final id = await addTrack(track); // Handles path prep
    return _resolveTrackPath(track.copyWith(id: id));
  }

  Future<Track> addUrl(String url) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    if (_activeCollectionDefinition == null)
      throw Exception("No active collection");

    setLoading(true);
    try {
      // Check if it already exists by the original URL
      final existingTrack = await getTrackByPath(url);
      if (existingTrack != null) {
        print('URL already exists in database: ${existingTrack.title}');
        return existingTrack;
      }

      String trackTitle = url; // Default title
      int trackDurationMs = 0; // Default duration
      bool isYouTube = false;

      // --- YouTube Integration ---
      var videoId = VideoId.parseVideoId(url);
      if (videoId != null) {
        isYouTube = true;
        print('Fetching metadata for YouTube video: $videoId');
        try {
          var video = await _yt.videos.get(videoId);
          trackTitle = video.title;
          trackDurationMs = video.duration?.inMilliseconds ?? 0;
          print('Fetched title: $trackTitle, Duration: $trackDurationMs ms');
        } catch (ytError) {
          print(
            'Error fetching YouTube metadata: $ytError. Using URL as title.',
          );
          // Keep default title/duration on error
        }
      } else {
        // Fallback for non-YouTube URLs (maybe try getting filename?)
        final uri = Uri.tryParse(url);
        final filename =
            (uri != null && uri.pathSegments.isNotEmpty)
                ? uri.pathSegments.last
                : '';
        if (filename.isNotEmpty) {
          trackTitle = filename;
        }
      }
      List<double>? waveformData;
      final track = Track(
        title: trackTitle,
        artist: 'Unknown',
        album: isYouTube ? 'YouTube' : 'Unknown',
        path: url,
        isUrl: true,
        duration: 0,
        waveformData: waveformData,
        rating: 0,
        comment: '',
        generalTags: [],
      );
      final id = await addTrack(track); // Handles path prep (no-op for URL)
      return _resolveTrackPath(
        track.copyWith(id: id),
      ); // Resolves path (no-op for URL)
    } catch (e) {
      print('Error adding URL: $e');
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  Future<void> importFromFile(String jsonFilePath) async {
    print("Import not fully implemented for hybrid collections.");
    // TODO: Read JSON, check active collection type, make paths relative if importing to 'shared', add tracks.
  }

  Future<void> exportToFile(String jsonFilePath) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    try {
      final tracks =
          await getAllTracks(); // Gets tracks with resolved absolute paths
      // Convert to JSON using the absolute paths suitable for export
      final jsonData = tracks.map((track) => track.toJson()).toList();
      final jsonString = jsonEncode(jsonData);
      final file = File(jsonFilePath);
      await file.writeAsString(jsonString);
      print("Exported active collection to $jsonFilePath");
    } catch (e) {
      print('Error exporting collection: $e');
      rethrow;
    }
  }
}
