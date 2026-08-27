import 'dart:async';
import 'package:sqflite/sqflite.dart'; // Required for DB operations
import 'package:path/path.dart' as pathLib; // Use alias
import 'package:uuid/uuid.dart'; // For generating playlist IDs

// Import models and the CollectionService
import '../models/playlist.dart';
import 'collection_service.dart'; // To get active DB and collection info

/// Service responsible for managing playlist data within the active collection's database.
class PlaylistService {
  // --- Database Table/Column Constants ---
  static const String tablePlaylists = 'playlists';
  static const String tablePlaylistTracks = 'playlist_tracks';
  static const String columnPlaylistId = 'id';
  static const String columnPlaylistName = 'name';
  static const String columnPlaylistTracksPlaylistId = 'playlist_id';
  static const String columnPlaylistTracksTrackPath = 'track_path';
  static const String columnPlaylistTracksSortOrder = 'sort_order';

  /// Loads playlists for the currently active collection.
  /// Requires the [collectionService] to access the active database and collection info.
  Future<List<Playlist>> loadPlaylists(
    CollectionService collectionService,
  ) async {
    final db = collectionService.getActiveDatabase();
    final activeCollection = collectionService.getActiveCollection();
    if (db == null || activeCollection == null) {
      print("PlaylistService: Cannot load playlists, no active collection/DB.");
      return [];
    }

    try {
      final List<Map<String, dynamic>> playlistMaps = await db.query(
        tablePlaylists,
      );
      final List<Playlist> playlists = [];

      for (var map in playlistMaps) {
        final playlistId = map[columnPlaylistId] as String;
        final playlistName = map[columnPlaylistName] as String;

        // Fetch tracks for this playlist
        final List<Map<String, dynamic>> trackMaps = await db.query(
          tablePlaylistTracks,
          where: '$columnPlaylistTracksPlaylistId = ?',
          whereArgs: [playlistId],
          orderBy:
              '$columnPlaylistTracksSortOrder ASC', // Optional: Load in order
        );

        // Extract and resolve paths
        final List<String> trackPaths =
            trackMaps.map((trackMap) {
              final storedPath =
                  trackMap[columnPlaylistTracksTrackPath] as String;
              // Resolve relative paths for shared collections
              if (activeCollection.type == CollectionType.shared &&
                  activeCollection.rootPath != null &&
                  !Uri.tryParse(storedPath)!.isAbsolute) {
                // Check if not already absolute/URL
                try {
                  return pathLib.join(activeCollection.rootPath!, storedPath);
                } catch (e) {
                  print(
                    "Error resolving playlist track path $storedPath with root ${activeCollection.rootPath}: $e",
                  );
                  return storedPath; // Return unresolved path on error
                }
              }
              return storedPath; // Return absolute path for local or URLs
            }).toList();

        playlists.add(
          Playlist(id: playlistId, name: playlistName, trackPaths: trackPaths),
        );
      }
      print(
        "PlaylistService: Loaded ${playlists.length} playlists for collection '${activeCollection.name}'.",
      );
      return playlists;
    } catch (e, stackTrace) {
      print("PlaylistService: Error loading playlists: $e\n$stackTrace");
      return []; // Return empty list on error
    }
  }

