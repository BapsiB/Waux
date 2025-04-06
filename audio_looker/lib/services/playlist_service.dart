// lib/services/playlist_service.dart

import '../models/playlist.dart';
// TODO: Import persistence library if needed (e.g., shared_preferences, sqflite)

/// Service responsible for managing playlist data (CRUD operations).
///
/// Currently uses an in-memory store. Replace with persistent storage
/// (e.g., SharedPreferences, database) for production use.
class PlaylistService {
  // In-memory storage for playlists. Replace with persistent storage later.
  final List<Playlist> _playlists = [];

  /// Loads all playlists.
  ///
  /// In a real application, this would load from persistent storage.
  Future<List<Playlist>> loadPlaylists() async {
    // Simulate loading delay
    await Future.delayed(const Duration(milliseconds: 100));
    // In a real app, load from SharedPreferences, database, etc.
    // Example:
    // final prefs = await SharedPreferences.getInstance();
    // final String? playlistsJson = prefs.getString('playlists');
    // if (playlistsJson != null) {
    //   final List<dynamic> decoded = jsonDecode(playlistsJson);
    //   _playlists = decoded.map((json) => Playlist.fromJson(json)).toList();
    // }
    print(
      "PlaylistService: Loaded ${_playlists.length} playlists (in-memory).",
    );
    return List.unmodifiable(_playlists); // Return a copy
  }

  /// Saves a new playlist or updates an existing one.
  ///
  /// In a real application, this would save to persistent storage.
  Future<void> savePlaylist(Playlist playlist) async {
    // Simulate saving delay
    await Future.delayed(const Duration(milliseconds: 50));
    final index = _playlists.indexWhere((p) => p.id == playlist.id);
    if (index != -1) {
      // Update existing playlist
      _playlists[index] = playlist;
      print("PlaylistService: Updated playlist '${playlist.name}'.");
    } else {
      // Add new playlist
      _playlists.add(playlist);
      print("PlaylistService: Created new playlist '${playlist.name}'.");
    }
    // In a real app, save the updated list to storage
    // Example:
    // final prefs = await SharedPreferences.getInstance();
    // final String playlistsJson = jsonEncode(_playlists.map((p) => p.toJson()).toList());
    // await prefs.setString('playlists', playlistsJson);
    await _persistPlaylists(); // Persist changes
  }

  /// Deletes a playlist by its ID.
  ///
  /// In a real application, this would delete from persistent storage.
  Future<void> deletePlaylist(String playlistId) async {
    // Simulate deleting delay
    await Future.delayed(const Duration(milliseconds: 50));
    final initialLength = _playlists.length;
    _playlists.removeWhere((p) => p.id == playlistId);
    if (_playlists.length < initialLength) {
      print("PlaylistService: Deleted playlist with ID '$playlistId'.");
    } else {
      print(
        "PlaylistService: Playlist with ID '$playlistId' not found for deletion.",
      );
    }
    // In a real app, save the updated list to storage
    await _persistPlaylists(); // Persist changes
  }

  /// Adds a track path to a specific playlist.
  Future<void> addTrackToPlaylist(String playlistId, String trackPath) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      if (!playlist.trackPaths.contains(trackPath)) {
        final updatedPaths = List<String>.from(playlist.trackPaths)
          ..add(trackPath);
        _playlists[index] = playlist.copyWith(trackPaths: updatedPaths);
        print(
          "PlaylistService: Added track '$trackPath' to playlist '${playlist.name}'.",
        );
        await _persistPlaylists(); // Persist changes
      } else {
        print(
          "PlaylistService: Track '$trackPath' already exists in playlist '${playlist.name}'.",
        );
      }
    } else {
      print(
        "PlaylistService: Playlist with ID '$playlistId' not found for adding track.",
      );
    }
  }

  /// Removes a track path from a specific playlist.
  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackPath,
  ) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      if (playlist.trackPaths.contains(trackPath)) {
        final updatedPaths = List<String>.from(playlist.trackPaths)
          ..remove(trackPath);
        _playlists[index] = playlist.copyWith(trackPaths: updatedPaths);
        print(
          "PlaylistService: Removed track '$trackPath' from playlist '${playlist.name}'.",
        );
        await _persistPlaylists(); // Persist changes
      } else {
        print(
          "PlaylistService: Track '$trackPath' not found in playlist '${playlist.name}'.",
        );
      }
    } else {
      print(
        "PlaylistService: Playlist with ID '$playlistId' not found for removing track.",
      );
    }
  }

  /// Renames a playlist.
  Future<void> renamePlaylist(String playlistId, String newName) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index] = _playlists[index].copyWith(name: newName);
      print(
        "PlaylistService: Renamed playlist ID '$playlistId' to '$newName'.",
      );
      await _persistPlaylists();
    } else {
      print(
        "PlaylistService: Playlist with ID '$playlistId' not found for renaming.",
      );
    }
  }

  /// Helper method to persist the current state of playlists.
  /// Replace with actual persistence logic (e.g., saving to SharedPreferences).
  Future<void> _persistPlaylists() async {
    // Simulate persistence delay
    await Future.delayed(const Duration(milliseconds: 20));
    // Example using SharedPreferences:
    // try {
    //   final prefs = await SharedPreferences.getInstance();
    //   final String playlistsJson = jsonEncode(_playlists.map((p) => p.toJson()).toList());
    //   await prefs.setString('playlists', playlistsJson);
    //   print("PlaylistService: Persisted ${_playlists.length} playlists.");
    // } catch (e) {
    //   print("PlaylistService: Error persisting playlists: $e");
    // }
    print(
      "PlaylistService: Persisted ${_playlists.length} playlists (in-memory simulation).",
    );
  }
}
