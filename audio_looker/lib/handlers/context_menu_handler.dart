// lib/handlers/context_menu_handler.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher
import 'package:path/path.dart' as path_lib; // Import for path manipulation

// Import BLoCs
import 'package:waux/blocs/track_management/track_data_bloc.dart';
import 'package:waux/blocs/audio_player/audio_player_bloc.dart';
import 'package:waux/blocs/playlist/playlist_bloc.dart';

// Import models
import 'package:waux/services/collection_service.dart';

/// Handles context menu creation and actions for tracks
class ContextMenuHandler {
  final BuildContext context;
  final Set<int> selectedTrackIds;
  final Function(int, bool) onSelectionChanged;
  final Function(Track, bool) onPlayTrack;

  ContextMenuHandler({
    required this.context,
    required this.selectedTrackIds,
    required this.onSelectionChanged,
    required this.onPlayTrack,
  });

  /// Shows the context menu at the tap position with options for the selected track
  void showContextMenu(BuildContext context, Offset tapPosition, Track track) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    // Ensure the right-clicked track is selected
    if (!selectedTrackIds.contains(track.id)) {
      // Update selection to just this track
      if (track.id != null) {
        onSelectionChanged(track.id!, true);
      }
    }

    showMenu(
      popUpAnimationStyle: AnimationStyle.noAnimation,
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(tapPosition.dx, tapPosition.dy, 0, 0), // Position at tap
        Offset.zero & overlay.size, // Overlay boundaries
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          value: 'play_now',
          enabled: selectedTrackIds.length == 1,
          child: const ListTile(
            leading: Icon(Icons.play_arrow),
            title: Text('Play Now'),
          ),
        ),
        // --- Reveal/Open Item ---
        PopupMenuItem(
          value: track.isUrl ? 'open_url' : 'reveal_file',
          child: ListTile(
            leading: Icon(
              track.isUrl ? Icons.open_in_browser : Icons.folder_open,
            ),
            title: Text(
              track.isUrl ? 'Open URL in Browser' : 'Reveal in Finder',
            ), // Adapt text for OS if needed
          ),
        ),
        // --- >>> NEW: Open File Item <<< ---
        // if (selectedTrackIds.length == 1 &&
        //     !track.isUrl) // Only show for single local files
        //   PopupMenuItem(
        //     value: 'open_file',
        //     child: const ListTile(
        //       leading: Icon(Icons.audiotrack_outlined), // Or Icons.open_in_new
        //       title: Text('Open File'),
        //     ),
        //   ),
        // --- >>> END NEW <<< ---
        // Use spread operator to add playlist items
        ...buildAddToPlaylistItems(context),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'edit',
          enabled: selectedTrackIds.length == 1,
          child: const ListTile(
            leading: Icon(Icons.edit_note),
            title: Text('Edit Details'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text(
              selectedTrackIds.length > 1
                  ? 'Delete ${selectedTrackIds.length} Items'
                  : 'Delete from Collection',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ),
      ],
    ).then((value) {
      // Handle menu selection
      _handleMenuSelection(value, track);
    });
  }

  /// Builds the "Add to playlist" submenu items
  List<PopupMenuEntry<dynamic>> buildAddToPlaylistItems(BuildContext context) {
    // ... (implementation remains the same) ...
    final playlistState = context.read<PlaylistBloc>().state;
    List<PopupMenuEntry<dynamic>> playlistItems = [];

    if (playlistState is PlaylistLoaded && playlistState.playlists.isNotEmpty) {
      // Add a header/divider for the playlist section
      playlistItems.add(const PopupMenuDivider());
      playlistItems.add(
        const PopupMenuItem<dynamic>(
          enabled: false, // Make it non-interactive
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8.0),
            leading: Icon(Icons.playlist_add, size: 18),
            title: Text(
              'Add to Playlist:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
      );

      // Add an item for each playlist
      playlistItems.addAll(
        playlistState.playlists.map((playlist) {
          return PopupMenuItem<dynamic>(
            // Return a map to identify the action and playlist ID
            value: {'action': 'add_to_playlist', 'playlist_id': playlist.id},
            child: Padding(
              // Indent playlist names slightly
              padding: const EdgeInsets.only(left: 24.0),
              child: Text(playlist.name),
            ),
          );
        }).toList(),
      );
    } else {
      // Optionally add a disabled item if no playlists exist
      playlistItems.add(const PopupMenuDivider());
      playlistItems.add(
        const PopupMenuItem<dynamic>(
          enabled: false,
          child: ListTile(
            leading: Icon(Icons.playlist_add, size: 18),
            title: Text('Add to Playlist: (None)'),
          ),
        ),
      );
    }

    return playlistItems;
  }

  /// Handle context menu selection
  void _handleMenuSelection(dynamic value, Track track) {
    if (value != null && value is Map && value['action'] == 'add_to_playlist') {
      _handleAddToPlaylist(value['playlist_id']);
    } else if (value == 'play_now' && selectedTrackIds.length == 1) {
      onPlayTrack(track, false);
    } else if (value == 'reveal_file' && !track.isUrl) {
      _revealFile(track.path);
    } else if (value == 'open_url' &&
        track.isUrl &&
        selectedTrackIds.length == 1) {
      _openUrl(track.path);
      // --- >>> NEW: Handle Open File <<< ---
    } else if (value == 'edit' && selectedTrackIds.length == 1) {
      _handleEditTrack(track);
    } else if (value == 'delete') {
      confirmAndDeleteSelected();
    }
  }

  /// Reveal File Method
  Future<void> _revealFile(String filePath) async {
    // ... (implementation remains the same) ...
    try {
      // Ensure it's an absolute path before proceeding
      if (!path_lib.isAbsolute(filePath)) {
        print("Error revealing file: Path is not absolute: $filePath");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Cannot reveal relative path: $filePath")),
        );
        return;
      }

      // Get the parent directory
      final String directoryPath = path_lib.dirname(filePath);
      final Uri directoryUri = Uri.file(directoryPath);

      if (await canLaunchUrl(directoryUri)) {
        await launchUrl(directoryUri);
      } else {
        throw Exception('Could not launch directory URI: $directoryUri');
      }
    } catch (e) {
      print("Error revealing file in Finder/Explorer: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Could not reveal file: $e")));
    }
  }

  /// Open URL Method
  Future<void> _openUrl(String url) async {
    // ... (implementation remains the same) ...
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        ); // Open in default browser
      } else {
        throw Exception('Could not launch URL: $url');
      }
    } catch (e) {
      print("Error opening URL: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Could not open URL: $e")));
    }
  }

  // --- >>> NEW: Open File Method <<< ---
  Future<void> _openFile(String filePath) async {
    try {
      // Ensure it's an absolute path before proceeding
      if (!path_lib.isAbsolute(filePath)) {
        print("Error opening file: Path is not absolute: $filePath");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Cannot open relative path: $filePath")),
        );
        return;
      }

      final Uri fileUri = Uri.file(filePath);

      if (await canLaunchUrl(fileUri)) {
        // LaunchMode.externalApplication might be needed on some platforms
        // to ensure it opens in the default app instead of trying within Flutter.
        // Let's try default first. Add mode if needed.
        await launchUrl(fileUri);
      } else {
        throw Exception('Could not launch file URI: $fileUri');
      }
    } catch (e) {
      print("Error opening file: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Could not open file: $e")));
    }
  }
  // --- >>> END NEW <<< ---

  /// Add selected tracks to a playlist
  void _handleAddToPlaylist(String playlistId) {
    // ... (implementation remains the same) ...
    final addedTrackIds = Set<int>.from(selectedTrackIds); // Copy selection
    final collectionState = context.read<TrackDataBloc>().state;
    final playlistBloc = context.read<PlaylistBloc>();

    if (collectionState is TrackDataLoaded) {
      int addedCount = 0;
      for (final trackId in addedTrackIds) {
        try {
          final trackToAdd = collectionState.tracks.firstWhere(
            (t) => t.id == trackId,
          );
          playlistBloc.add(
            AddTrackToPlaylist(
              playlistId: playlistId,
              trackPath: trackToAdd.path, // Pass the path from the track
            ),
          );
          addedCount++;
        } catch (e) {
          print("Couldn't find track $trackId to add to playlist $playlistId");
        }
      }
      if (addedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $addedCount track(s) to playlist.')),
        );
      }
    }
  }

  /// Handle edit track metadata
  void _handleEditTrack(Track track) {
    // ... (implementation remains the same) ...
    print("Edit action triggered for track: ${track.title}");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Edit action triggered (UI not implemented)'),
      ),
    );
  }

  /// Show confirmation dialog and delete selected tracks
  void confirmAndDeleteSelected() {
    // ... (implementation remains the same) ...
    if (selectedTrackIds.isEmpty) return;
    final count = selectedTrackIds.length;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text(
            'Are you sure you want to remove $count item(s) from your collection? This cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog first
                _performDelete();
              },
            ),
          ],
        );
      },
    );
  }

  /// Actually delete the selected tracks
  void _performDelete() {
    // ... (implementation remains the same) ...
    final collectionBloc = context.read<TrackDataBloc>();
    final audioPlayerBloc = context.read<AudioPlayerBloc>();
    final idsToDelete = List<int>.from(selectedTrackIds); // Copy IDs for safety

    // Check if we need to stop the player
    final selectedTrack = _getSelectedTrack();
    if (selectedTrack != null && idsToDelete.contains(selectedTrack.id)) {
      // Also check if the currently playing track in the player bloc matches
      final playerState = audioPlayerBloc.state;
      if (playerState is AudioPlayerLoaded &&
          playerState.currentSource == selectedTrack.path) {
        print("Stopping player because deleted track was active.");
        audioPlayerBloc.add(StopAudio());
      }
    }

    // Dispatch delete events
    for (final trackId in idsToDelete) {
      collectionBloc.add(RemoveTrack(trackId));
    }
  }

  /// Get the currently selected track (if single selection)
  Track? _getSelectedTrack() {
    // ... (implementation remains the same) ...
    if (selectedTrackIds.length != 1) return null;

    final trackDataState =
        context.read<TrackDataBloc>().state; // Or BlocProvider.of

    List<Track> tracks = []; // Default to empty list

    // Get tracks from the appropriate state
    if (trackDataState is TrackDataLoaded) {
      // If loaded, use the tracks from this state
      tracks = trackDataState.tracks;
    } else if (trackDataState is TrackDataLoading &&
        trackDataState.previousTracks != null) {
      // If loading, use the tracks from the *previous* loaded state
      tracks = trackDataState.previousTracks!;
    }

    if (tracks.isEmpty) return null;

    try {
      return tracks.firstWhere((t) => t.id == selectedTrackIds.first);
    } catch (e) {
      return null; // Not found
    }
  }
}
