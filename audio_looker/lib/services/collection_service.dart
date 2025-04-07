import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart'; // For Color
import 'package:path/path.dart' as pathLib; // Use alias
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart'; // For unique collection IDs

// Keep AudioService import if needed for waveform, etc.
// import 'package:audio_looker/services/audio_service.dart';

// --- Data Models (Track and Tag remain mostly the same) ---

class Track {
  final int? id;
  final String title;
  final String artist;
  final String album;
  // NOTE: This path can be ABSOLUTE (for local) or RELATIVE (for shared)
  final String path;
  final bool isUrl; // URLs are always treated as absolute
  final int duration; // in milliseconds
  final Map<String, dynamic> tags; // Time-based tags
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
    this.tags = const {},
    this.waveformData,
    this.rating = 0,
    this.comment = '',
    this.generalTags = const [],
  });

  // fromJson remains the same
  factory Track.fromJson(Map<String, dynamic> json) {
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
      tags: json['tags'] != null ? jsonDecode(json['tags']) : {},
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
      'tags': jsonEncode(tags),
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
    Map<String, dynamic>? tags,
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
      tags: tags ?? this.tags,
      waveformData: waveformData ?? this.waveformData,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      generalTags: generalTags ?? this.generalTags,
    );
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
  static const int _databaseVersion = 2; // Keep DB version
  static const String tableMusic = 'music';
  // Column names remain the same
  static const String columnId = 'id';
  static const String columnTitle = 'title';
  static const String columnArtist = 'artist';
  static const String columnAlbum = 'album';
  static const String columnPath = 'path'; // Holds absolute OR relative path
  static const String columnIsUrl = 'isUrl';
  static const String columnDuration = 'duration';
  static const String columnTags = 'tags';
  static const String columnWaveformData = 'waveformData';
  static const String columnRating = 'rating';
  static const String columnComment = 'comment';
  static const String columnGeneralTags = 'generalTags';

  // SharedPreferences Keys
  static const String _collectionDefinitionsKey = 'collection_definitions_list';
  static const String _generalTagsKey = 'general_tags_list'; // Global tags
  // REMOVED: _rootFoldersKey (now managed per local collection or via definition)

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

  // Initializes the service, potentially loading the last active collection
  Future<void> initialize() async {
    // TODO: Load last active collection ID from Prefs?
    // For now, we just prepare for opening a collection later.
    print("CollectionService initialized. Ready to open a collection.");
    // await _audioService.initialize(); // If using AudioService
  }

  // Opens a specific collection
  Future<void> openCollection(CollectionDefinition definition) async {
    setLoading(true);
    print("Opening collection: ${definition.name} (${definition.type.name})");
    try {
      // Close existing DB if open
      await closeCollection();

      _activeCollectionDefinition = definition;

      // Determine the actual DB path
      String dbFilePath = definition.dbPath;
      // For shared, ensure the directory exists (it's the rootPath)
      if (definition.type == CollectionType.shared) {
        final dbDir = Directory(definition.rootPath!);
        if (!await dbDir.exists()) {
          throw Exception(
            "Shared collection root directory does not exist: ${definition.rootPath}",
          );
        }
        // dbPath in definition for shared IS the full path including filename
      } else {
        // For local, ensure the directory exists (app data dir)
        final dbDir = Directory(pathLib.dirname(dbFilePath));
        if (!await dbDir.exists()) {
          await dbDir.create(recursive: true);
        }
      }

      // Open the database
      _database = await _initDatabase(dbFilePath);
      print("Database opened at: $dbFilePath");

      // Load root folders IF it's a local collection
      if (definition.type == CollectionType.local) {
        await _loadLocalCollectionRootFolders();
      } else {
        _localCollectionRootFolders = []; // Clear for shared collections
      }

      print("Collection ${definition.name} opened successfully.");
    } catch (e, stackTrace) {
      print("Error opening collection ${definition.name}: $e");
      print(stackTrace);
      _activeCollectionDefinition = null; // Reset active definition on error
      _database = null;
      _localCollectionRootFolders = [];
      // Rethrow or handle error appropriately
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  // Closes the currently active collection
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

  // Returns the currently active collection definition, if any
  CollectionDefinition? getActiveCollection() {
    return _activeCollectionDefinition;
  }

  // Modified: Initializes or opens database at a specific path
  Future<Database> _initDatabase(String dbPath) async {
    // Ensure the directory exists before opening
    final dbDir = Directory(pathLib.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
      print("Created database directory: ${dbDir.path}");
    }

    return await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // _onCreate and _onUpgrade remain the same (define table structure)
  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableMusic (
        $columnId INTEGER PRIMARY KEY,
        $columnTitle TEXT NOT NULL,
        $columnArtist TEXT NOT NULL,
        $columnAlbum TEXT NOT NULL,
        $columnPath TEXT NOT NULL,
        $columnIsUrl INTEGER NOT NULL,
        $columnDuration INTEGER NOT NULL,
        $columnTags TEXT,
        $columnWaveformData TEXT,
        $columnRating INTEGER DEFAULT 0,
        $columnComment TEXT DEFAULT '',
        $columnGeneralTags TEXT
      )
    ''');
    // --- NEW: Table for local collection root folders ---
    await db.execute('''
      CREATE TABLE local_root_folders (
        path TEXT PRIMARY KEY
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns for version 2
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
      try {
        // Add root folders table only if upgrading from v1
        await db.execute('''
            CREATE TABLE IF NOT EXISTS local_root_folders (
              path TEXT PRIMARY KEY
            )
          ''');
      } catch (e) {
        print("Could not add local_root_folders table: $e");
      }
    }
    // Add future upgrade logic here
    // if (oldVersion < 3) { ... }
  }

  // --- Root Folder Management (Revised) ---

  // Loads root folders for the *active local* collection from its DB
  Future<void> _loadLocalCollectionRootFolders() async {
    if (_database == null ||
        !_database!.isOpen ||
        _activeCollectionDefinition?.type != CollectionType.local) {
      _localCollectionRootFolders = [];
      return;
    }
    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        'local_root_folders',
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

  // Adds a root folder path to the *active local* collection's DB
  Future<void> addRootFolder(String folderPath) async {
    if (_activeCollectionDefinition?.type != CollectionType.local) {
      print('Cannot add root folders to non-local collections.');
      return; // Or throw an error
    }
    if (_database == null || !_database!.isOpen) {
      print('Error: Database not open in addRootFolder');
      return;
    }

    final normalizedPath = folderPath.replaceAll('\\', '/');
    if (!_localCollectionRootFolders.contains(normalizedPath)) {
      try {
        await _database!.insert(
          'local_root_folders',
          {'path': normalizedPath},
          conflictAlgorithm: ConflictAlgorithm.ignore, // Ignore if exists
        );
        _localCollectionRootFolders.add(
          normalizedPath,
        ); // Update in-memory list
        print('Added root folder to local collection: $normalizedPath');
      } catch (e) {
        print('Error adding local root folder to DB: $e');
      }
    }
  }

  // Removes a root folder path from the *active local* collection's DB
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
        'local_root_folders',
        where: 'path = ?',
        whereArgs: [normalizedPath],
      );
      if (count > 0) {
        _localCollectionRootFolders.remove(
          normalizedPath,
        ); // Update in-memory list
        print('Removed root folder from local collection: $normalizedPath');
      }
    } catch (e) {
      print('Error removing local root folder from DB: $e');
    }
  }

  // Gets root folders for the *active* collection
  List<String> getRootFolders() {
    if (_activeCollectionDefinition?.type == CollectionType.shared) {
      // Shared collections have exactly one root
      return [_activeCollectionDefinition!.rootPath!];
    } else if (_activeCollectionDefinition?.type == CollectionType.local) {
      // Return the list loaded for the active local collection
      return List<String>.unmodifiable(_localCollectionRootFolders);
    } else {
      // No active collection or unknown type
      return [];
    }
  }

  // --- Track CRUD Operations (Revised for Path Handling) ---

  // Helper to resolve path before returning Track object
  Track _resolveTrackPath(Track track) {
    if (_activeCollectionDefinition?.type == CollectionType.shared &&
        !track.isUrl && // Don't resolve URLs
        _activeCollectionDefinition?.rootPath != null) {
      // Prepend root path to the stored relative path
      final absolutePath = pathLib.join(
        _activeCollectionDefinition!.rootPath!,
        track.path,
      );
      // Return a new Track instance with the resolved absolute path
      return track.copyWith(path: absolutePath);
    }
    // For local collections or URLs, the path is already absolute
    return track;
  }

  // Helper to prepare track data for DB insertion/update
  Map<String, dynamic> _prepareTrackForDb(Track track) {
    String pathToStore = track.path;
    if (_activeCollectionDefinition?.type == CollectionType.shared &&
        !track.isUrl &&
        _activeCollectionDefinition?.rootPath != null) {
      // Calculate and store relative path
      try {
        pathToStore = pathLib.relative(
          track.path,
          from: _activeCollectionDefinition!.rootPath!,
        );
      } catch (e) {
        print(
          "Warning: Could not make path relative for ${track.path} against root ${_activeCollectionDefinition!.rootPath}. Storing absolute path. Error: $e",
        );
        // Fallback to absolute path if relative calculation fails (e.g., different drives on Windows)
        pathToStore = track.path;
      }
    }
    // Create a temporary track with the path to store, then convert to JSON
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
      return _resolveTrackPath(track); // Resolve path before returning
    }
    return null;
  }

  // Get track by path - needs careful handling for shared collections
  Future<Track?> getTrackByPath(String absolutePath) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");

    String pathQuery = absolutePath;
    // If searching in a shared collection, convert the absolute path to relative for the query
    if (_activeCollectionDefinition?.type == CollectionType.shared &&
        _activeCollectionDefinition?.rootPath != null) {
      try {
        // Ensure the input path is actually within the root
        if (pathLib.isWithin(
          _activeCollectionDefinition!.rootPath!,
          absolutePath,
        )) {
          pathQuery = pathLib.relative(
            absolutePath,
            from: _activeCollectionDefinition!.rootPath!,
          );
        } else {
          // Path is not within the shared root, it cannot exist in this DB
          return null;
        }
      } catch (e) {
        print(
          "Warning: Could not make search path relative. Querying absolute path. Error: $e",
        );
        pathQuery = absolutePath; // Fallback
      }
    }

    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where:
          '$columnPath = ?', // Query the path stored in DB (relative or absolute)
      whereArgs: [pathQuery],
    );

    if (maps.isNotEmpty) {
      final track = Track.fromJson(maps.first);
      // Resolve path even if found via relative, so caller always gets absolute
      return _resolveTrackPath(track);
    }
    return null;
  }

  Future<List<Track>> getAllTracks() async {
    if (_database == null || !_database!.isOpen)
      return []; // Return empty if DB not open
    final List<Map<String, dynamic>> maps = await _database!.query(tableMusic);
    // Resolve paths for all tracks before returning
    return maps.map((map) => _resolveTrackPath(Track.fromJson(map))).toList();
  }

  // Modified search to handle path resolution and potentially relative paths
  Future<List<Track>> searchTracks(String query) async {
    if (_database == null || !_database!.isOpen) return [];

    final String lowercaseQuery = query.toLowerCase();
    final String wildcardQuery = '%$lowercaseQuery%';

    // Base WHERE clause
    String whereClause = '''
      LOWER($columnTitle) LIKE ? OR
      LOWER($columnArtist) LIKE ? OR
      LOWER($columnAlbum) LIKE ? OR
      LOWER($columnComment) LIKE ? OR
      LOWER($columnGeneralTags) LIKE ?
    ''';
    List<dynamic> whereArgs = [
      wildcardQuery, // title
      wildcardQuery, // artist
      wildcardQuery, // album
      wildcardQuery, // comment
      wildcardQuery, // generalTags
    ];

    // Add path search - slightly different for shared vs local
    // For simplicity, we search the stored path (relative or absolute)
    // A more advanced search might try resolving relative paths first.
    whereClause += ' OR LOWER($columnPath) LIKE ?';
    whereArgs.add(wildcardQuery); // Search stored path value

    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: whereClause,
      whereArgs: whereArgs,
    );

    // Resolve paths for all found tracks
    return maps.map((map) => _resolveTrackPath(Track.fromJson(map))).toList();
  }

  // --- Metadata Update Methods (Mostly Unchanged Logic, operate on active DB) ---

  Future<void> updateRating(int trackId, int rating) async {
    final track = await getTrack(trackId); // getTrack already resolves path
    if (track != null) {
      // Use copyWith which doesn't affect the path resolution
      final updatedTrack = track.copyWith(rating: rating);
      // updateTrack handles storing relative/absolute path correctly
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
    // Need to get the track *without* resolved path to update DB correctly
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    if (maps.isEmpty) return;
    final trackFromDb = Track.fromJson(maps.first); // Path is as stored in DB

    final tags = List<String>.from(trackFromDb.generalTags);
    if (!tags.contains(tag)) {
      tags.add(tag);
      // Use copyWith on the track fetched directly from DB
      final updatedTrack = trackFromDb.copyWith(generalTags: tags);
      // updateTrack expects a Track object, it will handle path prep internally
      await updateTrack(updatedTrack);
    }
  }

  Future<void> removeGeneralTag(int trackId, String tag) async {
    // Need to get the track *without* resolved path to update DB correctly
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: '$columnId = ?',
      whereArgs: [trackId],
    );
    if (maps.isEmpty) return;
    final trackFromDb = Track.fromJson(maps.first); // Path is as stored in DB

    final tags = List<String>.from(trackFromDb.generalTags);
    tags.remove(tag);
    final updatedTrack = trackFromDb.copyWith(generalTags: tags);
    await updateTrack(updatedTrack);
  }

  // --- Tag Definition Management (Global via SharedPreferences - Unchanged) ---

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
      // TODO: Need BLoC/UI logic to remove this tag from all tracks across *all collections*
      // This becomes much harder now. Maybe tag removal should only affect the active collection?
      // For now, it just removes the definition globally.
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

  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      _loadingController.add(_isLoading);
    }
  }

  bool get isLoading => _isLoading;

  Future<void> dispose() async {
    await closeCollection(); // Ensure active DB is closed
    await _loadingController.close();
    // await _audioService.dispose(); // If used
    print("CollectionService disposed.");
  }

  // --- Methods needing review/implementation based on AudioService ---
  // addUrl, updateWaveformForTrack, needsWaveformLoading, addMultipleFiles
  // These need to be adapted to use the active collection context (type, rootPath)
  // and the _prepareTrackForDb / _resolveTrackPath helpers.
  // Example for addLocalFile:
  Future<Track> addLocalFile(String filePath) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    if (_activeCollectionDefinition == null)
      throw Exception("No active collection");

    // Check if track already exists (using absolute path for check)
    final existingTrack = await getTrackByPath(filePath);
    if (existingTrack != null) {
      print('Track already exists in database: ${existingTrack.title}');
      // TODO: Add waveform update logic if needed, similar to original code
      return existingTrack; // Return the resolved track
    }

    // TODO: Extract metadata (title, artist, duration) - Placeholder:
    final filename = pathLib.basename(filePath);
    final title = pathLib.basenameWithoutExtension(filePath);

    // TODO: Extract waveform data (using AudioService?) - Placeholder:
    List<double>? waveformData; // = await _loadWaveformData(filePath, false);

    // Create track with ABSOLUTE path initially
    final track = Track(
      title: title,
      artist: 'Unknown',
      album: 'Unknown',
      path: filePath, // Absolute path
      isUrl: false,
      duration: 0, // Placeholder
      waveformData: waveformData,
      rating: 0,
      comment: '',
      generalTags: [],
    );

    // addTrack handles storing relative/absolute path based on active collection
    final id = await addTrack(track);
    // Return the track with ID, resolving path if necessary for the caller
    return _resolveTrackPath(track.copyWith(id: id));
  }

  // --- ADDED addUrl Method ---
  Future<Track> addUrl(String url) async {
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    if (_activeCollectionDefinition == null)
      throw Exception("No active collection");
    setLoading(true);
    try {
      // Check if URL already exists (URLs are always absolute)
      final existingTrack = await getTrackByPath(url);
      if (existingTrack != null) {
        print('URL already exists in database: ${existingTrack.title}');
        // TODO: Add waveform update logic if needed
        return existingTrack; // Return resolved track
      }

      // Extract basic info from URL as placeholder
      final uri = Uri.parse(url);
      final filename = pathLib.basename(uri.path);
      final title =
          filename.isNotEmpty ? filename : url; // Use URL if path is empty

      // TODO: Extract waveform data (using AudioService?) - Placeholder:
      List<double>? waveformData; // = await _loadWaveformData(url, true);

      // Create track with URL as path
      final track = Track(
        title: title,
        artist: 'Unknown', // Placeholder
        album: 'Unknown', // Placeholder
        path: url, // Store the URL directly
        isUrl: true,
        duration: 0, // Placeholder - might get from stream later
        waveformData: waveformData,
        rating: 0,
        comment: '',
        generalTags: [],
      );

      // addTrack handles URLs correctly (doesn't try to make relative)
      final id = await addTrack(track);
      // Return the track with ID, resolving path (which does nothing for URLs)
      return _resolveTrackPath(track.copyWith(id: id));
    } catch (e) {
      print('Error adding URL: $e');
      rethrow; // Rethrow the error to be handled by the caller (e.g., BLoC)
    } finally {
      setLoading(false);
    }
  }

  // Placeholder - needs implementation detail based on AudioService interaction
  // Future<List<double>?> _loadWaveformData(String source, bool isUrl) async { return null; }

  // --- Import/Export (Needs adaptation) ---
  // Export needs to resolve paths to absolute before saving JSON
  // Import needs to make paths relative if importing into a shared collection

  Future<void> importFromFile(String jsonFilePath) async {
    // TODO: Implement - Read JSON, check active collection type,
    // make paths relative if importing to 'shared', add tracks.
    print("Import not fully implemented for hybrid collections.");
  }

  Future<void> exportToFile(String jsonFilePath) async {
    // TODO: Implement - Get all tracks (paths will be resolved to absolute),
    // convert to JSON, write file.
    print("Export not fully implemented for hybrid collections.");
    if (_database == null || !_database!.isOpen)
      throw Exception("Database not open");
    try {
      final tracks =
          await getAllTracks(); // Gets tracks with resolved absolute paths
      final jsonData =
          tracks
              .map((track) => track.toJson())
              .toList(); // toJson uses the path field
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
