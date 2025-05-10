// lib/services/collection_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart'; // For Color
import 'package:path/path.dart' as pathLib; // Use alias
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart'; // Import uuid
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../services/audio_service.dart';
import 'package:just_audio/just_audio.dart';

// Enum definitions (TrackSource, CollectionType) remain the same...
enum TrackSource { local, url, youtube }

enum CollectionType { local, shared }

// Track class definition remains the same...
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
  final String? albumArtist;
  final String? composer;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final int? bpm;

  Track({
    this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist,
    this.composer,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.bpm,

    required this.path,
    required this.isUrl,
    required this.duration,
    this.timeMarkers = const [],
    this.waveformData,
    this.rating = 0,
    this.comment = '',
    this.generalTags = const [],
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      album: json['album'],
      albumArtist: json['albumArtist'],
      composer: json['composer'],
      genre: json['genre'],
      year: json['year'],
      trackNumber: json['trackNumber'],
      discNumber: json['discNumber'],
      bpm: json['bpm'],
      path: json['path'],
      isUrl:
          json['isUrl'] is bool
              ? json['isUrl']
              : (json['isUrl'] == 1), // Handle integer bool
      duration: json['duration'],
      timeMarkers:
          (json['timeMarkers'] != null)
              ? _parseTimeMarkersJson(json['timeMarkers'])
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
      final dynamic decodedJson =
          (markersJsonInput is String)
              ? jsonDecode(markersJsonInput)
              : markersJsonInput;

      if (decodedJson is List) {
        return decodedJson
            .map((markerJson) {
              if (markerJson is Map<String, dynamic>) {
                return TimeMarker.fromJson(markerJson);
              } else {
                print(
                  "Warning: Found non-map item in timeMarkers list: $markerJson",
                );
                return null;
              }
            })
            .whereType<TimeMarker>()
            .toList();
      } else {
        print(
          "Warning: Expected List for timeMarkers, but got ${decodedJson.runtimeType}. Defaulting to empty list.",
        );
        return [];
      }
    } catch (e) {
      print(
        "Error parsing timeMarkers JSON: $e. Input: $markersJsonInput. Defaulting to empty list.",
      );
      return [];
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'albumArtist': albumArtist,
      'composer': composer,
      'genre': genre,
      'year': year,
      'trackNumber': trackNumber,
      'discNumber': discNumber,
      'bpm': bpm,
      'path': path,
      'isUrl': isUrl ? 1 : 0,
      'duration': duration,
      'timeMarkers': jsonEncode(
        timeMarkers.map((marker) => marker.toJson()).toList(),
      ),
      'waveformData': waveformData != null ? jsonEncode(waveformData) : null,
      'rating': rating,
      'comment': comment,
      'generalTags': jsonEncode(generalTags),
    };
  }

  Track copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? composer,
    String? genre,
    int? year,
    int? trackNumber,
    int? discNumber,
    int? bpm,
    String? path,
    bool? isUrl,
    int? duration,
    List<TimeMarker>? timeMarkers,
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
      albumArtist: albumArtist ?? this.albumArtist,
      composer: composer ?? this.composer,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      bpm: bpm ?? this.bpm,
      path: path ?? this.path,
      isUrl: isUrl ?? this.isUrl,
      duration: duration ?? this.duration,
      timeMarkers: timeMarkers ?? this.timeMarkers,
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
      if (path.contains('youtube.com') || path.contains('youtu.be')) {
        return TrackSource.youtube;
      } else {
        return TrackSource.url;
      }
    }
  }
}

// Tag class definition remains the same...
class Tag {
  final String name;
  final int? colorValue; // Store color as int

  Tag({required this.name, this.colorValue});

  Map<String, dynamic> toJson() => {'name': name, 'colorValue': colorValue};

  factory Tag.fromJson(Map<String, dynamic> json) =>
      Tag(name: json['name'], colorValue: json['colorValue']);

  Color? get color => colorValue == null ? null : Color(colorValue!);
}

// CollectionDefinition class definition remains the same...
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
    if (type == CollectionType.shared &&
        (rootPath == null || rootPath!.isEmpty)) {
      throw ArgumentError('Shared collections must have a non-empty rootPath.');
    }
    if (type == CollectionType.local && rootPath != null) {
      throw ArgumentError('Local collections should not have a rootPath.');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'dbPath': dbPath,
    'rootPath': rootPath,
  };

  factory CollectionDefinition.fromJson(Map<String, dynamic> json) =>
      CollectionDefinition(
        id: json['id'],
        name: json['name'],
        type: CollectionType.values.firstWhere((e) => e.name == json['type']),
        dbPath: json['dbPath'],
        rootPath: json['rootPath'],
      );
}

