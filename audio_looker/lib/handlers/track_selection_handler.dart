// lib/handlers/track_selection_handler.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

// Import BLoCs
import '../blocs/track_management/track_data_bloc.dart'; // <<< CHANGED: Import new BLoC
import '../blocs/track_management/track_metadata_bloc.dart'; // <<< ADDED: Import new BLoC
import '../blocs/audio_player/audio_player_bloc.dart';

// Import models
import '../models/playlist.dart';
import '../services/collection_service.dart'; // For Track model

/// Handles track selection logic, sorting, and interaction with player/metadata BLoCs.
class TrackSelectionHandler {
  final BuildContext context;
  final Set<int> selectedTrackIds;
  final int? anchorTrackId;
  final Track?
  selectedTrackForPlayer; // The track currently loaded/selected in the player UI part
  final String sortColumnName;
  final DataGridSortDirection sortDirectionSf;
  final Playlist? currentlySelectedPlaylist; // Used for filtering

  TrackSelectionHandler({
    required this.context,
    required this.selectedTrackIds,
    this.anchorTrackId,
    this.selectedTrackForPlayer,
    required this.sortColumnName,
    required this.sortDirectionSf,
    this.currentlySelectedPlaylist,
  });

  /// Gets the list of tracks currently displayed, applying playlist and rating filters, and sorting.
  /// Reads data from TrackDataBloc.
  List<Track> getCurrentDisplayedTracks() {
    final trackDataState = context.read<TrackDataBloc>().state;
    List<Track> sourceTracks = [];
    int? minimumRating;

    // Get the list from the appropriate state (already sorted by the BLoC)
    if (trackDataState is TrackDataLoaded) {
      sourceTracks = trackDataState.tracks;
      minimumRating = trackDataState.minimumRating;
    } else if (trackDataState is TrackDataLoading &&
        trackDataState.previousTracks != null) {
      sourceTracks = trackDataState.previousTracks!;
      minimumRating = trackDataState.minimumRating;
    } else if (trackDataState is TrackDataProcessingNeeded) {
      sourceTracks = trackDataState.tracks;
      minimumRating = trackDataState.minimumRating;
    } else if (trackDataState is TrackDataDeletingFolder) {
      sourceTracks = trackDataState.previousTracks ?? [];
      minimumRating = trackDataState.minimumRating;
    }
    // Add other relevant states if they hold track data

    // Apply playlist filter
    List<Track> playlistFilteredTracks;
    if (currentlySelectedPlaylist != null) {
      final playlistTrackPaths = Set<String>.from(
        currentlySelectedPlaylist!.trackPaths,
      );
      playlistFilteredTracks =
          sourceTracks
              .where((track) => playlistTrackPaths.contains(track.path))
              .toList();
    } else {
      playlistFilteredTracks = sourceTracks;
    }

    // Apply rating filter
    List<Track> ratingFilteredTracks;
    if (minimumRating != null && minimumRating > 0) {
      ratingFilteredTracks =
          playlistFilteredTracks
              .where((track) => track.rating >= minimumRating!)
              .toList();
    } else {
      ratingFilteredTracks = playlistFilteredTracks;
    }

    // *** RETURN THE FILTERED LIST DIRECTLY - NO SORTING HERE ***
    return ratingFilteredTracks; //
  }

