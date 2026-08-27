// lib/models/playlist.dart

import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// Represents a single playlist containing a list of track paths.
class Playlist extends Equatable {
  /// Unique identifier for the playlist.
  final String id;

  /// User-defined name for the playlist.
  final String name;

  /// List of track file paths included in the playlist.
  final List<String> trackPaths;

  /// Creates a new Playlist instance.
  ///
  /// If [id] is not provided, a new unique ID is generated.
  Playlist({String? id, required this.name, this.trackPaths = const []})
    : id = id ?? const Uuid().v4(); // Generate unique ID if not provided

  /// Creates a copy of the playlist with optional updated fields.
  Playlist copyWith({String? id, String? name, List<String>? trackPaths}) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackPaths: trackPaths ?? this.trackPaths,
    );
  }

  @override
  List<Object?> get props => [id, name, trackPaths];

  @override
  bool get stringify => true;

  // --- Serialization (Optional - for persistence) ---

  /// Creates a Playlist from a JSON map.
  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      trackPaths: List<String>.from(json['trackPaths'] as List<dynamic>),
    );
  }

  /// Converts the Playlist to a JSON map.
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'trackPaths': trackPaths};
  }
}
