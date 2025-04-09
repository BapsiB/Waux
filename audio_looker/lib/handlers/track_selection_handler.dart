// lib/handlers/track_selection_handler.dart

import 'package:audio_looker/blocs/track_management/track_management_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

// Import BLoCs
// import 'package:audio_looker/blocs/collection_management/collection_management_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';

// Import models
import 'package:audio_looker/models/playlist.dart';
import 'package:audio_looker/services/collection_service.dart';

/// Handles track selection and sorting functions
class TrackSelectionHandler {
  final BuildContext context;
  final Set<int> selectedTrackIds;
  final int? anchorTrackId;
  final Track? selectedTrackForPlayer;
  final String? currentlyLoadedPathInPlayer;
  final String sortColumnName;
  final DataGridSortDirection sortDirectionSf;
  final Playlist? currentlySelectedPlaylist;

  TrackSelectionHandler({
    required this.context,
    required this.selectedTrackIds,
    this.anchorTrackId,
    this.selectedTrackForPlayer,
    this.currentlyLoadedPathInPlayer,
    required this.sortColumnName,
    required this.sortDirectionSf,
    this.currentlySelectedPlaylist,
  });

  List<Track> getCurrentDisplayedTracks() {
    final collectionState = context.read<TrackManagementBloc>().state;
    List<Track> sourceTracks = [];
    int? minimumRating; // Variable to hold the filter value

    // Get tracks and minimumRating from the current state
    if (collectionState is TrackManagementLoaded) {
      sourceTracks = collectionState.tracks;
      minimumRating = collectionState.minimumRating; // <<< Get rating
    } else if (collectionState is TrackManagementLoading &&
        collectionState.currentTracks != null) {
      sourceTracks = collectionState.currentTracks!;
      minimumRating = collectionState.currentMinimumRating; // <<< Get rating
    } else if (collectionState is TrackManagementError &&
        collectionState.tracks != null) {
      sourceTracks = collectionState.tracks!;
      // Assume no filter on error, or get from state if added there
    } else if (collectionState is TrackManagementProcessingWaveforms) {
      sourceTracks = collectionState.tracks;
      minimumRating = collectionState.minimumRating; // <<< Get rating
    }

    List<Track> ratingFilteredTracks;
    if (minimumRating != null && minimumRating > 0) {
      // Filter tracks where rating is greater than or equal to the minimum
      ratingFilteredTracks =
          sourceTracks
              .where((track) => track.rating >= minimumRating!)
              .toList();
      print(
        "Applying rating filter: >= $minimumRating stars. Found ${ratingFilteredTracks.length} tracks.",
      );
    } else {
      ratingFilteredTracks = sourceTracks; // No filter or 0 stars selected
      print("No rating filter applied (minimumRating is $minimumRating).");
    }

    // Apply playlist filter AFTER rating filter
    List<Track> playlistFilteredTracks;
    if (currentlySelectedPlaylist != null) {
      final playlistTrackPaths = Set<String>.from(
        currentlySelectedPlaylist!.trackPaths,
      );
      // Filter the RATING-FILTERED tracks
      playlistFilteredTracks =
          ratingFilteredTracks
              .where((track) => playlistTrackPaths.contains(track.path))
              .toList();
    } else {
      // If no playlist selected, use the rating-filtered list
      playlistFilteredTracks = ratingFilteredTracks;
    }

    // Sort the final filtered list
    return getSortedTracks(playlistFilteredTracks);
  }

