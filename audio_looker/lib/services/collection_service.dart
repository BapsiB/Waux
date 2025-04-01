import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
// import 'package:http/http.dart' as http;
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

  Future<Track> addLocalFile(String file) async {
    try {
      setLoading(true);

      // In a real app, you'd extract metadata from the audio file
      // For simplicity, we'll just use the filename
      final filename = basename(file);
      final title = basenameWithoutExtension(file);

      // Extract waveform data
      await _audioService.loadAudio(file, isUrl: false);

      // Wait for waveform data to be generated
      List<double>? waveformData;
      await for (var data in _audioService.waveformStream.take(1)) {
        waveformData = data;
        break;
      }

      // Create the track with waveform data
      final track = Track(
        title: title,
        artist: 'Unknown',
        album: 'Unknown',
        path: file,
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

  Future<Track> addUrl(String url) async {
    try {
      setLoading(true);

      // Extract waveform data
      await _audioService.loadAudio(url, isUrl: true);

      // Wait for waveform data to be generated
      List<double>? waveformData;
      await for (var data in _audioService.waveformStream.take(1)) {
        waveformData = data;
        break;
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

  Future<void> dispose() async {
    await _loadingController.close();
    await _audioService.dispose();
  }
}
