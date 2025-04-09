// lib/handlers/context_menu_handler.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Import BLoCs
// import 'package:audio_looker/blocs/collection_management/collection_management_bloc.dart';
import 'package:audio_looker/blocs/track_management/track_management_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';
import 'package:audio_looker/blocs/playlist/playlist_bloc.dart';

// Import models
import 'package:audio_looker/services/collection_service.dart';

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
    } else if (value == 'edit' && selectedTrackIds.length == 1) {
      _handleEditTrack(track);
    } else if (value == 'delete') {
      confirmAndDeleteSelected();
    }
  }

  /// Add selected tracks to a playlist
  void _handleAddToPlaylist(String playlistId) {
    final addedTrackIds = Set<int>.from(selectedTrackIds); // Copy selection
    final collectionState = context.read<TrackManagementBloc>().state;
    final playlistBloc = context.read<PlaylistBloc>();

    if (collectionState is TrackManagementLoaded) {
      int addedCount = 0;
      for (final trackId in addedTrackIds) {
        try {
          final trackToAdd = collectionState.tracks.firstWhere(
            (t) => t.id == trackId,
          );
          playlistBloc.add(
            AddTrackToPlaylist(
              playlistId: playlistId,
              trackPath: trackToAdd.path,
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
    // Placeholder for edit functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Edit action triggered (UI not implemented)'),
      ),
    );
  }

  /// Show confirmation dialog and delete selected tracks
  void confirmAndDeleteSelected() {
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
    final collectionBloc = context.read<TrackManagementBloc>();
    final audioPlayerBloc = context.read<AudioPlayerBloc>();
    final idsToDelete = List<int>.from(selectedTrackIds); // Copy IDs for safety

    // Check if we need to stop the player
    final selectedTrack = _getSelectedTrack();
    if (selectedTrack != null && idsToDelete.contains(selectedTrack.id)) {
      audioPlayerBloc.add(StopAudio());
    }

    // Dispatch delete events
    for (final trackId in idsToDelete) {
      collectionBloc.add(RemoveTrack(trackId));
    }
  }

  /// Get the currently selected track (if single selection)
  Track? _getSelectedTrack() {
    if (selectedTrackIds.length != 1) return null;

    final state = context.read<TrackManagementBloc>().state;
    if (state is! TrackManagementLoaded) return null;

    try {
      return state.tracks.firstWhere((t) => t.id == selectedTrackIds.first);
    } catch (e) {
      return null;
    }
  }
}