// --- Collection Service ---

class CollectionService {
  // --- Constants ---
  static const int _databaseVersion = 5; // <<< INCREMENTED DB VERSION
  static const String tableMusic = 'music';
  static const String tablePlaylists = 'playlists';
  static const String tablePlaylistTracks = 'playlist_tracks';
  static const String tableLocalRoots = 'local_root_folders';
  static const String tableUiSettings = 'ui_settings'; // <<< NEW TABLE

  // Column names for music table...
  static const String columnId = 'id';
  static const String columnTitle = 'title';
  static const String columnArtist = 'artist';
  static const String columnAlbum = 'album';
  static const String columnAlbumArtist = 'albumArtist';
  static const String columnComposer = 'composer';
  static const String columnGenre = 'genre';
  static const String columnYear = 'year';
  static const String columnTrackNumber = 'trackNumber';
  static const String columnDiscNumber = 'discNumber';
  static const String columnBpm = 'bpm';
  static const String columnPath = 'path';
  static const String columnIsUrl = 'isUrl';
  static const String columnDuration = 'duration';
  static const String columnTimeMarkers = 'timeMarkers';
  static const String columnWaveformData = 'waveformData';
  static const String columnRating = 'rating';
  static const String columnComment = 'comment';
  static const String columnGeneralTags = 'generalTags';
  final _yt = YoutubeExplode();

  // Playlist table columns...
  static const String columnPlaylistId = 'id';
  static const String columnPlaylistName = 'name';

  // Playlist tracks table columns...
  static const String columnPlaylistTracksPlaylistId = 'playlist_id';
  static const String columnPlaylistTracksTrackPath = 'track_path';
  static const String columnPlaylistTracksSortOrder = 'sort_order';

  // UI Settings table columns <<< NEW
  static const String columnUiSettingsKey = 'key';
  static const String columnUiSettingsValue = 'value';

  // SharedPreferences Keys...
  static const String _collectionDefinitionsKey = 'collection_definitions_list';
  static const String _generalTagsKey = 'general_tags_list';
  static const String _lastActiveCollectionIdKey = 'last_active_collection_id';

  // --- State ---
  Database? _database;
  CollectionDefinition? _activeCollectionDefinition;
  List<String> _localCollectionRootFolders = [];
  final _loadingController = StreamController<bool>.broadcast();
  Stream<bool> get loadingStream => _loadingController.stream;
  bool _isLoading = false;