  /// Creates a new playlist in the active collection's database.
  Future<Playlist?> createPlaylist(
    CollectionService collectionService,
    String name,
  ) async {
    final db = collectionService.getActiveDatabase();
    final activeCollection = collectionService.getActiveCollection();
    if (db == null || activeCollection == null) {
      print(
        "PlaylistService: Cannot create playlist, no active collection/DB.",
      );
      return null;
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      print("PlaylistService: Playlist name cannot be empty.");
      return null; // Or throw
    }

    final newPlaylist = Playlist(name: trimmedName); // Generates ID

    try {
      await db.insert(tablePlaylists, {
        columnPlaylistId: newPlaylist.id,
        columnPlaylistName: newPlaylist.name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      print(
        "PlaylistService: Created playlist '${newPlaylist.name}' in collection '${activeCollection.name}'.",
      );
      return newPlaylist;
    } catch (e, stackTrace) {
      print("PlaylistService: Error creating playlist: $e\n$stackTrace");
      return null;
    }
  }

  /// Deletes a playlist from the active collection's database.
  Future<void> deletePlaylist(
    CollectionService collectionService,
    String playlistId,
  ) async {
    final db = collectionService.getActiveDatabase();
    final activeCollection = collectionService.getActiveCollection();
    if (db == null || activeCollection == null) {
      print(
        "PlaylistService: Cannot delete playlist, no active collection/DB.",
      );
      return;
    }

    try {
      // Foreign key constraint with ON DELETE CASCADE should handle deleting tracks
      final count = await db.delete(
        tablePlaylists,
        where: '$columnPlaylistId = ?',
        whereArgs: [playlistId],
      );
      if (count > 0) {
        print(
          "PlaylistService: Deleted playlist ID '$playlistId' from collection '${activeCollection.name}'.",
        );
      } else {
        print(
          "PlaylistService: Playlist ID '$playlistId' not found for deletion.",
        );
      }
    } catch (e, stackTrace) {
      print("PlaylistService: Error deleting playlist: $e\n$stackTrace");
    }
  }

  /// Adds a track to a specific playlist in the active collection's database.
  /// Expects [absoluteTrackPath] and converts it to relative if needed.
  Future<void> addTrackToPlaylist(
    CollectionService collectionService,
    String playlistId,
    String absoluteTrackPath,
  ) async {
    final db = collectionService.getActiveDatabase();
    final activeCollection = collectionService.getActiveCollection();
    if (db == null || activeCollection == null) {
      print("PlaylistService: Cannot add track, no active collection/DB.");
      return;
    }

    String pathToAdd = absoluteTrackPath;
    // Convert to relative path if it's a shared collection and the path is within its root
    if (activeCollection.type == CollectionType.shared &&
        activeCollection.rootPath != null &&
        !Uri.tryParse(absoluteTrackPath)!.isAbsolute) {
      // Don't make URLs relative
      try {
        if (pathLib.isAbsolute(absoluteTrackPath) &&
            pathLib.isWithin(activeCollection.rootPath!, absoluteTrackPath)) {
          pathToAdd = pathLib.relative(
            absoluteTrackPath,
            from: activeCollection.rootPath!,
          );
        } else {
          print(
            "Warning: Track path '$absoluteTrackPath' is not within shared root '${activeCollection.rootPath}'. Storing absolute path in playlist.",
          );
          pathToAdd = absoluteTrackPath; // Fallback to absolute
        }
      } catch (e) {
        print(
          "Warning: Could not make track path relative. Storing absolute path in playlist. Error: $e",
        );
        pathToAdd = absoluteTrackPath; // Fallback
      }
    }

    try {
      // Check if track already exists in this playlist to avoid duplicates
      final existing = await db.query(
        tablePlaylistTracks,
        where:
            '$columnPlaylistTracksPlaylistId = ? AND $columnPlaylistTracksTrackPath = ?',
        whereArgs: [playlistId, pathToAdd],
        limit: 1,
      );

      if (existing.isEmpty) {
        // TODO: Determine sort order (e.g., count existing tracks)
        final countResult = await db.rawQuery(
          'SELECT COUNT(*) as count FROM $tablePlaylistTracks WHERE $columnPlaylistTracksPlaylistId = ?',
          [playlistId],
        );
        final sortOrder = Sqflite.firstIntValue(countResult) ?? 0;

        await db.insert(tablePlaylistTracks, {
          columnPlaylistTracksPlaylistId: playlistId,
          columnPlaylistTracksTrackPath: pathToAdd,
          columnPlaylistTracksSortOrder: sortOrder,
        });
        print(
          "PlaylistService: Added track '$pathToAdd' to playlist '$playlistId'.",
        );
      } else {
        print(
          "PlaylistService: Track '$pathToAdd' already in playlist '$playlistId'.",
        );
      }
    } catch (e, stackTrace) {
      print("PlaylistService: Error adding track to playlist: $e\n$stackTrace");
    }
  }

  /// Removes a track from a specific playlist in the active collection's database.
  /// Expects [absoluteTrackPath] and converts it to relative if needed.
  Future<void> removeTrackFromPlaylist(
    CollectionService collectionService,
    String playlistId,
    String absoluteTrackPath,
  ) async {
    final db = collectionService.getActiveDatabase();
    final activeCollection = collectionService.getActiveCollection();
    if (db == null || activeCollection == null) {
      print("PlaylistService: Cannot remove track, no active collection/DB.");
      return;
    }

    String pathToRemove = absoluteTrackPath;
    // Convert to relative path if it's a shared collection
    if (activeCollection.type == CollectionType.shared &&
        activeCollection.rootPath != null &&
        !Uri.tryParse(absoluteTrackPath)!.isAbsolute) {
      try {
        if (pathLib.isAbsolute(absoluteTrackPath) &&
            pathLib.isWithin(activeCollection.rootPath!, absoluteTrackPath)) {
          pathToRemove = pathLib.relative(
            absoluteTrackPath,
            from: activeCollection.rootPath!,
          );
        } else {
          pathToRemove = absoluteTrackPath;
        }
      } catch (e) {
        pathToRemove = absoluteTrackPath;
      }
    }

    try {
      final count = await db.delete(
        tablePlaylistTracks,
        where:
            '$columnPlaylistTracksPlaylistId = ? AND $columnPlaylistTracksTrackPath = ?',
        whereArgs: [playlistId, pathToRemove],
      );
      if (count > 0) {
        print(
          "PlaylistService: Removed track '$pathToRemove' from playlist '$playlistId'.",
        );
        // TODO: Optionally re-order remaining tracks?
      } else {
        print(
          "PlaylistService: Track '$pathToRemove' not found in playlist '$playlistId'.",
        );
      }
    } catch (e, stackTrace) {
      print(
        "PlaylistService: Error removing track from playlist: $e\n$stackTrace",
      );
    }
  }

  /// Renames a playlist in the active collection's database.
  Future<void> renamePlaylist(
    CollectionService collectionService,
    String playlistId,
    String newName,
  ) async {
    final db = collectionService.getActiveDatabase();
    final activeCollection = collectionService.getActiveCollection();
    if (db == null || activeCollection == null) {
      print(
        "PlaylistService: Cannot rename playlist, no active collection/DB.",
      );
      return;
    }
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) {
      print("PlaylistService: Playlist name cannot be empty.");
      return; // Or throw
    }

    try {
      final count = await db.update(
        tablePlaylists,
        {columnPlaylistName: trimmedName},
        where: '$columnPlaylistId = ?',
        whereArgs: [playlistId],
      );
      if (count > 0) {
        print(
          "PlaylistService: Renamed playlist ID '$playlistId' to '$trimmedName'.",
        );
      } else {
        print(
          "PlaylistService: Playlist ID '$playlistId' not found for renaming.",
        );
      }
    } catch (e, stackTrace) {
      print("PlaylistService: Error renaming playlist: $e\n$stackTrace");
    }
  }

  // Add other methods as needed (e.g., reorder tracks in playlist)
}