  /// Sorts tracks based on current sort column and direction
  List<Track> getSortedTracks(List<Track> tracks) {
    List<Track> sortedTracks = List.from(tracks);
    sortedTracks.sort((a, b) {
      int comparison = 0;
      switch (sortColumnName) {
        case 'title':
          comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case 'artist':
          comparison = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          break;
        case 'album':
          comparison = a.album.toLowerCase().compareTo(b.album.toLowerCase());
          break;
        case 'rating':
          comparison = a.rating.compareTo(b.rating);
          break;
        case 'tags':
          String aTag =
              a.generalTags.isNotEmpty
                  ? a.generalTags.join(',').toLowerCase()
                  : '\uffff';
          String bTag =
              b.generalTags.isNotEmpty
                  ? b.generalTags.join(',').toLowerCase()
                  : '\uffff';
          comparison = aTag.compareTo(bTag);
          break;
        // Add cases for other sortable columns if needed
      }
      // Secondary sort by title if primary columns are equal
      if (comparison == 0 && sortColumnName != 'title') {
        comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      return sortDirectionSf == DataGridSortDirection.ascending
          ? comparison
          : -comparison;
    });
    return sortedTracks;
  }

  /// Handles track selection changes
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

    final List<Track> currentDisplayedTracks = getCurrentDisplayedTracks();

    if (isSelected) {
      if (isCtrlPressed) {
        newSelectedIds.add(trackId);
        newAnchorId = trackId;
      } else if (isShiftPressed && newAnchorId != null) {
        final anchorIndex = currentDisplayedTracks.indexWhere(
          (t) => t.id == newAnchorId,
        );
        final clickedIndex = currentDisplayedTracks.indexWhere(
          (t) => t.id == trackId,
        );
        if (anchorIndex != -1 && clickedIndex != -1) {
          final start = anchorIndex < clickedIndex ? anchorIndex : clickedIndex;
          final end = anchorIndex > clickedIndex ? anchorIndex : clickedIndex;
          newSelectedIds.clear();
          for (int i = start; i <= end; i++) {
            if (i >= 0 &&
                i < currentDisplayedTracks.length &&
                currentDisplayedTracks[i].id != null) {
              newSelectedIds.add(currentDisplayedTracks[i].id!);
            }
          }
          // Keep the anchor where the shift-select *started* for subsequent shifts
        } else {
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
        newSelectedIds.remove(trackId);
        if (newAnchorId == trackId) newAnchorId = null;
      } else {
        // Simple deselection or deselecting one from a shift-selection
        newSelectedIds.remove(trackId);
        if (newAnchorId == trackId) newAnchorId = null;
        // If deselecting the only selected item without modifier, clear anchor
        if (newSelectedIds.isEmpty) newAnchorId = null;
      }
    }

    // Update player based on new selection
    Track? newSelectedTrack;
    if (newSelectedIds.length == 1) {
      final newSelectedId = newSelectedIds.first;
      newSelectedTrack = getTrackById(newSelectedId);
    }

    // Return updated selection state
    onSelectionStateChanged(newSelectedIds, newAnchorId, newSelectedTrack);
  }

  /// Gets a track by its ID
  Track? getTrackById(int id) {
    final state = context.read<TrackManagementBloc>().state;
    List<Track> sourceList = [];
    if (state is TrackManagementLoaded) {
      sourceList = state.tracks;
    } else if (state is TrackManagementLoading && state.currentTracks != null) {
      sourceList = state.currentTracks!;
    } else if (state is TrackManagementError && state.tracks != null) {
      sourceList = state.tracks!;
    }

    try {
      return sourceList.firstWhere((t) => t.id == id);
    } catch (e) {
      return null; // Not found
    }
  }

  /// Handles updating player track selection state
  void selectTrackForPlayer(Track track) {
    print("Selecting track for player: ${track.title}");
    final bloc = context.read<AudioPlayerBloc>();
    final currentBlocState = bloc.state;
    bool needsLoad = true;
    if (currentBlocState is AudioPlayerLoaded &&
        currentBlocState.currentSource == track.path) {
      needsLoad = false;
    }

    if (needsLoad) {
      bloc.add(LoadAudio(source: track.path, isUrl: track.isUrl));
    }
  }

  /// Select and load a track, then play it
  void selectAndPlayTrack(Track track) {
    print("Selecting and playing track: ${track.title}");
    final bloc = context.read<AudioPlayerBloc>();
    final currentBlocState = bloc.state;
    bool needsLoad = true;
    if (currentBlocState is AudioPlayerLoaded &&
        currentBlocState.currentSource == track.path) {
      needsLoad = false;
    }

    if (needsLoad) {
      bloc.add(LoadAudio(source: track.path, isUrl: track.isUrl));
      Future.delayed(const Duration(milliseconds: 150), () {
        final postDelayState = bloc.state;
        if (postDelayState is AudioPlayerLoaded &&
            postDelayState.currentSource == track.path) {
          bloc.add(PlayAudio());
        }
      });
    } else {
      bloc.add(PlayAudio());
    }
  }

  /// Open player with track loaded but don't play
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
      bloc.add(LoadAudio(source: track.path, isUrl: track.isUrl));
      // Optional: Auto-play when opening via edit? Maybe not.
    }
  }

  /// Handle rating changes
  void handleRatingChanged(int trackId, int newRating) {
    print("Rating changed in table: Track $trackId -> $newRating stars");
    context.read<TrackManagementBloc>().add(
      UpdateTrackRating(trackId, newRating),
    );
  }
}