  // --- Collection Definition Management ---
  // (Methods: loadCollectionDefinitions, _saveCollectionDefinitions, addCollectionDefinition, removeCollectionDefinition)
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
    return [];
  }

  /// Updates the file path of an existing track while preserving other metadata.
  /// Handles converting the newPath to relative if the collection is shared.
  Future<int> updateTrackPath(int trackId, String newAbsolutePath) async {
    if (_database == null || !_database!.isOpen) {
      throw Exception("Database not open");
    }
    if (_activeCollectionDefinition == null) {
      throw Exception("No active collection definition");
    }

    String pathToStore = newAbsolutePath;
    // Convert to relative path if it's a shared collection and the path is within its root
    if (_activeCollectionDefinition!.type == CollectionType.shared &&
        !Uri.tryParse(
          newAbsolutePath,
        )!.isAbsolute && // Don't make URLs relative
        _activeCollectionDefinition!.rootPath != null) {
      try {
        if (pathLib.isAbsolute(newAbsolutePath) &&
            pathLib.isWithin(
              _activeCollectionDefinition!.rootPath!,
              newAbsolutePath,
            )) {
          pathToStore = pathLib.relative(
            newAbsolutePath,
            from: _activeCollectionDefinition!.rootPath!,
          );
        } else if (!pathLib.isAbsolute(newAbsolutePath)) {
          // If the passed path is already relative (e.g. from some other logic)
          // and it's a shared collection, assume it's correct relative to the root.
          // This case might need careful handling depending on where newAbsolutePath comes from.
          // For now, we assume newAbsolutePath is indeed absolute when passed to this specific function.
          print(
            "Warning: updateTrackPath received a relative path '$newAbsolutePath' for a shared collection. Storing as is, assuming it's relative to the root.",
          );
        }
        // If absolute but not within root, it will be stored as absolute.
      } catch (e) {
        print(
          "Warning: Could not make new path relative for '$newAbsolutePath'. Storing as is. Error: $e",
        );
        pathToStore = newAbsolutePath; // Fallback
      }
    }

    try {
      final count = await _database!.update(
        tableMusic,
        {columnPath: pathToStore}, // Only update the path column
        where: '$columnId = ?',
        whereArgs: [trackId],
      );
      if (count > 0) {
        print(
          "CollectionService: Updated path for track $trackId to '$pathToStore' (stored) from '$newAbsolutePath' (provided).",
        );
      } else {
        print("CollectionService: Track $trackId not found for path update.");
      }
      return count;
    } catch (e) {
      print("CollectionService: Error updating path for track $trackId: $e");
      rethrow;
    }
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

  Future<void> addCollectionDefinition(CollectionDefinition definition) async {
    final definitions = await loadCollectionDefinitions();
    if (!definitions.any((def) => def.id == definition.id)) {
      definitions.add(definition);
      await _saveCollectionDefinitions(definitions);
      print('Added collection definition: ${definition.name}');
    } else {
      print('Collection definition with ID ${definition.id} already exists.');
    }
  }

  // Helper to get duration using just_audio
  Future<int> _getAudioDuration(String path, bool isUrl) async {
    final player = AudioPlayer();
    int durationMs = 0;
    try {
      Duration? duration;
      if (isUrl) {
        duration = await player.setUrl(path);
      } else {
        duration = await player.setFilePath(path);
      }
      durationMs = duration?.inMilliseconds ?? 0;
    } catch (e) {
      print("CollectionService: Error getting duration for $path: $e");
      // Handle specific errors if needed (e.g., network, file not found)
      durationMs = 0; // Default to 0 on error
    } finally {
      await player.dispose(); // Dispose the temporary player
    }
    // print("CollectionService: Fetched duration for $path: $durationMs ms");
    return durationMs;
  }

  Future<void> removeCollectionDefinition(String id) async {
    final definitions = await loadCollectionDefinitions();
    final initialLength = definitions.length;
    definitions.removeWhere((def) => def.id == id);
    if (definitions.length < initialLength) {
      await _saveCollectionDefinitions(definitions);
      print('Removed collection definition with ID: $id');
    }
  }

  // --- Service Lifecycle & Collection Switching ---
  // (Methods: initialize, openCollection, closeCollection, getActiveCollection, getActiveDatabase)
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
      // Ensure directories exist
      if (definition.type == CollectionType.shared) {
        final dbDir = Directory(definition.rootPath!);
        if (!await dbDir.exists()) {
          throw Exception(
            "Shared collection root directory does not exist: ${definition.rootPath}",
          );
        }
      } else {
        // Local
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

  Database? getActiveDatabase() {
    if (_database != null && _database!.isOpen) {
      return _database;
    }
    print("Warning: getActiveDatabase called but database is null or closed.");
    return null;
  }

  // --- Database Initialization and Migration ---
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
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future _onCreate(Database db, int version) async {
    // Music Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableMusic (
        $columnId INTEGER PRIMARY KEY, $columnTitle TEXT NOT NULL,
        $columnArtist TEXT NOT NULL, $columnAlbum TEXT NOT NULL,
        $columnAlbumArtist TEXT, $columnComposer TEXT,
        $columnGenre TEXT, $columnYear INTEGER,
        $columnTrackNumber INTEGER, $columnDiscNumber INTEGER,
        $columnBpm INTEGER,
        $columnPath TEXT NOT NULL, $columnIsUrl INTEGER NOT NULL,
        $columnDuration INTEGER NOT NULL, $columnTimeMarkers TEXT,
        $columnWaveformData TEXT, $columnRating INTEGER DEFAULT 0,
        $columnComment TEXT DEFAULT '', $columnGeneralTags TEXT
      )
    ''');
    // Local Root Folders Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableLocalRoots ( path TEXT PRIMARY KEY )
    ''');
    // Playlist Tables
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablePlaylists (
        $columnPlaylistId TEXT PRIMARY KEY, $columnPlaylistName TEXT NOT NULL
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
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_id
      ON $tablePlaylistTracks ($columnPlaylistTracksPlaylistId)
    ''');
    // --- UI Settings Table --- <<< NEW
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableUiSettings (
        $columnUiSettingsKey TEXT PRIMARY KEY,
        $columnUiSettingsValue TEXT
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migrations from v1 to v2 (Waveform, Rating, Comment, Tags, Playlist tables)
    if (oldVersion < 2) {
      print("Applying v1 -> v2 upgrades...");
      // Add columns to music table (use try-catch for safety)
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
      // Add new tables
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
        await db.execute(
          ''' CREATE TABLE IF NOT EXISTS $tablePlaylistTracks (
              $columnPlaylistTracksPlaylistId TEXT NOT NULL, $columnPlaylistTracksTrackPath TEXT NOT NULL,
              $columnPlaylistTracksSortOrder INTEGER,
              FOREIGN KEY ($columnPlaylistTracksPlaylistId) REFERENCES $tablePlaylists ($columnPlaylistId) ON DELETE CASCADE )''',
        );
        await db.execute(
          ''' CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_id ON $tablePlaylistTracks ($columnPlaylistTracksPlaylistId) ''',
        );
      } catch (e) {
        print("Could not add $tablePlaylistTracks table/index: $e");
      }
    }
    // Migration from v2 to v3 (Rename 'tags' to 'timeMarkers')
    if (oldVersion < 3) {
      print("Applying v2 -> v3 upgrades...");
      try {
        const String oldColumnTags = 'tags'; // Define old name for migration
        await db.execute(
          'ALTER TABLE $tableMusic RENAME COLUMN $oldColumnTags TO $columnTimeMarkers',
        );
        print("Renamed column '$oldColumnTags' to '$columnTimeMarkers'.");
      } catch (e) {
        print("Error renaming 'tags' column to '$columnTimeMarkers': $e");
      }
    }
    // --- NEW: v3 -> v4 upgrade (Add ui_settings table) ---
    if (oldVersion < 4) {
      print("Applying v3 -> v4 upgrades...");
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $tableUiSettings (
            $columnUiSettingsKey TEXT PRIMARY KEY,
            $columnUiSettingsValue TEXT
          )
        ''');
        print("Added '$tableUiSettings' table.");
      } catch (e) {
        print("Error adding '$tableUiSettings' table: $e");
      }
    }
    // --- NEW: v4 -> v5 upgrade (Add new metadata columns to music table) ---
    if (oldVersion < 5) {
      print("Applying v4 -> v5 upgrades (Adding metadata columns)...");
      Future<void> addColumn(String name, String type) async {
        try {
          await db.execute('ALTER TABLE $tableMusic ADD COLUMN $name $type');
          print("Added column '$name' to '$tableMusic'.");
        } catch (e) {
          // Ignore error if column already exists (common in development)
          if (e.toString().contains('duplicate column name')) {
            print("Column '$name' already exists.");
          } else {
            print("Error adding column '$name': $e");
            // Consider rethrowing if it's a critical error
          }
        }
      }

      await addColumn(columnAlbumArtist, 'TEXT');
      await addColumn(columnComposer, 'TEXT');
      await addColumn(columnGenre, 'TEXT');
      await addColumn(columnYear, 'INTEGER');
      await addColumn(columnTrackNumber, 'INTEGER');
      await addColumn(columnDiscNumber, 'INTEGER');
      await addColumn(columnBpm, 'INTEGER');
    }
  }

  // --- Root Folder Management ---
  // (Methods: _loadLocalCollectionRootFolders, addRootFolder, removeRootFolder, getRootFolders)
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

  Future<void> updateTrackDuration(int trackId, int durationMs) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    try {
      final count = await _database!.update(
        tableMusic,
        {columnDuration: durationMs}, // Update only the duration column
        where: '$columnId = ?',
        whereArgs: [trackId],
      );
      if (count > 0) {
        print(
          "CollectionService: Updated duration for track $trackId to $durationMs ms.",
        );
      } else {
        print(
          "CollectionService: Track $trackId not found for duration update.",
        );
      }
    } catch (e) {
      print(
        "CollectionService: Error updating duration for track $trackId: $e",
      );
      rethrow; // Re-throw to be caught by BLoC
    }
  }

  // --- ADDED: Update methods for new metadata ---
  Future<void> updateTrackAlbumArtist(int trackId, String? value) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnAlbumArtist: value},
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    print("CollectionService: Updated albumArtist for track $trackId");
  }

  Future<void> updateTrackComposer(int trackId, String? value) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnComposer: value},
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    print("CollectionService: Updated composer for track $trackId");
  }

  Future<void> updateTrackGenre(int trackId, String? value) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnGenre: value},
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    print("CollectionService: Updated genre for track $trackId");
  }

  Future<void> updateTrackYear(int trackId, int? value) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnYear: value},
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    print("CollectionService: Updated year for track $trackId");
  }

  Future<void> updateTrackNumber(int trackId, int? value) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnTrackNumber: value},
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    print("CollectionService: Updated trackNumber for track $trackId");
  }

  Future<void> updateTrackDiscNumber(int trackId, int? value) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnDiscNumber: value},
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    print("CollectionService: Updated discNumber for track $trackId");
  }

  Future<void> updateTrackBpm(int trackId, int? value) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnBpm: value},
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    print("CollectionService: Updated bpm for track $trackId");
  }
  // --- END ADDED Update methods ---

  List<String> getRootFolders() {
    if (_activeCollectionDefinition?.type == CollectionType.shared) {
      return [_activeCollectionDefinition!.rootPath!];
    } else if (_activeCollectionDefinition?.type == CollectionType.local) {
      return List<String>.unmodifiable(_localCollectionRootFolders);
    } else {
      return [];
    }
  }

  // --- Track CRUD Operations ---
  // (Helpers: _resolveTrackPath, _prepareTrackForDb)
  // (Methods: addTrack, updateTrack, deleteTrack, getTrack, getTrackByPath, getAllTracks, searchTracks)

  // Resolves relative path to absolute for shared collections
  Track _resolveTrackPath(Track track) {
    if (_activeCollectionDefinition?.type == CollectionType.shared &&
        !track.isUrl &&
        _activeCollectionDefinition?.rootPath != null) {
      try {
        final absolutePath = pathLib.join(
          _activeCollectionDefinition!.rootPath!,
          track.path, // track.path is relative here
        );
        return track.copyWith(path: absolutePath);
      } catch (e) {
        print(
          "Error resolving relative path ${track.path} with root ${_activeCollectionDefinition!.rootPath}: $e",
        );
        return track; // Return original track if resolution fails
      }
    }
    return track; // Return as is for local or URLs
  }

  // Converts absolute path to relative for shared collections before DB storage
  Map<String, dynamic> _prepareTrackForDb(Track track) {
    String pathToStore = track.path;
    if (_activeCollectionDefinition?.type == CollectionType.shared &&
        !track.isUrl && // Don't make URLs relative
        _activeCollectionDefinition?.rootPath != null) {
      try {
        // Ensure paths are absolute before making relative
        if (!pathLib.isAbsolute(track.path)) {
          print(
            "Warning: Trying to make non-absolute path relative: ${track.path}",
          );
        } else if (!pathLib.isAbsolute(
          _activeCollectionDefinition!.rootPath!,
        )) {
          print(
            "Warning: Root path is not absolute: ${_activeCollectionDefinition!.rootPath}",
          );
        } else if (pathLib.isWithin(
          _activeCollectionDefinition!.rootPath!,
          track.path,
        )) {
          // Only make relative if it's actually within the root
          pathToStore = pathLib.relative(
            track.path,
            from: _activeCollectionDefinition!.rootPath!,
          );
        } else {
          print(
            "Warning: Track path ${track.path} is outside shared root ${_activeCollectionDefinition!.rootPath}. Storing absolute path.",
          );
          // Keep pathToStore as the absolute path
        }
      } catch (e) {
        print(
          "Warning: Could not make path relative for ${track.path} against root ${_activeCollectionDefinition!.rootPath}. Storing absolute path. Error: $e",
        );
        pathToStore = track.path; // Fallback to absolute path
      }
    }
    // Return JSON representation with the potentially modified path
    return track.copyWith(path: pathToStore).toJson();
  }

  Future<int> addTrack(Track track) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    final data = _prepareTrackForDb(track); // Convert path if needed
    return await _database!.insert(tableMusic, data);
  }

  Future<int> updateTrack(Track track) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    final data = _prepareTrackForDb(track); // Convert path if needed
    return await _database!.update(
      tableMusic,
      data,
      where: '$columnId = ?',
      whereArgs: [track.id],
    );
  }

  Future<int> deleteTrack(int id) async {
    if (_database == null || !_database!.isOpen) {
      print(
        "CollectionService.deleteTrack: ERROR - Database not open for track $id",
      ); // <<< Added Log
      throw Exception("Database not open");
    }
    print(
      "CollectionService.deleteTrack: Attempting to delete track with ID: $id",
    ); // <<< Added Log
    try {
      final int count = await _database!.delete(
        tableMusic,
        where: '$columnId = ?',
        whereArgs: [id],
      );
      print(
        "CollectionService.deleteTrack: Database delete result for ID $id. Rows affected: $count",
      ); // <<< Added Log
      return count;
    } catch (e) {
      print(
        "CollectionService.deleteTrack: Database ERROR deleting track $id: $e",
      ); // <<< Added Log
      rethrow; // Re-throw the database exception
    }
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
      return _resolveTrackPath(track); // Resolve path after loading
    }
    return null;
  }

  Future<Track?> getTrackByPath(String absolutePath) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    String pathQuery = absolutePath;
    // Convert search path to relative if it's a shared collection
    if (_activeCollectionDefinition?.type == CollectionType.shared &&
        _activeCollectionDefinition?.rootPath != null &&
        !Uri.tryParse(absolutePath)!.isAbsolute) {
      // Don't try to make URLs relative
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
          pathQuery = absolutePath; // Assume already relative
          print(
            "Warning: getTrackByPath received potentially relative path for shared collection: $absolutePath",
          );
        } else {
          print(
            "Warning: getTrackByPath received absolute path outside shared root: $absolutePath",
          );
          return null; // Path is outside the shared root, cannot exist in DB relatively
        }
      } catch (e) {
        print(
          "Warning: Could not make search path relative. Querying absolute path. Error: $e",
        );
        pathQuery =
            absolutePath; // Fallback to querying absolute path (might fail for shared)
      }
    }
    // Query using the potentially modified path
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: '$columnPath = ?',
      whereArgs: [pathQuery],
    );
    if (maps.isNotEmpty) {
      final track = Track.fromJson(maps.first);
      return _resolveTrackPath(track); // Resolve path after loading
    }
    return null;
  }

  Future<List<Track>> getAllTracks() async {
    if (_database == null || !_database!.isOpen) return [];
    final List<Map<String, dynamic>> maps = await _database!.query(tableMusic);
    // Resolve paths for all tracks after loading
    return maps.map((map) => _resolveTrackPath(Track.fromJson(map))).toList();
  }

  Future<List<Track>> searchTracks(String query) async {
    if (_database == null || !_database!.isOpen) return [];
    final String lowercaseQuery = query.toLowerCase();
    final String wildcardQuery = '%$lowercaseQuery%';
    // Search across relevant fields
    String whereClause = '''
      LOWER($columnTitle) LIKE ? OR LOWER($columnArtist) LIKE ? OR
      LOWER($columnAlbum) LIKE ? OR LOWER($columnComment) LIKE ? OR
      LOWER($columnGeneralTags) LIKE ? OR LOWER($columnPath) LIKE ?
    ''';
    List<dynamic> whereArgs = List.filled(6, wildcardQuery);

    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: whereClause,
      whereArgs: whereArgs,
    );
    // Resolve paths for search results
    return maps.map((map) => _resolveTrackPath(Track.fromJson(map))).toList();
  }

  // --- Metadata Update Methods ---
  // (Methods: updateRating, updateComment, addGeneralTag, removeGeneralTag, updateTrackMarkers)

  Future<void> updateRating(int trackId, int rating) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnRating: rating},
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> updateComment(int trackId, String comment) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnComment: comment},
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> addGeneralTag(int trackId, String tag) async {
    final track = await getTrack(trackId); // Gets track with resolved path
    if (track != null) {
      final tags = List<String>.from(track.generalTags);
      if (!tags.contains(tag)) {
        tags.add(tag);
        // Use updateTrack which handles path preparation for DB
        await updateTrack(track.copyWith(generalTags: tags));
      }
    }
  }

  Future<void> removeGeneralTag(int trackId, String tag) async {
    final track = await getTrack(trackId); // Gets track with resolved path
    if (track != null) {
      final tags = List<String>.from(track.generalTags);
      if (tags.remove(tag)) {
        // Use updateTrack which handles path preparation for DB
        await updateTrack(track.copyWith(generalTags: tags));
      }
    }
  }

  Future<void> updateTrackMarkers(int trackId, List<TimeMarker> markers) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    try {
      final String markersJson = jsonEncode(
        markers.map((marker) => marker.toJson()).toList(),
      );
      final count = await _database!.update(
        tableMusic,
        {columnTimeMarkers: markersJson},
        where: '$columnId = ?',
        whereArgs: [trackId],
      );
      if (count == 0)
        print("Warning: updateTrackMarkers - Track ID $trackId not found.");
      else
        print("Successfully updated markers for track ID $trackId.");
    } catch (e) {
      print("Error updating track markers for ID $trackId: $e");
      rethrow;
    }
  }

  // --- Tag Definition Management (Global via SharedPreferences) ---
  // (Methods: getAllTags, _saveAllTags, addTag, removeTag, updateTag)
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

  // --- UI Settings --- <<< NEW
  Future<void> saveUiSetting(String key, String value) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    try {
      await _database!.insert(tableUiSettings, {
        columnUiSettingsKey: key,
        columnUiSettingsValue: value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // print("Saved UI setting: $key");
    } catch (e) {
      print("Error saving UI setting for key $key: $e");
      rethrow;
    }
  }

  Future<String?> loadUiSetting(String key) async {
    if (_database == null || !_database!.isOpen) return null;
    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        tableUiSettings,
        where: '$columnUiSettingsKey = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return maps.first[columnUiSettingsValue] as String?;
      }
    } catch (e) {
      print("Error loading UI setting for key $key: $e");
    }
    return null;
  }

  // --- Column Config Convenience Methods --- <<< NEW
  static const String _columnConfigKey = 'trackTableColumnConfig';

  Future<void> saveColumnConfig(Map<String, dynamic> config) async {
    try {
      final jsonString = jsonEncode(config);
      await saveUiSetting(_columnConfigKey, jsonString);
      print("Saved column configuration.");
    } catch (e) {
      print("Error saving column config: $e");
    }
  }

  Future<Map<String, dynamic>?> loadColumnConfig() async {
    try {
      final jsonString = await loadUiSetting(_columnConfigKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        return jsonDecode(jsonString) as Map<String, dynamic>?;
      }
    } catch (e) {
      print("Error loading/decoding column config: $e");
    }
    print("No saved column config found or error loading.");
    return null;
  }

  // --- Utility Methods ---
  // (Methods: setLoading, isLoading, dispose, deleteFolderFromDisk, getTracksInFolder, loadLastActiveCollectionId, saveLastActiveCollectionId)
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
    final allTracks =
        await getAllTracks(); // Gets tracks with resolved absolute paths

    final normalizedTargetFolderPath = pathLib.normalize(folderPath);
    print(
      "[getTracksInFolder] Normalized Target Path: '$normalizedTargetFolderPath'",
    );

    for (final track in allTracks) {
      if (!track.isUrl) {
        final normalizedTrackPath = pathLib.normalize(track.path);
        final trackDirectory = pathLib.dirname(normalizedTrackPath);

        // print("  [Checking Track] ID: ${track.id}, Title: ${track.title}");
        // print("    Track Path (Normalized): '$normalizedTrackPath'");
        // print("    Track Dir  (Normalized): '$trackDirectory'");

        if (pathLib.equals(trackDirectory, normalizedTargetFolderPath) ||
            pathLib.isWithin(normalizedTargetFolderPath, trackDirectory)) {
          // print("    --> MATCH FOUND!");
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

  static const String _lastScannedFilesKeyPrefix =
      'lastScannedFiles_'; // Add prefix

  Future<void> saveLastScanState(
    String collectionId,
    Set<String> filePaths,
  ) async {
    final jsonString = jsonEncode(filePaths.toList());
    await saveUiSetting('$_lastScannedFilesKeyPrefix$collectionId', jsonString);
  }

  Future<Set<String>?> loadLastScanState(String collectionId) async {
    final jsonString = await loadUiSetting(
      '$_lastScannedFilesKeyPrefix$collectionId',
    );
    if (jsonString != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(jsonString);
        return Set<String>.from(decodedList.cast<String>());
      } catch (e) {
        print("Error decoding last scan state: $e");
        return null;
      }
    }
    return null;
  }

  Future<void> updateTrackTitle(int trackId, String title) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnTitle: title}, // Update only the title column
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    print("CollectionService: Updated title for track $trackId");
  }

  Future<void> updateTrackArtist(int trackId, String artist) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnArtist: artist}, // Update only the artist column
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    print("CollectionService: Updated artist for track $trackId");
  }

  Future<void> updateTrackAlbum(int trackId, String album) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    await _database!.update(
      tableMusic,
      {columnAlbum: album}, // Update only the album column
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    print("CollectionService: Updated album for track $trackId");
  }

  // --- Methods needing review/implementation ---
  // (Methods: addLocalFile, addUrl, importFromFile, exportToFile)
  Future<Track?> addLocalFile(String filePath) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    if (_activeCollectionDefinition == null)
      throw Exception("No active collection");

    final normalizedFilePath = pathLib.normalize(filePath);
    String pathToCheckInDb = normalizedFilePath;
    if (_activeCollectionDefinition?.type == CollectionType.shared &&
        _activeCollectionDefinition?.rootPath != null &&
        pathLib.isWithin(
          _activeCollectionDefinition!.rootPath!,
          normalizedFilePath,
        )) {
      try {
        pathToCheckInDb = pathLib.relative(
          normalizedFilePath,
          from: _activeCollectionDefinition!.rootPath!,
        );
      } catch (e) {
        return null;
      }
    }

    final List<Map<String, dynamic>> existingMaps = await _database!.query(
      tableMusic,
      where: '$columnPath = ?',
      whereArgs: [pathToCheckInDb],
      limit: 1,
    );

    if (existingMaps.isNotEmpty) {
      // <<< Track EXISTS - Return existing data >>>
      final existingTrack = Track.fromJson(existingMaps.first);
      print(
        'Track already exists: ${existingTrack.title}. Returning existing data.',
      );
      return _resolveTrackPath(existingTrack);
    } else {
      // <<< Track does NOT exist - Fetch duration and add >>>
      print(
        "Track not found in DB. Fetching duration for: $normalizedFilePath",
      );
      final durationMs = await _getAudioDuration(normalizedFilePath, false);
      print("Duration fetched: $durationMs ms");

      final filename = pathLib.basename(normalizedFilePath);
      final title = pathLib.basenameWithoutExtension(normalizedFilePath);

      final track = Track(
        title: title,
        artist: 'Unknown',
        album: 'Unknown',
        path: normalizedFilePath,
        isUrl: false,
        duration: durationMs, // <<< Use fetched duration
        waveformData: null,
        rating: 0,
        comment: '',
        generalTags: [],
      );

      final id = await addTrack(track); // addTrack handles _prepareTrackForDb
      print(
        "Added NEW track ${track.title} with ID $id and duration $durationMs",
      );
      return _resolveTrackPath(track.copyWith(id: id));
    }
  }

  Future<Track> addUrl(String url) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    if (_activeCollectionDefinition == null)
      throw Exception("No active collection");

    setLoading(true);
    try {
      final List<Map<String, dynamic>> existingMaps = await _database!.query(
        tableMusic,
        where: '$columnPath = ?',
        whereArgs: [url],
        limit: 1,
      );

      if (existingMaps.isNotEmpty) {
        // <<< Track EXISTS - Return existing data >>>
        final existingTrack = Track.fromJson(existingMaps.first);
        print(
          'URL already exists: ${existingTrack.title}. Returning existing data.',
        );
        return _resolveTrackPath(existingTrack);
      } else {
        // <<< Track does NOT exist - Fetch metadata/duration and add >>>
        print("URL not found in DB. Fetching metadata/duration for: $url");
        String trackTitle = url;
        int trackDurationMs = 0;
        // ... (rest of metadata fetching logic as before, including _getAudioDuration if needed) ...
        bool isYouTube = false;
        String artist = 'Unknown';
        String album = 'Unknown';
        String effectiveUrl = url;

        var videoId = VideoId.parseVideoId(url);
        if (videoId != null) {
          isYouTube = true;
          // ... (fetch YT metadata including duration) ...
          try {
            var video = await _yt.videos.get(videoId);
            trackTitle = video.title;
            trackDurationMs = video.duration?.inMilliseconds ?? 0;
            artist = video.author;
            album = 'YouTube';
            if (trackDurationMs == 0) {
              var manifest = await _yt.videos.streamsClient.getManifest(
                videoId,
              );
              var streamInfo = manifest.audioOnly.withHighestBitrate();
              effectiveUrl = streamInfo.url.toString();
            }
          } catch (ytError) {
            /* ... */
          }
        } else {
          /* ... */
        }

        if (trackDurationMs == 0) {
          trackDurationMs = await _getAudioDuration(effectiveUrl, true);
        }
        // --- End metadata/duration fetching ---

        final track = Track(
          title: trackTitle,
          artist: artist,
          album: album,
          path: url,
          isUrl: true,
          duration: trackDurationMs, // <<< Use fetched duration
          waveformData: null,
          rating: 0,
          comment: '',
          generalTags: [],
        );

        final id = await addTrack(track);
        print(
          "Added NEW URL track ${track.title} with ID $id and duration $trackDurationMs",
        );
        return _resolveTrackPath(track.copyWith(id: id));
      }
    } catch (e, stackTrace) {
      print('Error adding URL: $e\n$stackTrace');
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  Future<void> importFromFile(String jsonFilePath) async {
    print("Import not fully implemented for hybrid collections.");
    // TODO: Implement import logic considering collection type and path handling.
  }

  Future<void> exportToFile(String jsonFilePath) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    try {
      final tracks =
          await getAllTracks(); // Gets tracks with resolved absolute paths
      final jsonData =
          tracks
              .map((track) => track.toJson())
              .toList(); // Use resolved paths for export
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
