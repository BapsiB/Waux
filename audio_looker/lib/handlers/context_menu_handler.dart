// lib/handlers/context_menu_handler.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path_lib;

// Import BLoCs
import '../blocs/track_management/track_data_bloc.dart';
import '../blocs/audio_player/audio_player_bloc.dart';
import '../blocs/playlist/playlist_bloc.dart';

// Import models and custom menu widget
import '../services/collection_service.dart';
import '../widgets/custom_context_menu.dart';

class ContextMenuHandler {
  final BuildContext context; // Context for BLoC access
  final Set<int> selectedTrackIds;
  final Function(int, bool) onSelectionChanged;
  final Function(Track, bool) onPlayTrack;

  OverlayEntry? _overlayEntry;

  ContextMenuHandler({
    required this.context,
    required this.selectedTrackIds,
    required this.onSelectionChanged,
    required this.onPlayTrack,
  });

  bool get isMenuVisible => _overlayEntry != null;

  void dismiss() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      print("CustomContextMenuHandler: Dismissed menu.");
    }
  }

  /// Shows the context menu at the tap position. Dismisses any existing menu first.
  void showContextMenu(
    BuildContext anchorContext,
    Offset tapPosition,
    Track track,
  ) {
    print("CustomContextMenuHandler: showContextMenu called.");
    dismiss();

    if (!selectedTrackIds.contains(track.id)) {
      onSelectionChanged(track.id!, true);
    }

    final overlay = Overlay.of(anchorContext);
    // --- FIX: Get screen size *before* OverlayEntry builder ---
    final screenSize = MediaQuery.of(anchorContext).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    // --- END FIX ---

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        // Use ctx instead of context to avoid shadowing
        return Positioned(
          // --- FIX: Use pre-calculated screen dimensions ---
          left: _calculateHorizontalPosition(tapPosition.dx, screenWidth),
          top: _calculateVerticalPosition(tapPosition.dy, screenHeight),
          // --- END FIX ---
          child: CustomContextMenu(
            items: _buildContextMenuItems(track), // Build items dynamically
            onDismiss: dismiss, // Menu dismisses itself on item tap
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
    print("CustomContextMenuHandler: Inserted new menu overlay.");
  }

  // --- Action Handlers remain the same ---
  Future<void> _handleRevealFile(String filePath) async {
    try {
      if (!path_lib.isAbsolute(filePath)) {
        print("Error revealing file: Path is not absolute: $filePath");
        ScaffoldMessenger.of(context).showSnackBar(
          // Use handler's context
          SnackBar(content: Text("Cannot reveal relative path: $filePath")),
        );
        return;
      }
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

  Future<void> _handleOpenUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  void _handleAddToPlaylist(String playlistId, Track track) {
    final Set<int> idsToAdd = Set.from(selectedTrackIds);
    if (!idsToAdd.contains(track.id)) idsToAdd.add(track.id!);

    final collectionBloc = BlocProvider.of<TrackDataBloc>(context);
    final playlistBloc = BlocProvider.of<PlaylistBloc>(context);
    final trackDataState = collectionBloc.state;

    List<Track>? sourceTracks;
    if (trackDataState is TrackDataLoaded)
      sourceTracks = trackDataState.tracks;
    else if (trackDataState is TrackDataProcessingNeeded)
      sourceTracks = trackDataState.tracks;
    else if (trackDataState is TrackDataLoading &&
        trackDataState.previousTracks != null)
      sourceTracks = trackDataState.previousTracks;

    if (sourceTracks != null) {
      int addedCount = 0;
      for (final trackId in idsToAdd) {
        try {
          final trackToAdd = sourceTracks.firstWhere((t) => t.id == trackId);
          playlistBloc.add(
            AddTrackToPlaylist(
              playlistId: playlistId,
              trackPath: trackToAdd.path,
            ),
          );
          addedCount++;
        } catch (e) {
          print(
            "ContextMenuHandler: Couldn't find track $trackId to add to playlist",
          );
        }
      }
      if (addedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $addedCount track(s) to playlist.')),
        );
      }
    } else {
      print(
        "ContextMenuHandler: Could not get track list from state to add to playlist.",
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add tracks. Track data not ready.'),
        ),
      );
    }
  }

  void _handleEditTrack(Track track) {
    print(
      "ContextMenuHandler: Edit action triggered for track: ${track.title}",
    );
    // Use the onPlayTrack callback to signal HomeScreen to handle opening the player
    onPlayTrack(track, false);
  }

  void confirmAndDeleteSelected() {
    if (selectedTrackIds.isEmpty) return;
    final count = selectedTrackIds.length;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to remove $count item(s)?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _performDelete();
              },
            ),
          ],
        );
      },
    );
  }

  void _performDelete() {
    final collectionBloc = BlocProvider.of<TrackDataBloc>(context);
    final audioPlayerBloc = BlocProvider.of<AudioPlayerBloc>(context);
    final idsToDelete = List<int>.from(selectedTrackIds);

    Track? currentlyPlayingTrack;
    final playerState = audioPlayerBloc.state;
    if (playerState is AudioPlayerLoaded) {
      final trackDataState = collectionBloc.state;
      List<Track> currentTracks = [];
      if (trackDataState is TrackDataLoaded)
        currentTracks = trackDataState.tracks;
      else if (trackDataState is TrackDataProcessingNeeded)
        currentTracks = trackDataState.tracks;
      try {
        currentlyPlayingTrack = currentTracks.firstWhere(
          (t) => t.path == playerState.currentSource,
        );
      } catch (e) {
        /* not found */
      }
    }
    if (currentlyPlayingTrack != null &&
        idsToDelete.contains(currentlyPlayingTrack.id)) {
      audioPlayerBloc.add(StopAudio());
    }

    for (final trackId in idsToDelete) {
      collectionBloc.add(RemoveTrack(trackId));
    }
  }

  // --- Menu Item Building remains the same ---
  List<CustomContextMenuItem> _buildContextMenuItems(Track track) {
    final playlistState = BlocProvider.of<PlaylistBloc>(context).state;
    final bool isSingleSelection =
        selectedTrackIds.length == 1 && selectedTrackIds.contains(track.id);

    List<CustomContextMenuItem> buildPlaylistItems() {
      List<CustomContextMenuItem> items = [];
      if (playlistState is PlaylistLoaded &&
          playlistState.playlists.isNotEmpty) {
        items.add(
          const CustomContextMenuItem(
            label: 'Add to Playlist:',
            enabled: false,
            icon: Icons.playlist_add,
          ),
        );
        items.addAll(
          playlistState.playlists.map((playlist) {
            return CustomContextMenuItem(
              label: '  ${playlist.name}',
              onTap: () => _handleAddToPlaylist(playlist.id, track),
            );
          }),
        );
      } else {
        items.add(
          const CustomContextMenuItem(
            label: 'Add to Playlist: (None)',
            enabled: false,
            icon: Icons.playlist_add,
          ),
        );
      }
      return items;
    }

    return [
      CustomContextMenuItem(
        label: 'Play Now',
        icon: Icons.play_arrow,
        enabled: isSingleSelection,
        onTap: () => onPlayTrack(track, false),
      ),
      CustomContextMenuItem(
        label: track.isUrl ? 'Open URL in Browser' : 'Reveal in Finder',
        icon: track.isUrl ? Icons.open_in_browser : Icons.folder_open,
        onTap: () {
          if (track.isUrl) {
            _handleOpenUrl(track.path);
          } else {
            _handleRevealFile(track.path);
          }
        },
      ),
      ...buildPlaylistItems(),
      CustomContextMenuItem(
        label: 'Edit Details',
        icon: Icons.edit_note,
        enabled: isSingleSelection,
        onTap: () => _handleEditTrack(track),
      ),
      CustomContextMenuItem(
        label:
            selectedTrackIds.length > 1
                ? 'Delete ${selectedTrackIds.length} Items'
                : 'Delete from Collection',
        icon: Icons.delete_outline,
        color: Colors.red,
        onTap: confirmAndDeleteSelected,
      ),
    ];
  }

  // Position calculation helpers remain the same
  double _calculateHorizontalPosition(double dx, double screenWidth) {
    const menuWidth = 200.0; // Estimate
    if (dx + menuWidth > screenWidth) {
      return screenWidth - menuWidth - 10; // Adjust if overflows right
    }
    return dx.clamp(10.0, screenWidth - menuWidth - 10);
  }

  double _calculateVerticalPosition(double dy, double screenHeight) {
    const menuHeight = 250.0; // Estimate
    if (dy + menuHeight > screenHeight) {
      return screenHeight - menuHeight - 10; // Adjust if overflows bottom
    }
    return dy.clamp(10.0, screenHeight - menuHeight - 10);
  }
}
