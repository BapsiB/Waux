// lib/handlers/context_menu_handler.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path_lib;

// Import BLoCs
import '../blocs/track_management/track_data_bloc.dart';
import '../blocs/audio_player/audio_player_bloc.dart';
import '../blocs/playlist/playlist_bloc.dart';
import '../blocs/track_management/track_metadata_bloc.dart';
import '../blocs/track_management/global_tag_bloc.dart';

// Import models and custom menu widget
import '../services/collection_service.dart';
import '../widgets/custom_context_menu.dart';
import '../widgets/tag_editor_popup.dart';
// Import the (yet to be created) multi-edit dialog
// import '../widgets/multi_metadata_editor.dart'; // <-- Add this later

class ContextMenuHandler {
  final BuildContext context; // Context for BLoC access
  final Set<int> selectedTrackIds;
  final Function(int, bool) onSelectionChanged;
  // Modified: Let's use a callback for opening the editor
  final Function(Set<int> trackIds) onShowMultiEditDialog;
  final Function(Track, bool) onPlayTrack;

  OverlayEntry? _overlayEntry;

  ContextMenuHandler({
    required this.context,
    required this.selectedTrackIds,
    required this.onSelectionChanged,
    required this.onShowMultiEditDialog, // <-- ADDED callback
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

  void showContextMenu(
    BuildContext anchorContext,
    Offset tapPosition,
    Track track,
  ) {
    print("CustomContextMenuHandler: showContextMenu called.");
    dismiss();

    // Ensure the right-clicked track is part of the selection
    if (!selectedTrackIds.contains(track.id)) {
      // Select ONLY the clicked track if it wasn't part of the selection
      selectedTrackIds.clear();
      selectedTrackIds.add(track.id!);
      // Notify the parent about the selection change
      onSelectionChanged(track.id!, true);
    }

    final overlay = Overlay.of(anchorContext);
    final screenSize = MediaQuery.of(anchorContext).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: _calculateHorizontalPosition(tapPosition.dx, screenWidth),
          top: _calculateVerticalPosition(tapPosition.dy, screenHeight),
          child: CustomContextMenu(
            items: _buildContextMenuItems(track), // Build items dynamically
            onDismiss: dismiss,
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
    print("CustomContextMenuHandler: Inserted new menu overlay.");
  }

  // --- Action Handlers ---
  Future<void> _handleRevealFile(String filePath) async {
    // ... (implementation remains the same)
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
    // ... (implementation remains the same)
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

  void _handleAddToPlaylist(String playlistId) {
    // Removed 'track' parameter
    // Use the selectedTrackIds set directly
    final Set<int> idsToAdd = Set.from(selectedTrackIds);
    if (idsToAdd.isEmpty) {
      print("ContextMenuHandler: No tracks selected to add to playlist.");
      return;
    }

    final collectionBloc = BlocProvider.of<TrackDataBloc>(context);
    final playlistBloc = BlocProvider.of<PlaylistBloc>(context);
    final trackDataState = collectionBloc.state;

    // --- Get source tracks based on current state ---
    List<Track>? sourceTracks;
    if (trackDataState is TrackDataLoaded)
      sourceTracks = trackDataState.tracks;
    else if (trackDataState is TrackDataProcessingNeeded)
      sourceTracks = trackDataState.tracks;
    else if (trackDataState is TrackDataLoading &&
        trackDataState.previousTracks != null)
      sourceTracks = trackDataState.previousTracks;
    else if (trackDataState is TrackDataDeletingFolder &&
        trackDataState.previousTracks != null)
      sourceTracks = trackDataState.previousTracks;
    // Add other states if necessary

    if (sourceTracks != null) {
      int addedCount = 0;
      int skippedCount = 0;
      for (final trackId in idsToAdd) {
        try {
          // Find the track object using its ID
          final trackToAdd = sourceTracks.firstWhere((t) => t.id == trackId);
          playlistBloc.add(
            AddTrackToPlaylist(
              playlistId: playlistId,
              trackPath: trackToAdd.path, // Use the path from the found track
            ),
          );
          addedCount++;
        } catch (e) {
          skippedCount++;
          print(
            "ContextMenuHandler: Couldn't find track with ID $trackId to add to playlist. Skipping.",
          );
        }
      }
      if (addedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added $addedCount track(s) to playlist.' +
                  (skippedCount > 0 ? ' ($skippedCount skipped)' : ''),
            ),
          ),
        );
      } else if (skippedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find selected tracks to add.'),
          ),
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

  // REMOVED: _handleEditTrack is replaced by triggering the multi-edit dialog

  void confirmAndDeleteSelected() {
    // ... (implementation remains the same)
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
    // ... (implementation remains the same)
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

  // --- Menu Item Building ---
  List<CustomContextMenuItem> _buildContextMenuItems(Track rightClickedTrack) {
    final playlistState = BlocProvider.of<PlaylistBloc>(context).state;
    final bool isSingleSelection = selectedTrackIds.length == 1;
    // Determine if the specifically right-clicked track is the *only* selected track
    final bool isOnlyThisTrackSelected =
        isSingleSelection && selectedTrackIds.contains(rightClickedTrack.id);

    List<CustomContextMenuItem> buildPlaylistItems() {
      List<CustomContextMenuItem> items = [];
      if (playlistState is PlaylistLoaded &&
          playlistState.playlists.isNotEmpty) {
        items.add(
          const CustomContextMenuItem(
            label: 'Add Selection to Playlist:', // Clarify "Selection"
            enabled: false, // Header is not enabled
            icon: Icons.playlist_add,
          ),
        );
        items.addAll(
          playlistState.playlists.map((playlist) {
            return CustomContextMenuItem(
              label: '  ${playlist.name}',
              // Enabled only if there's a selection
              enabled: selectedTrackIds.isNotEmpty,
              onTap:
                  () => _handleAddToPlaylist(
                    playlist.id,
                  ), // Pass only playlist ID
            );
          }),
        );
      } else {
        items.add(
          const CustomContextMenuItem(
            label: 'Add Selection to Playlist:',
            enabled: false,
            icon: Icons.playlist_add,
          ),
        );
        items.add(
          const CustomContextMenuItem(
            label: '  (No playlists created)',
            enabled: false,
          ),
        );
      }
      return items;
    }

    return [
      CustomContextMenuItem(
        label: 'Play Now',
        icon: Icons.play_arrow,
        // Enabled only if exactly one track (the right-clicked one) is selected
        enabled: isOnlyThisTrackSelected,
        onTap: () => onPlayTrack(rightClickedTrack, false),
      ),
      // --- ADDED: Edit Metadata Item ---
      CustomContextMenuItem(
        label: 'Edit Metadata',
        icon: Icons.edit_note,
        // Enabled if one or more tracks are selected
        enabled: selectedTrackIds.isNotEmpty,
        onTap:
            () => onShowMultiEditDialog(
              selectedTrackIds,
            ), // Call the new callback
      ),
      // Add Edit Tags option
      CustomContextMenuItem(
        label: 'Edit Tags',
        icon: Icons.label,
        // Enabled if one or more tracks are selected
        enabled: selectedTrackIds.isNotEmpty,
        onTap: () {
          // Get the tracks from the TrackDataBloc state
          final trackDataState = context.read<TrackDataBloc>().state;
          List<Track> tracksToEdit = [];

          List<Track> sourceTracks = [];
          if (trackDataState is TrackDataLoaded) {
            sourceTracks = trackDataState.tracks;
          } else if (trackDataState is TrackDataLoading &&
              trackDataState.previousTracks != null) {
            sourceTracks = trackDataState.previousTracks!;
          } else if (trackDataState is TrackDataProcessingNeeded) {
            sourceTracks = trackDataState.tracks;
          } else if (trackDataState is TrackDataDeletingFolder &&
              trackDataState.previousTracks != null) {
            sourceTracks = trackDataState.previousTracks!;
          }

          if (sourceTracks.isNotEmpty) {
            for (int id in selectedTrackIds) {
              try {
                tracksToEdit.add(
                  sourceTracks.firstWhere((track) => track.id == id),
                );
              } catch (e) {
                print("Could not find track with ID $id for tag editing.");
              }
            }
          }

          if (tracksToEdit.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Could not load details for selected tracks."),
              ),
            );
            return;
          }

          // Show the TagEditorPopup
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) {
              return MultiBlocProvider(
                providers: [
                  BlocProvider.value(
                    value: BlocProvider.of<TrackMetadataBloc>(context),
                  ),
                  BlocProvider.value(
                    value: BlocProvider.of<GlobalTagBloc>(context),
                  ),
                ],
                child: TagEditorPopup(
                  trackIds: tracksToEdit.map((t) => t.id!).toList(),
                  trackTags: Map.fromEntries(
                    tracksToEdit.map((t) => MapEntry(t.id!, t.generalTags)),
                  ),
                ),
              );
            },
          );
        },
      ),
      // --- END ADDED ---
      CustomContextMenuItem(
        label:
            rightClickedTrack.isUrl
                ? 'Open URL in Browser'
                : 'Reveal in Finder',
        icon:
            rightClickedTrack.isUrl ? Icons.open_in_browser : Icons.folder_open,
        // This action usually applies to the right-clicked item, regardless of multi-selection
        enabled: true,
        onTap: () {
          if (rightClickedTrack.isUrl) {
            _handleOpenUrl(rightClickedTrack.path);
          } else {
            _handleRevealFile(rightClickedTrack.path);
          }
        },
      ),
      ...buildPlaylistItems(), // Add playlist items
      // REMOVED: Redundant 'Edit Details' - covered by 'Edit Metadata'
      // CustomContextMenuItem(
      //   label: 'Edit Details',
      //   icon: Icons.edit_note,
      //   enabled: isOnlyThisTrackSelected, // Only for single selection
      //   onTap: () => _handleEditTrack(rightClickedTrack),
      // ),
      const CustomContextMenuItem(
        label: '',
        enabled: false,
      ), // Divider visually
      CustomContextMenuItem(
        label:
            selectedTrackIds.length > 1
                ? 'Delete ${selectedTrackIds.length} Items'
                : 'Delete Item', // Label adjusts based on selection count
        icon: Icons.delete_outline,
        color: Colors.red,
        // Enabled if there's any selection
        enabled: selectedTrackIds.isNotEmpty,
        onTap: confirmAndDeleteSelected,
      ),
    ];
  }

  // Position calculation helpers remain the same
  double _calculateHorizontalPosition(double dx, double screenWidth) {
    // ... (implementation remains the same)
    const menuWidth = 250.0; // Adjusted estimate for potentially longer text
    if (dx + menuWidth > screenWidth) {
      return screenWidth - menuWidth - 10;
    }
    return dx.clamp(10.0, screenWidth - menuWidth - 10);
  }

  double _calculateVerticalPosition(double dy, double screenHeight) {
    // ... (implementation remains the same)
    const menuHeight = 280.0; // Adjusted estimate
    if (dy + menuHeight > screenHeight) {
      return screenHeight - menuHeight - 10;
    }
    return dy.clamp(10.0, screenHeight - menuHeight - 10);
  }
}