  /// Sorts a given list of tracks based on current sort column and direction.
  /// (This method remains the same internally)
  // List<Track> getSortedTracks(List<Track> tracks) {
  //   List<Track> sortedTracks = List.from(tracks);
  //   sortedTracks.sort((a, b) {
  //     int comparison = 0;
  //     switch (sortColumnName) {
  //       case 'title':
  //         comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  //         break;
  //       case 'artist':
  //         comparison = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
  //         break;
  //       case 'album':
  //         comparison = a.album.toLowerCase().compareTo(b.album.toLowerCase());
  //         break;
  //       case 'rating':
  //         comparison = a.rating.compareTo(b.rating);
  //         break;
  //       case 'tags':
  //         // Handle potential empty tags for sorting
  //         String aTag =
  //             a.generalTags.isNotEmpty
  //                 ? a.generalTags.join(',').toLowerCase()
  //                 : '\uffff'; // Place empty tags last
  //         String bTag =
  //             b.generalTags.isNotEmpty
  //                 ? b.generalTags.join(',').toLowerCase()
  //                 : '\uffff';
  //         comparison = aTag.compareTo(bTag);
  //         break;
  //       // Add cases for other sortable columns if needed
  //       case 'duration': // <<< ADDED Duration Sort Case
  //         comparison = a.duration.compareTo(b.duration);
  //         break;
  //     }
  //     // Secondary sort by title if primary columns are equal
  //     if (comparison == 0 && sortColumnName != 'title') {
  //       comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  //     }
  //     return sortDirectionSf == DataGridSortDirection.ascending
  //         ? comparison
  //         : -comparison;
  //   });
  //   return sortedTracks;
  // }

  /// Handles track selection changes in the UI (e.g., DataGrid).
  /// Calculates the new selection state based on modifiers (Shift, Ctrl/Meta).
  /// Calls the [onSelectionStateChanged] callback with the updated state.
  void handleSelectionChanged(
    int trackId,
    bool isSelected, {
    bool isShiftPressed = false,
    bool isCtrlPressed = false,
    required Function(
      Set<int> selectedIds,
      int? anchorId,
      Track? selectedForPlayer,
    )
    onSelectionStateChanged,
  }) {
    final Set<int> newSelectedIds = Set.from(selectedTrackIds);
    int? newAnchorId = anchorTrackId;

    // Use the current *displayed* tracks for shift-selection logic
    final List<Track> currentDisplayedTracks = getCurrentDisplayedTracks();

    // --- LOGGING START ---
    print("--- Selection Change ---");
    print(
      "Incoming: trackId=$trackId, isSelected=$isSelected, shift=$isShiftPressed, ctrl=$isCtrlPressed",
    );
    print(
      "Current State: anchorId=$anchorTrackId, selectedIds=$selectedTrackIds",
    );
    print("Displayed Tracks (Count: ${currentDisplayedTracks.length}):");
    // Log IDs and Titles for context, truncated if too long
    int logCount = 0;
    for (var track in currentDisplayedTracks) {
      print("  - ID: ${track.id}, Title: ${track.title}");
      logCount++;
      if (logCount > 20) {
        // Limit log output
        print("  ... (list truncated)");
        break;
      }
    }
    // --- LOGGING END ---

    if (isSelected) {
      if (isCtrlPressed) {
        // Add/remove single item without affecting others
        newSelectedIds.add(trackId);
        newAnchorId = trackId; // Set anchor to the last clicked item
      } else if (isShiftPressed && newAnchorId != null) {
        // Range selection
        final anchorIndex = currentDisplayedTracks.indexWhere(
          (t) => t.id == newAnchorId,
        );
        final clickedIndex = currentDisplayedTracks.indexWhere(
          (t) => t.id == trackId,
        );

        print(
          "Shift Selection: Anchor ID=$newAnchorId (Index: $anchorIndex), Clicked ID=$trackId (Index: $clickedIndex)",
        ); // Log indices

        if (anchorIndex != -1 && clickedIndex != -1) {
          final start = anchorIndex < clickedIndex ? anchorIndex : clickedIndex;
          final end = anchorIndex > clickedIndex ? anchorIndex : clickedIndex;
          print(
            "Shift Selection: Calculated Range [$start - $end]",
          ); // Log range
          // Add the range to the *existing* selection if Ctrl/Meta is also held
          // Otherwise, clear the selection first. For simplicity, let's assume Shift clears first.
          // TODO: Refine this based on standard platform behavior if needed (Shift+Ctrl)
          newSelectedIds.clear();
          for (int i = start; i <= end; i++) {
            if (i >= 0 &&
                i < currentDisplayedTracks.length &&
                currentDisplayedTracks[i].id != null) {
              newSelectedIds.add(currentDisplayedTracks[i].id!);
            }
          }
          // Anchor remains the same for subsequent shift clicks
        } else {
          // Anchor not found or clicked item not found in current view
          print(
            "Shift Selection: Anchor or Clicked item not found in displayed list. Selecting only clicked.",
          );
          newSelectedIds.clear();
          newSelectedIds.add(trackId);
          newAnchorId = trackId;
        }
      } else {
        // Single click without modifiers
        newSelectedIds.clear();
        newSelectedIds.add(trackId);
        newAnchorId = trackId;
      }
    } else {
      // Deselecting
      if (isCtrlPressed) {
        // Remove single item
        newSelectedIds.remove(trackId);
        // If the deselected item was the anchor, clear the anchor
        if (newAnchorId == trackId)
          newAnchorId = newSelectedIds.isNotEmpty ? newSelectedIds.last : null;
      } else {
        // Simple deselection (e.g., clicking already selected item without modifier)
        // This case might be handled by the DataGrid itself depending on selection mode.
        // If called, assume it means deselecting this specific item.
        newSelectedIds.remove(trackId);
        if (newAnchorId == trackId)
          newAnchorId = newSelectedIds.isNotEmpty ? newSelectedIds.last : null;
        // If deselecting the only selected item, clear anchor
        if (newSelectedIds.isEmpty) newAnchorId = null;
      }
    }

    // Determine the track to be potentially loaded in the player
    Track? newSelectedTrackForPlayer;
    if (newSelectedIds.length == 1) {
      final newSelectedId = newSelectedIds.first;
      // Get the track data from the currently displayed list to avoid extra lookups
      try {
        newSelectedTrackForPlayer = currentDisplayedTracks.firstWhere(
          (t) => t.id == newSelectedId,
        );
      } catch (e) {
        // Fallback: try getting from the BLoC state directly if not in displayed list (shouldn't happen often)
        newSelectedTrackForPlayer = getTrackByIdFromBlocState(newSelectedId);
        print(
          "Warning: Selected track $newSelectedId not found in displayed list, using fallback lookup.",
        );
      }
    }

    // --- LOGGING START ---
    print(
      "Resulting State: newAnchorId=$newAnchorId, newSelectedIds=$newSelectedIds",
    );
    print("--- End Selection Change ---");
    // --- LOGGING END ---

    // Call the callback provided by HomeScreen to update its state
    onSelectionStateChanged(
      newSelectedIds,
      newAnchorId,
      newSelectedTrackForPlayer,
    );
  }

