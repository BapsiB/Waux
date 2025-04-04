import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:audio_looker/services/audio_service.dart';

class Track {
  final int? id;
  final String title;
  final String artist;
  final String album;
  final String path;
  final bool isUrl;
  final int duration; // in milliseconds
  final Map<String, dynamic> tags;
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

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      album: json['album'],
      path: json['path'],
      isUrl: json['isUrl'] == 1,
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'path': path,
      'isUrl': isUrl ? 1 : 0,
      'duration': duration,
      'tags': jsonEncode(tags),
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

class CollectionService {
  static const String _databaseName = 'music_collector.db';
  static const int _databaseVersion = 2; // Increased version for schema update

  static const String tableMusic = 'music';

  static const String columnId = 'id';
  static const String columnTitle = 'title';
  static const String columnArtist = 'artist';
  static const String columnAlbum = 'album';
  static const String columnPath = 'path';
  static const String columnIsUrl = 'isUrl';
  static const String columnDuration = 'duration';
  static const String columnTags = 'tags';
  static const String columnWaveformData = 'waveformData';
  static const String columnRating = 'rating';
  static const String columnComment = 'comment';
  static const String columnGeneralTags = 'generalTags';

  Database? _database;
  final AudioService _audioService = AudioService();

  // Add a loading state stream
  final _loadingController = StreamController<bool>.broadcast();
  Stream<bool> get loadingStream => _loadingController.stream;
  bool _isLoading = false;

  // Key for storing root folders in SharedPreferences
  static const String _rootFoldersKey = 'root_folders';

  static const String _generalTagsKey = 'general_tags_list';

  // Store root folders
  List<String> _rootFolders = [];

  // Cache to track which files we've already checked for waveforms
  final Set<String> _checkedWaveforms = {};

  CollectionService() {
    _audioService.initialize();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    _loadingController.add(_isLoading);
  }

  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    _database = await _initDatabase();

    // Load root folders
    await _loadRootFolders();
  }

  // New method to add a root folder
  Future<void> addRootFolder(String folderPath) async {
    // Normalize path separators for consistency
    final normalizedPath = folderPath.replaceAll('\\', '/');

    // Don't add duplicates
    if (!_rootFolders.contains(normalizedPath)) {
      _rootFolders.add(normalizedPath);
      await _saveRootFolders();
      print('Added root folder: $normalizedPath');
    } else {
      print('Root folder already exists: $normalizedPath');
    }
  }

  // New method to remove a root folder
  Future<void> removeRootFolder(String folderPath) async {
    final normalizedPath = folderPath.replaceAll('\\', '/');
    if (_rootFolders.remove(normalizedPath)) {
      await _saveRootFolders();
      print('Removed root folder: $normalizedPath');
    }
  }

  // New method to get all root folders
  List<String> getRootFolders() {
    return List<String>.from(_rootFolders);
  }

