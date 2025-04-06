// lib/services/playlist_service.dart

import 'dart:convert'; // Required for jsonEncode/jsonDecode
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import '../models/playlist.dart';

/// Service responsible for managing playlist data (CRUD operations).
/// Uses SharedPreferences for persistence.
class PlaylistService {
  // Key for storing the playlist list in SharedPreferences
  static const String _playlistsStorageKey = 'playlists_data';

  // In-memory cache of playlists. Loaded from storage on startup.
  List<Playlist> _playlists = [];
  bool _isInitialized = false; // Flag to prevent multiple initial loads

  /// Ensures playlists are loaded from storage. Call before accessing playlists.
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await loadPlaylists();
      _isInitialized = true;
    }
  }

  /// Loads playlists from SharedPreferences.
  ///
  /// This is typically called once when the service/app starts.
  Future<List<Playlist>> loadPlaylists() async {
    // Simulate loading delay (optional)
    // await Future.delayed(const Duration(milliseconds: 100));

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? playlistsJson = prefs.getString(_playlistsStorageKey);

      if (playlistsJson != null) {
        final List<dynamic> decodedList = jsonDecode(playlistsJson);
        _playlists =
            decodedList
                .map(
                  (jsonItem) =>
                      Playlist.fromJson(jsonItem as Map<String, dynamic>),
                )
                .toList();
        print(
          "PlaylistService: Loaded ${_playlists.length} playlists from SharedPreferences.",
        );
      } else {
        _playlists = []; // Initialize empty if nothing is saved yet
        print(
          "PlaylistService: No playlists found in SharedPreferences, initializing empty list.",
        );
      }
    } catch (e) {
      print(
        "PlaylistService: Error loading playlists from SharedPreferences: $e",
      );
      _playlists = []; // Initialize empty on error
    }
    _isInitialized = true; // Mark as initialized even if loading failed
    return List.unmodifiable(_playlists); // Return a copy
  }

  /// Saves the current list of playlists to SharedPreferences.
  Future<void> _persistPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Convert the list of Playlist objects to a list of JSON maps
      final List<Map<String, dynamic>> playlistsJsonList =
          _playlists.map((p) => p.toJson()).toList();
      // Encode the list of maps into a single JSON string
      final String encodedData = jsonEncode(playlistsJsonList);
      // Save the JSON string
      await prefs.setString(_playlistsStorageKey, encodedData);
      print(
        "PlaylistService: Persisted ${_playlists.length} playlists to SharedPreferences.",
      );
    } catch (e) {
      print(
        "PlaylistService: Error persisting playlists to SharedPreferences: $e",
      );
    }
  }

  /// Gets all playlists (ensures they are loaded first).
  Future<List<Playlist>> getAllPlaylists() async {
    await _ensureInitialized();
    return List.unmodifiable(_playlists);
  }

  /// Saves a new playlist or updates an existing one, then persists.
  Future<void> savePlaylist(Playlist playlist) async {
    await _ensureInitialized();
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
    // Persist changes to storage
    await _persistPlaylists();
  }

  /// Deletes a playlist by its ID, then persists.
  Future<void> deletePlaylist(String playlistId) async {
    await _ensureInitialized();
    final initialLength = _playlists.length;
    _playlists.removeWhere((p) => p.id == playlistId);
    if (_playlists.length < initialLength) {
      print("PlaylistService: Deleted playlist with ID '$playlistId'.");
      // Persist changes to storage
      await _persistPlaylists();
    } else {
      print(
        "PlaylistService: Playlist with ID '$playlistId' not found for deletion.",
      );
    }
  }

  /// Adds a track path to a specific playlist, then persists.
  Future<void> addTrackToPlaylist(String playlistId, String trackPath) async {
    await _ensureInitialized();
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
        // Persist changes to storage
        await _persistPlaylists();
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

  /// Removes a track path from a specific playlist, then persists.
  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackPath,
  ) async {
    await _ensureInitialized();
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
        // Persist changes to storage
        await _persistPlaylists();
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

  /// Renames a playlist, then persists.
  Future<void> renamePlaylist(String playlistId, String newName) async {
    await _ensureInitialized();
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index] = _playlists[index].copyWith(name: newName);
      print(
        "PlaylistService: Renamed playlist ID '$playlistId' to '$newName'.",
      );
      // Persist changes to storage
      await _persistPlaylists();
    } else {
      print(
        "PlaylistService: Playlist with ID '$playlistId' not found for renaming.",
      );
    }
  }
}