  /// Gets a track by its ID directly from the current TrackDataBloc state.
  /// Used as a fallback or for direct lookups.
  Track? getTrackByIdFromBlocState(int id) {
    // <<< CHANGED: Read state from TrackDataBloc >>>
    final trackDataState = context.read<TrackDataBloc>().state;
    List<Track> sourceList = [];

    if (trackDataState is TrackDataLoaded) {
      sourceList = trackDataState.tracks;
    } else if (trackDataState is TrackDataLoading &&
        trackDataState.previousTracks != null) {
      sourceList = trackDataState.previousTracks!;
    }
    // Add other states if needed

    try {
      // Search within the sourceList obtained from the BLoC state
      return sourceList.firstWhere((t) => t.id == id);
    } catch (e) {
      return null; // Not found
    }
  }

  /// Selects a track to be loaded into the player UI, dispatches LoadAudio to AudioPlayerBloc.
  /// Does not automatically play.
  void selectTrackForPlayer(Track track) {
    print("Selecting track for player: ${track.title}");
    final bloc = context.read<AudioPlayerBloc>();
    final currentBlocState = bloc.state;
    bool needsLoad = true;

    // Check if the player already has this track loaded
    if (currentBlocState is AudioPlayerLoaded &&
        currentBlocState.currentSource == track.path) {
      needsLoad = false;
    }

    if (needsLoad) {
      bloc.add(LoadAudio(track: track));
    } else {
      print("Track already loaded in player.");
      // Optionally seek to beginning if desired when re-selecting an already loaded track
      // bloc.add(const SeekAudio(position: Duration.zero));
    }
  }