  // Save root folders to persistent storage
  Future<void> _saveRootFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_rootFoldersKey, _rootFolders);
      print('Saved ${_rootFolders.length} root folders');
    } catch (e) {
      print('Error saving root folders: $e');
    }
  }

  // Load root folders from persistent storage
  Future<void> _loadRootFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _rootFolders = prefs.getStringList(_rootFoldersKey) ?? [];
      print('Loaded ${_rootFolders.length} root folders');
    } catch (e) {
      print('Error loading root folders: $e');
      _rootFolders = [];
    }
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

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
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns for version 2
      await db.execute(
        'ALTER TABLE $tableMusic ADD COLUMN $columnWaveformData TEXT',
      );
      await db.execute(
        'ALTER TABLE $tableMusic ADD COLUMN $columnRating INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE $tableMusic ADD COLUMN $columnComment TEXT DEFAULT ""',
      );
      await db.execute(
        'ALTER TABLE $tableMusic ADD COLUMN $columnGeneralTags TEXT',
      );
    }
  }

  Future<int> addTrack(Track track) async {
    return await _database!.insert(tableMusic, track.toJson());
  }

  Future<int> updateTrack(Track track) async {
    return await _database!.update(
      tableMusic,
      track.toJson(),
      where: '$columnId = ?',
      whereArgs: [track.id],
    );
  }

  Future<int> deleteTrack(int id) async {
    return await _database!.delete(
      tableMusic,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  Future<List<Track>> getAllTracks() async {
    final List<Map<String, dynamic>> maps = await _database!.query(tableMusic);
    return List.generate(maps.length, (i) {
      return Track.fromJson(maps[i]);
    });
  }

  Future<List<Tag>> getAllTags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? tagsJsonString = prefs.getString(_generalTagsKey);

      if (tagsJsonString != null) {
        final List<dynamic> decodedList = jsonDecode(tagsJsonString);
        return decodedList.map((jsonItem) => Tag.fromJson(jsonItem)).toList();
      } else {
        // Return empty list if no tags are saved yet
        return [];
      }
    } catch (e) {
      print('Error loading general tags: $e');
      return []; // Return empty list on error
    }
  }

  Future<bool> _saveAllTags(List<Tag> tags) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Convert list of Tag objects to list of Maps, then encode to JSON string
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
    // Avoid adding duplicates (case-insensitive check)
    if (!currentTags.any(
      (tag) => tag.name.toLowerCase() == newTag.name.toLowerCase(),
    )) {
      currentTags.add(newTag);
      await _saveAllTags(currentTags);
      print('Added general tag: ${newTag.name}');
    } else {
      print('General tag "${newTag.name}" already exists.');
      // Optionally throw an error or return a status
    }
  }

  // Method to remove a tag by its name
  Future<void> removeTag(String tagName) async {
    final currentTags = await getAllTags();
    final originalLength = currentTags.length;
    currentTags.removeWhere((tag) => tag.name == tagName);

    // Save only if something was actually removed
    if (currentTags.length < originalLength) {
      await _saveAllTags(currentTags);
      print('Removed general tag: $tagName');

      // TODO: Remember to implement logic in the BLoC or here
      // to remove this tag from all tracks that use it in their 'generalTags' list.
      // Example (conceptual - might need adjustment):
      // final allTracks = await getAllTracks();
      // for (var track in allTracks) {
      //   if (track.generalTags.contains(tagName)) {
      //      await removeGeneralTag(track.id!, tagName); // Call existing method
      //   }
      // }
    } else {
      print('General tag "$tagName" not found for removal.');
    }
  }

  Future<void> updateTag(Tag updatedTag) async {
    final currentTags = await getAllTags();
    final index = currentTags.indexWhere((tag) => tag.name == updatedTag.name);

    if (index != -1) {
      currentTags[index] =
          updatedTag; // Replace the old tag with the updated one
      await _saveAllTags(currentTags);
      print('Updated general tag: ${updatedTag.name}');
    } else {
      print('General tag "${updatedTag.name}" not found for update.');
      // Optionally throw an error
    }
  }

  Future<List<Track>> searchTracks(String query) async {
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where:
          '$columnTitle LIKE ? OR $columnArtist LIKE ? OR $columnAlbum LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
    );
    return List.generate(maps.length, (i) {
      return Track.fromJson(maps[i]);
    });
  }

  Future<Track?> getTrack(int id) async {
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: '$columnId = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Track.fromJson(maps.first);
    }
    return null;
  }

  Future<Track?> getTrackByPath(String path) async {
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableMusic,
      where: '$columnPath = ?',
      whereArgs: [path],
    );

    if (maps.isNotEmpty) {
      return Track.fromJson(maps.first);
    }
    return null;
  }

  Future<void> addTagToTrack(int trackId, double position, String label) async {
    final track = await getTrack(trackId);
    if (track != null) {
      final tags = Map<String, dynamic>.from(track.tags);
      tags[position.toString()] = label;

      final updatedTrack = track.copyWith(tags: tags);
      await updateTrack(updatedTrack);
    }
  }

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
    final track = await getTrack(trackId);
    if (track != null) {
      final tags = List<String>.from(track.generalTags);
      if (!tags.contains(tag)) {
        tags.add(tag);
        final updatedTrack = track.copyWith(generalTags: tags);
        await updateTrack(updatedTrack);
      }
    }
  }

  Future<void> removeGeneralTag(int trackId, String tag) async {
    final track = await getTrack(trackId);
    if (track != null) {
      final tags = List<String>.from(track.generalTags);
      tags.remove(tag);
      final updatedTrack = track.copyWith(generalTags: tags);
      await updateTrack(updatedTrack);
    }
  }

  Future<void> importFromFile(String path) async {
    try {
      final file = File(path);
      final jsonString = await file.readAsString();
      final List<dynamic> jsonData = jsonDecode(jsonString);

      for (var trackJson in jsonData) {
        final track = Track.fromJson(trackJson);
        await addTrack(track);
      }
    } catch (e) {
      print('Error importing collection: $e');
      rethrow;
    }
  }

  Future<void> exportToFile(String path) async {
    try {
      final tracks = await getAllTracks();
      final jsonData = tracks.map((track) => track.toJson()).toList();
      final jsonString = jsonEncode(jsonData);

      final file = File(path);
      await file.writeAsString(jsonString);
    } catch (e) {
      print('Error exporting collection: $e');
      rethrow;
    }
  }

  // New method to check if waveform data already exists
  Future<bool> _hasWaveformData(String path) async {
    final track = await getTrackByPath(path);
    return track?.waveformData != null && track!.waveformData!.isNotEmpty;
  }

  // New method to load waveform data from AudioService with caching
  Future<List<double>?> _loadWaveformData(String source, bool isUrl) async {
    // Skip waveform extraction if we've already checked this file and found waveform data
    if (_checkedWaveforms.contains(source)) {
      print(
        '🔍 CollectionService: Skipping waveform extraction for already checked source: $source',
      );
      return null;
    }

    try {
      print(
        '🔍 CollectionService: Checking for cached waveform in AudioService',
      );

      // First try to get from cache without loading the audio
      // Use the public method instead of the private one
      final cachedWaveform = await _audioService.loadWaveformFromCache(source);
      if (cachedWaveform != null) {
        print('✅ CollectionService: Using cached waveform from AudioService');
        _checkedWaveforms.add(source);
        return cachedWaveform;
      }

      // We need to extract the waveform
      print(
        '🔍 CollectionService: No cached waveform found, extracting new waveform',
      );
      await _audioService.loadAudio(source, isUrl: isUrl);

      // Wait for waveform data to be generated
      List<double>? waveformData;
      await for (var data in _audioService.waveformStream.take(1)) {
        waveformData = data;
        break;
      }

      // Mark as checked
      _checkedWaveforms.add(source);

      print('✅ CollectionService: Waveform extraction complete');
      return waveformData;
    } catch (e) {
      print('❌ CollectionService: Error loading waveform data: $e');
      return null;
    }
  }

  // Updated method for adding local file with optimized waveform loading
  Future<Track> addLocalFile(String filePath) async {
    try {
      setLoading(true);

      // Check if track already exists in database
      final existingTrack = await getTrackByPath(filePath);
      if (existingTrack != null) {
        print('Track already exists in database: ${existingTrack.title}');

        // If track exists but has no waveform data, we'll try to add it
        if (existingTrack.waveformData == null ||
            existingTrack.waveformData!.isEmpty) {
          print('Existing track has no waveform data, trying to extract it');
          final waveformData = await _loadWaveformData(filePath, false);

          if (waveformData != null) {
            final updatedTrack = existingTrack.copyWith(
              waveformData: waveformData,
            );
            await updateTrack(updatedTrack);
            setLoading(false);
            return updatedTrack;
          }
        }

        setLoading(false);
        return existingTrack;
      }

      // In a real app, you'd extract metadata from the audio file
      // For simplicity, we'll just use the filename
      final filename = basename(filePath);
      final title = basenameWithoutExtension(filePath);

      // First check if there's waveform data in database
      print('🔍 CollectionService: Checking for waveform in database');
      final hasWaveform = await _hasWaveformData(filePath);

      List<double>? waveformData;

      if (!hasWaveform) {
        // No waveform in database, try to load/extract it
        print(
          '🔍 CollectionService: No waveform in database, checking cache or extracting',
        );
        waveformData = await _loadWaveformData(filePath, false);
      } else {
        print(
          '✅ CollectionService: Found waveform in database, skipping extraction',
        );
      }

      // Create the track with waveform data
      final track = Track(
        title: title,
        artist: 'Unknown',
        album: 'Unknown',
        path: filePath,
        isUrl: false,
        duration: 0, // This would be extracted from the file
        waveformData: waveformData,
        rating: 0,
        comment: '',
        generalTags: [],
      );

      final id = await addTrack(track);
      setLoading(false);
      return track.copyWith(id: id);
    } catch (e) {
      setLoading(false);
      print('Error adding local file: $e');
      rethrow;
    }
  }

  // Updated method for adding URL with optimized waveform loading
  Future<Track> addUrl(String url) async {
    try {
      setLoading(true);

      // Check if URL already exists in database
      final existingTrack = await getTrackByPath(url);
      if (existingTrack != null) {
        print('URL already exists in database: ${existingTrack.title}');

        // If track exists but has no waveform data, we'll try to add it
        if (existingTrack.waveformData == null ||
            existingTrack.waveformData!.isEmpty) {
          print(
            'Existing URL track has no waveform data, trying to extract it',
          );
          final waveformData = await _loadWaveformData(url, true);

          if (waveformData != null) {
            final updatedTrack = existingTrack.copyWith(
              waveformData: waveformData,
            );
            await updateTrack(updatedTrack);
            setLoading(false);
            return updatedTrack;
          }
        }

        setLoading(false);
        return existingTrack;
      }

      // First check if there's waveform data in database
      print('🔍 CollectionService: Checking for waveform in database for URL');
      final hasWaveform = await _hasWaveformData(url);

      List<double>? waveformData;

      if (!hasWaveform) {
        // No waveform in database, try to load/extract it
        print(
          '🔍 CollectionService: No waveform in database for URL, checking cache or extracting',
        );
        waveformData = await _loadWaveformData(url, true);
      } else {
        print(
          '✅ CollectionService: Found waveform in database for URL, skipping extraction',
        );
      }

      // For URLs, we might need to fetch some metadata
      // For simplicity, we'll just use the URL
      final uri = Uri.parse(url);
      final filename = basename(uri.path);

      final track = Track(
        title: filename,
        artist: 'Unknown',
        album: 'Unknown',
        path: url,
        isUrl: true,
        duration: 0, // This would be extracted from the stream
        waveformData: waveformData,
        rating: 0,
        comment: '',
        generalTags: [],
      );

      final id = await addTrack(track);
      setLoading(false);
      return track.copyWith(id: id);
    } catch (e) {
      setLoading(false);
      print('Error adding URL: $e');
      rethrow;
    }
  }

  // New method to update or create waveform for track
  Future<bool> updateWaveformForTrack(int trackId) async {
    try {
      setLoading(true);
      final track = await getTrack(trackId);

      if (track == null) {
        setLoading(false);
        return false;
      }

      // Clear existing AudioService cache for this track
      await _audioService.clearCacheForSource(track.path);

      // Remove from checked files set to force reload
      _checkedWaveforms.remove(track.path);

      // Force reload waveform
      final waveformData = await _loadWaveformData(track.path, track.isUrl);

      if (waveformData != null) {
        final updatedTrack = track.copyWith(waveformData: waveformData);
        await updateTrack(updatedTrack);
        setLoading(false);
        return true;
      }

      setLoading(false);
      return false;
    } catch (e) {
      setLoading(false);
      print('Error updating waveform: $e');
      return false;
    }
  }

  // Check if track needs waveform loading
  Future<bool> needsWaveformLoading(Track track) async {
    // If track has no waveform data, we need to load it
    if (track.waveformData == null || track.waveformData!.isEmpty) {
      // Check if it's in AudioService cache first
      final cachedWaveform = await _audioService.loadWaveformFromCache(
        track.path,
      );
      return cachedWaveform == null;
    }
    return false;
  }

  // Add multiple files with batch optimization
  Future<List<Track>> addMultipleFiles(List<String> filePaths) async {
    try {
      setLoading(true);
      final List<Track> addedTracks = [];

      // Process all files
      for (final filePath in filePaths) {
        try {
          final track = await addLocalFile(filePath);
          addedTracks.add(track);
        } catch (e) {
          print('Error adding file $filePath: $e');
          // Continue with next file
        }
      }

      setLoading(false);
      return addedTracks;
    } catch (e) {
      setLoading(false);
      print('Error adding multiple files: $e');
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _loadingController.close();
    await _audioService.dispose();
  }
}

class Tag {
  final String name;
  final int? colorValue; // Store color as int

  Tag({required this.name, this.colorValue});

  Map<String, dynamic> toJson() => {'name': name, 'colorValue': colorValue};

  factory Tag.fromJson(Map<String, dynamic> json) =>
      Tag(name: json['name'], colorValue: json['colorValue']);

  // Helper to get Flutter Color object
  Color? get color => colorValue == null ? null : Color(colorValue!);
}