  /// Selects a track, loads it via AudioPlayerBloc, and requests playback.
  void selectAndPlayTrack(Track track, {bool togglePlay = false}) {
    print("Selecting and playing track: ${track.title}");
    final bloc = context.read<AudioPlayerBloc>();
    final currentBlocState = bloc.state;
    bool needsLoad = true;

    if (currentBlocState is AudioPlayerLoaded &&
        currentBlocState.currentSource == track.path) {
      needsLoad = false;
    }

    if (needsLoad) {
      // Dispatch LoadAudio with playWhenReady set to true
      bloc.add(
        LoadAudio(
          track: track,
          playWhenReady: true, // Tell the BLoC to play after loading
        ),
      );
    } else {
      // Track is already loaded
      if (togglePlay && currentBlocState is AudioPlayerLoaded) {
        // If togglePlay is true, toggle the current state
        if (currentBlocState.isPlaying) {
          bloc.add(PauseAudio());
        } else {
          // Handle playing from end
          if (currentBlocState.position >= currentBlocState.duration &&
              currentBlocState.duration > Duration.zero) {
            bloc.add(const SeekAudio(position: Duration.zero));
            // Add small delay before playing after seek
            Future.delayed(
              const Duration(milliseconds: 50),
              () => bloc.add(PlayAudio()),
            );
          } else {
            bloc.add(PlayAudio());
          }
        }
      } else {
        // If togglePlay is false, just ensure it plays
        if (currentBlocState is AudioPlayerLoaded &&
            currentBlocState.position >= currentBlocState.duration &&
            currentBlocState.duration > Duration.zero) {
          bloc.add(const SeekAudio(position: Duration.zero));
          // Add small delay before playing after seek
          Future.delayed(
            const Duration(milliseconds: 50),
            () => bloc.add(PlayAudio()),
          );
        } else {
          bloc.add(PlayAudio());
        }
      }
    }
  }

  /// Selects a track and ensures it's loaded in the player (via AudioPlayerBloc), but doesn't play.
  /// Typically used when opening the player for editing metadata.
  void selectAndOpenPlayer(Track track) {
    print("Selecting and opening player for track: ${track.title}");
    final bloc = context.read<AudioPlayerBloc>();
    final currentBlocState = bloc.state;
    bool needsLoad = true;

    if (currentBlocState is AudioPlayerLoaded &&
        currentBlocState.currentSource == track.path) {
      needsLoad = false;
    }

    if (needsLoad) {
      // Load without requesting play
      bloc.add(LoadAudio(track: track, playWhenReady: false));
    } else {
      print("Track already loaded, not reloading for opening player.");
      // Ensure player is paused if it was playing something else? Optional.
      // if (currentBlocState is AudioPlayerLoaded && currentBlocState.isPlaying) {
      //    bloc.add(PauseAudio());
      // }
    }
  }

  /// Handles rating changes triggered from the UI (e.g., RatingCellWidget).
  /// Dispatches the update event to TrackMetadataBloc.
  void handleRatingChanged(int trackId, int newRating) {
    print("Rating changed in table: Track $trackId -> $newRating stars");
    // <<< CHANGED: Dispatch event to TrackMetadataBloc >>>
    context.read<TrackMetadataBloc>().add(
      UpdateTrackRating(trackId, newRating),
    );
    // Note: The UI (e.g., HomeScreen) should listen to TrackMetadataBloc's
    // success state and trigger a reload in TrackDataBloc if needed.
  }
}
