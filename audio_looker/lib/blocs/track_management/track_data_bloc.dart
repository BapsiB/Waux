// lib/blocs/track_data/track_data_bloc.dart

import 'dart:async';
import 'dart:io'; // Required for Directory operations
// import 'dart:math'; // Required for Random waveform generation

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as pathLib; // Use alias

// Import Services and Models
import '../../services/collection_service.dart'; // For Track, CollectionService, CollectionDefinition, CollectionType
import '../../services/waveform_processing_service.dart';
import '../../services/playlist_service.dart'; // For PlaylistService
import '../../utils/track_filtering.dart'; // For applyFilters
// import '../waveform_processing/waveform_processing_event.dart';

part 'track_data_event.dart';
part 'track_data_state.dart';

/// BLoC responsible for loading, filtering, searching, and managing
/// the list of tracks and root folders for the active collection.
class TrackDataBloc extends Bloc<TrackDataEvent, TrackDataState> {
  final CollectionService _collectionService;
  final PlaylistService _playlistService;
  final WaveformProcessingService _waveformProcessingService;
  // final WaveformProcessingBloc _waveformProcessingBloc; // Removed direct dependency
  // Define supported extensions (consider making this configurable later)
  final List<String> _supportedExtensions = [
    'mp3',
    'wav',
    'ogg',
    'm4a',
    'aac',
    'flac',
  ];

  // Keep track of the last search query to re-apply after loads/syncs
  String _lastSearchQuery = '';
  int? _lastMinimumRating;
  bool _isCheckingFiles = false;
  String? _selectedPlaylistId;

  TrackDataBloc({
    required CollectionService collectionService,
    required PlaylistService playlistService,
    required WaveformProcessingService waveformProcessingService,
  }) : _collectionService = collectionService,
       _playlistService = playlistService,
       _waveformProcessingService = waveformProcessingService,
       super(TrackDataInitial()) {
    on<LoadTracks>(_onLoadTracks);
    on<SearchTracks>(_onSearchTracks);
    on<SyncFolders>(_onSyncFolders);
    on<SetRatingFilter>(_onSetRatingFilter);
    on<AddTracks>(_onAddTracks);
    on<AddTrackUrl>(_onAddTrackUrl);
    on<RemoveTrack>(_onRemoveTrack);
    on<AddRootFolder>(_onAddRootFolder);
    on<RemoveRootFolder>(_onRemoveRootFolder);
    on<ReloadDataPreservingFilters>(_onReloadDataPreservingFilters);
    on<DeleteFolder>(_onDeleteFolder);
    on<ConfirmDeleteFolderFiles>(_onConfirmDeleteFolderFiles);
    on<UpdateTrackWaveform>(_onUpdateTrackWaveform);
    on<CheckForNewFiles>(_onCheckForNewFiles);
    on<AddDetectedFiles>(_onAddDetectedFiles);
    on<SetPlaylistFilter>(_onSetPlaylistFilter);
    on<SkipDetectedFiles>(_onSkipDetectedFiles);
    on<ProcessFileChanges>(_onProcessFileChanges);
    on<UpdateTrackPath>(
      _onUpdateTrackPath,
    ); // Might not be directly called from UI anymore
    on<SkipAllFileChanges>(_onSkipAllFileChanges);
  }

  Future<void> _onUpdateTrackPath(
    UpdateTrackPath event,
    Emitter<TrackDataState> emit,
  ) async {
    try {
      await _collectionService.updateTrackPath(event.trackId, event.newPath);
      print(
        "TrackDataBloc: Successfully updated path for track ${event.trackId} from ${event.oldPath} to ${event.newPath}",
      );
      // Optionally, if you want to immediately reflect this specific change in the UI without a full reload:
      // You might need to update the track in the current state's track list and re-emit.
      // However, a full reload after all changes are processed is often simpler.
    } catch (e) {
      print(
        "TrackDataBloc: Error updating path for track ${event.trackId}: $e",
      );
      // Emit an error or handle as needed
    }
  }

  Future<void> _onProcessFileChanges(
    ProcessFileChanges event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      print(
        "TrackDataBloc: Cannot process file changes, no active collection.",
      );
      return;
    }

    emit(
      TrackDataLoading(
        // Indicate processing
        previousTracks: _getTracksFromState(),
        previousRootFolders: _getRootFoldersFromState(),
        searchQuery: _lastSearchQuery,
        minimumRating: _lastMinimumRating,
        selectedPlaylistId: _selectedPlaylistId,
      ),
    );

    bool changesMade = false;

    try {
      // 1. Process Moved Files (updates paths in DB)
      if (event.movedFilesToUpdate.isNotEmpty) {
        print("Processing ${event.movedFilesToUpdate.length} moved files...");
        for (final movedInfo in event.movedFilesToUpdate) {
          // No need to dispatch UpdateTrackPath to self, call service directly for efficiency
          await _collectionService.updateTrackPath(
            movedInfo.trackId,
            movedInfo.newPath,
          );
          print(
            "Updated path for moved track: ${movedInfo.trackTitle} (ID: ${movedInfo.trackId}) to ${movedInfo.newPath}",
          );
        }
        changesMade = true;
      }

      // 2. Process Deletions
      if (event.trackIdsToDelete.isNotEmpty) {
        print("Processing ${event.trackIdsToDelete.length} deletions...");
        for (final trackId in event.trackIdsToDelete) {
          try {
            await _collectionService.deleteTrack(trackId);
          } catch (e) {
            print("Error deleting track $trackId from service: $e");
          }
        }
        changesMade = true;
      }

      // 3. Process Additions
      if (event.filesToAdd.isNotEmpty) {
        print("Processing ${event.filesToAdd.length} additions...");
        // We can directly call _onAddTracks's core logic or dispatch AddTracks
        // Dispatching AddTracks is cleaner to reuse its existing processing (like waveform queueing)
        add(
          AddTracks(event.filesToAdd),
        ); // This will trigger its own loading/processing states
        changesMade =
            true; // Technically AddTracks handles its own reloads, but good to note a change occurred.
        // The final ReloadDataPreservingFilters will catch all.
      }

      // 4. Save the current disk state as the new "last known good state"
      final List<String> currentFilePathsOnDiskList = [];
      final List<String> rootFolders = _collectionService.getRootFolders();
      for (final rootPath in rootFolders) {
        final dir = Directory(rootPath);
        if (await dir.exists()) {
          await _findAudioFilesRecursively(
            dir,
            currentFilePathsOnDiskList,
            _supportedExtensions,
          );
        }
      }
      final Set<String> currentFilesOnDisk =
          currentFilePathsOnDiskList.map(pathLib.normalize).toSet();
      await _collectionService.saveLastScanState(
        activeDef.id,
        currentFilesOnDisk,
      );
      print(
        "Saved current disk state after processing changes for collection ${activeDef.id}.",
      );
    } catch (e, stackTrace) {
      print("TrackDataBloc: Error processing file changes: $e\n$stackTrace");
      emit(TrackDataError("Error applying file changes: ${e.toString()}"));
    } finally {
      // 5. Reload all data to reflect changes
      // If AddTracks was called, it might lead to its own reloads/processing states.
      // This final reload ensures consistency.
      print("Reloading data after processing all file changes.");
      add(ReloadDataPreservingFilters());
    }
  }

  Future<void> _onSkipAllFileChanges(
    SkipAllFileChanges event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      print("TrackDataBloc: Cannot skip file changes, no active collection.");
      return;
    }
    print(
      "TrackDataBloc: User chose to skip all file changes. Saving current disk state.",
    );
    try {
      final List<String> currentFilePathsOnDiskList = [];
      final List<String> rootFolders = _collectionService.getRootFolders();
      for (final rootPath in rootFolders) {
        final dir = Directory(rootPath);
        if (await dir.exists()) {
          await _findAudioFilesRecursively(
            dir,
            currentFilePathsOnDiskList,
            _supportedExtensions,
          );
        }
      }
      final Set<String> currentFilesOnDisk =
          currentFilePathsOnDiskList.map(pathLib.normalize).toSet();
      await _collectionService.saveLastScanState(
        activeDef.id,
        currentFilesOnDisk,
      );
      print(
        "Saved current disk state after skipping changes for collection ${activeDef.id}.",
      );
    } catch (e) {
      print("Error saving disk state after skipping: $e");
    }
    add(
      ReloadDataPreservingFilters(),
    ); // Reload to clear the FilesystemChangesDetected state
  }

  // --- Helper to generate placeholder waveform (Updated) ---
  List<double> _generatePlaceholderWaveform() {
    // Use the same logic as the original AudioService._generateRandomWaveform
    print('Generating placeholder waveform (AudioService logic)');
    return List.generate(
      100, // Generate 100 points
      (index) => (0.3 + 0.7 * (index % 10) / 10), // Specific formula
    );
  }

  Future<void> _onSetPlaylistFilter(
    SetPlaylistFilter event,
    Emitter<TrackDataState> emit,
  ) async {
    print("TrackDataBloc: Setting playlist filter to ID: ${event.playlistId}");
    _selectedPlaylistId = event.playlistId; // Store the new playlist ID

    // Re-apply filters, similar to search/rating changes
    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition == null) {
      emit(
        TrackDataLoaded(
          tracks: const [],
          rootFolders: const [],
          searchQuery: _lastSearchQuery,
          minimumRating: _lastMinimumRating,
          selectedPlaylistId: _selectedPlaylistId,
        ),
      );
      return;
    }

    emit(
      TrackDataLoading(
        // Emit loading while filtering
        previousTracks: _getTracksFromState(),
        previousRootFolders: _getRootFoldersFromState(),
        searchQuery: _lastSearchQuery,
        minimumRating: _lastMinimumRating,
        selectedPlaylistId: _selectedPlaylistId, // <<< Pass ID to state
      ),
    );

    try {
      // 1. Get all tracks
      final allTracks = await _collectionService.getAllTracks();

      // 2. Get track paths for the selected playlist (if any)
      Set<String>? playlistTrackPaths;
      if (_selectedPlaylistId != null) {
        // Fetch all playlists and find the selected one
        // Note: This might be inefficient if you have many playlists.
        // Consider adding a PlaylistService method like `getPlaylistTrackPaths(id)`.
        final allPlaylists = await _playlistService.loadPlaylists(
          _collectionService,
        );
        try {
          final selectedPlaylist = allPlaylists.firstWhere(
            (p) => p.id == _selectedPlaylistId,
          );
          playlistTrackPaths = Set<String>.from(selectedPlaylist.trackPaths);
        } catch (e) {
          print(
            "TrackDataBloc: Error finding selected playlist '$_selectedPlaylistId' - clearing filter.",
          );
          _selectedPlaylistId = null; // Clear filter if playlist not found
        }
      }

      // 3. Apply all filters
      final filteredTracks = applyFilters(
        allTracks: allTracks, // Pass the full list
        searchQuery: _lastSearchQuery,
        minRating: _lastMinimumRating,
        playlistTrackPaths: playlistTrackPaths, // Pass the paths (or null)
      );

      // 4. Emit the final loaded state
      emit(
        TrackDataLoaded(
          tracks: filteredTracks,
          rootFolders: _getRootFoldersFromState(), // Preserve root folders
          searchQuery: _lastSearchQuery.isEmpty ? null : _lastSearchQuery,
          minimumRating: _lastMinimumRating,
          selectedPlaylistId:
              _selectedPlaylistId, // <<< Include the ID in the final state
        ),
      );
    } catch (e, stackTrace) {
      print("TrackDataBloc: ERROR applying playlist filter: $e\n$stackTrace");
      emit(TrackDataError("Failed to apply playlist filter: ${e.toString()}"));
      // Optionally reload all tracks without the failed filter
      add(LoadTracks());
    }
  }

  // --- Modified _onLoadTracks ---
  Future<void> _onLoadTracks(
    LoadTracks event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition == null) {
      print("TrackDataBloc: Cannot load tracks, no active collection.");
      emit(
        TrackDataLoaded(
          tracks: const [],
          rootFolders: const [],
          searchQuery: _lastSearchQuery,
          minimumRating: _lastMinimumRating,
        ),
      );
      return;
    }

    emit(
      TrackDataLoading(
        previousTracks: _getTracksFromState(),
        previousRootFolders: _getRootFoldersFromState(),
        searchQuery: _lastSearchQuery,
        minimumRating: _lastMinimumRating,
      ),
    );

    try {
      List<Track> allTracks = await _collectionService.getAllTracks();
      final rootFolders = _collectionService.getRootFolders();
      print(
        "TrackDataBloc: Loaded ${allTracks.length} tracks and ${rootFolders.length} roots for '${activeDefinition.name}'.",
      );

      // --- START: Process Placeholders & Check for Missing Waveforms ---
      List<Track> tracksForState = [];
      List<Track> tracksNeedingProcessing = [];

      for (var track in allTracks) {
        bool waveformMissing =
            track.waveformData == null || track.waveformData!.isEmpty;

        if (track.sourceType == TrackSource.youtube && waveformMissing) {
          // Generate placeholder for YouTube tracks lacking data using the updated helper
          tracksForState.add(
            track.copyWith(waveformData: _generatePlaceholderWaveform()),
          );
        } else if (!track.isUrl && waveformMissing) {
          // Mark non-URL tracks with missing data for processing
          tracksNeedingProcessing.add(track);
          tracksForState.add(track); // Add original track to state for now
        } else {
          // Track is URL (non-YT) or has waveform data
          tracksForState.add(track);
        }
      }

      Set<String>? playlistTrackPaths;
      if (_selectedPlaylistId != null) {
        final allPlaylists = await _playlistService.loadPlaylists(
          _collectionService,
        );
        try {
          final selectedPlaylist = allPlaylists.firstWhere(
            (p) => p.id == _selectedPlaylistId,
          );
          playlistTrackPaths = Set<String>.from(selectedPlaylist.trackPaths);
        } catch (e) {
          print(
            "TrackDataBloc: Error finding selected playlist '$_selectedPlaylistId' during load.",
          );
          _selectedPlaylistId = null; // Clear invalid ID
        }
      }

      // Apply existing filters *after* potential placeholder generation
      final filteredTracksForState = applyFilters(
        allTracks: tracksForState, // Use the list potentially with placeholders
        searchQuery: _lastSearchQuery,
        minRating: _lastMinimumRating,
        playlistTrackPaths: playlistTrackPaths, // <<< Pass playlist paths
      );

      if (tracksNeedingProcessing.isNotEmpty) {
        print(
          '[TrackDataBloc._onLoadTracks] Found ${tracksNeedingProcessing.length} tracks needing actual waveform processing.',
        );
        final List<Map<String, String>> trackDataForService =
            tracksNeedingProcessing
                .where((track) => track.id != null && track.path.isNotEmpty)
                .map(
                  (track) => {
                    'id': track.id!.toString(),
                    // Resolve path to absolute here before sending to service
                    'path': _resolveAbsolutePath(track),
                  },
                )
                .toList();

        if (trackDataForService.isNotEmpty) {
          // Add to queue
          _waveformProcessingService.addTracksToQueue(trackDataForService);
          print(
            '[TrackDataBloc._onLoadTracks] Added ${trackDataForService.length} tracks to waveform queue.',
          );

          // Emit state to signal processing needed (UI can show progress bar)
          // This state still contains the currently loaded/filtered tracks for display
          emit(
            TrackDataProcessingNeeded(
              addedTracks:
                  tracksNeedingProcessing, // Signal which tracks need processing
              tracks:
                  filteredTracksForState, // Base tracks for UI (includes placeholders)
              rootFolders: rootFolders, // Base roots for UI
              searchQuery: _lastSearchQuery,
              minimumRating: _lastMinimumRating,
            ),
          );
          print(
            '[TrackDataBloc._onLoadTracks] Emitted TrackDataProcessingNeeded.',
          );
          // NOTE: We DO NOT emit TrackDataLoaded immediately after.
          // The WaveformProcessingBloc listener will trigger ReloadDataPreservingFilters
          // which will eventually lead back to TrackDataLoaded state after processing.
        } else {
          // If no valid data for service, just emit normal loaded state
          print(
            '[TrackDataBloc._onLoadTracks] No valid track IDs/paths found for waveform processing, emitting normal loaded state.',
          );
          emit(
            TrackDataLoaded(
              tracks: filteredTracksForState,
              rootFolders: rootFolders,
              searchQuery: _lastSearchQuery,
              minimumRating: _lastMinimumRating,
            ),
          );
        }
      } else {
        // No tracks need waveform processing, emit loaded state directly
        print(
          '[TrackDataBloc._onLoadTracks] No tracks need actual waveform processing, emitting normal loaded state.',
        );
        emit(
          TrackDataLoaded(
            tracks: filteredTracksForState,
            rootFolders: rootFolders,
            searchQuery: _lastSearchQuery,
            minimumRating: _lastMinimumRating,
          ),
        );
      }
      // --- END: Queue tracks ---
    } catch (e, stackTrace) {
      print("TrackDataBloc: ERROR loading tracks: $e\n$stackTrace");
      emit(TrackDataError("Failed to load tracks: ${e.toString()}"));
    }
  }

  // --- Modified _onAddTracks ---
  Future<void> _onAddTracks(
    AddTracks event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      emit(const TrackDataError("Cannot add tracks: No active collection."));
      return;
    }
    print(
      "[TrackDataBloc] Adding ${event.filePaths.length} tracks to ${activeDef.name}",
    );

    final List<Track> addedOrFoundTracks = [];
    final List<Track> tracksNeedingProcessing = [];
    // Removed tracksWithPlaceholders as placeholder logic is now applied later

    // Emit Loading state while adding
    emit(
      TrackDataLoading(
        previousTracks: _getTracksFromState(),
        previousRootFolders: _getRootFoldersFromState(),
        searchQuery: _lastSearchQuery,
        minimumRating: _lastMinimumRating,
      ),
    );

    try {
      for (final filePath in event.filePaths) {
        try {
          final Track? addedOrFoundTrack = await _collectionService
              .addLocalFile(filePath);
          if (addedOrFoundTrack != null) {
            addedOrFoundTracks.add(addedOrFoundTrack);
            // Check if this newly added/found track needs processing
            bool waveformMissing =
                addedOrFoundTrack.waveformData == null ||
                addedOrFoundTrack.waveformData!.isEmpty;
            // Only queue local files for actual processing
            if (!addedOrFoundTrack.isUrl && waveformMissing) {
              tracksNeedingProcessing.add(addedOrFoundTrack);
            }
          }
        } catch (e) {
          print('TrackDataBloc ERROR: Failed to add file $filePath: $e');
        }
      }
      print(
        "[TrackDataBloc] Finished adding/checking ${event.filePaths.length} tracks in service. ${addedOrFoundTracks.length} added/found.",
      );

      // --- Trigger Waveform Processing for newly added local files ---
      if (tracksNeedingProcessing.isNotEmpty) {
        print(
          '[TrackDataBloc._onAddTracks] Triggering waveform processing for ${tracksNeedingProcessing.length} newly added/found local tracks...',
        );
        final List<Map<String, String>> trackDataForService =
            tracksNeedingProcessing
                .where((track) => track.id != null && track.path.isNotEmpty)
                .map(
                  (track) => {
                    'id': track.id!.toString(),
                    'path': _resolveAbsolutePath(track), // Resolve path here
                  },
                )
                .toList();

        if (trackDataForService.isNotEmpty) {
          _waveformProcessingService.addTracksToQueue(trackDataForService);
          print(
            '[TrackDataBloc._onAddTracks] Added ${trackDataForService.length} tracks to waveform queue.',
          );

          // Emit the ProcessingNeeded state, including ALL tracks currently loaded
          final allTracksAfterAdd = await _collectionService.getAllTracks();
          // --- Add placeholders for any YT tracks in the full list ---
          final allTracksWithPlaceholders =
              allTracksAfterAdd.map((track) {
                bool waveformMissing =
                    track.waveformData == null || track.waveformData!.isEmpty;
                if (track.sourceType == TrackSource.youtube &&
                    waveformMissing) {
                  // Use the updated helper method
                  return track.copyWith(
                    waveformData: _generatePlaceholderWaveform(),
                  );
                }
                return track;
              }).toList();
          // --- Apply filters to the list with placeholders ---
          final filteredTracks = applyFilters(
            allTracks: allTracksWithPlaceholders,
            searchQuery: _lastSearchQuery,
            minRating: _lastMinimumRating,
          );

          emit(
            TrackDataProcessingNeeded(
              addedTracks:
                  tracksNeedingProcessing, // Tracks *actually* sent for processing
              tracks:
                  filteredTracks, // Show the *updated* filtered list (with placeholders)
              rootFolders: _getRootFoldersFromState(),
              searchQuery: _lastSearchQuery,
              minimumRating: _lastMinimumRating,
            ),
          );
          print(
            '[TrackDataBloc._onAddTracks] Emitted TrackDataProcessingNeeded.',
          );
        } else {
          print(
            '[TrackDataBloc._onAddTracks] No valid tracks to queue. Reloading...',
          );
          add(ReloadDataPreservingFilters()); // Fallback reload
        }
      } else {
        // No tracks needed processing, just reload to show added tracks
        print(
          '[TrackDataBloc._onAddTracks] No new tracks need processing. Reloading...',
        );
        add(ReloadDataPreservingFilters());
      }
      // --- End Trigger Waveform Processing ---
    } catch (e, stackTrace) {
      print('TrackDataBloc ERROR: Exception in _onAddTracks: $e\n$stackTrace');
      emit(TrackDataError("Failed to add tracks: ${e.toString()}"));
      add(ReloadDataPreservingFilters());
    }
  }
  // --- End Modified _onAddTracks ---

  Future<void> _onAddTrackUrl(
    AddTrackUrl event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      emit(const TrackDataError("Cannot add URL: No active collection."));
      return;
    }

    emit(
      TrackDataLoading(
        previousTracks: _getTracksFromState(),
        previousRootFolders: _getRootFoldersFromState(),
        searchQuery: _lastSearchQuery,
        minimumRating: _lastMinimumRating,
      ),
    );

    try {
      // addUrl now returns the track, check if it's YouTube
      // final Track? addedTrack = await _collectionService.addUrl(event.url);

      // --- Reload data AFTER adding the URL ---
      // The _onLoadTracks handler will now generate the placeholder if needed.
      add(ReloadDataPreservingFilters());
    } catch (e, stackTrace) {
      print("TrackDataBloc ERROR adding track from URL: $e\n$stackTrace");
      emit(TrackDataError("Failed to add URL: ${e.toString()}"));
      // Reload even on error to potentially clear loading state
      add(ReloadDataPreservingFilters());
    }
  }

  // --- Other event handlers ---
  Future<void> _onSearchTracks(
    SearchTracks event,
    Emitter<TrackDataState> emit,
  ) async {
    _lastSearchQuery = event.query; // Store the new search query
    print(
      "TrackDataBloc: Handling search: '$_lastSearchQuery'. Current selected playlist ID: $_selectedPlaylistId",
    ); // Log

    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition == null) {
      // Handle case where no collection is active (e.g., emit empty loaded state)
      emit(
        TrackDataLoaded(
          tracks: const [],
          rootFolders: const [],
          searchQuery:
              _lastSearchQuery.isEmpty
                  ? null
                  : _lastSearchQuery, // Reflect search query
          minimumRating: _lastMinimumRating,
          selectedPlaylistId: _selectedPlaylistId, // Keep playlist ID
        ),
      );
      return;
    }

    // Emit loading state, preserving all current filters
    emit(
      TrackDataLoading(
        previousTracks: _getTracksFromState(),
        previousRootFolders: _getRootFoldersFromState(),
        searchQuery: _lastSearchQuery.isEmpty ? null : _lastSearchQuery,
        minimumRating: _lastMinimumRating,
        selectedPlaylistId: _selectedPlaylistId, // <<< Pass current playlist ID
      ),
    );

    try {
      // 1. Get all tracks from the collection service
      final allTracks = await _collectionService.getAllTracks();
      print(
        "TrackDataBloc: Fetched ${allTracks.length} total tracks for search.",
      );

      // 2. Fetch playlist track paths based on the currently stored _selectedPlaylistId
      Set<String>? playlistTrackPaths;
      if (_selectedPlaylistId != null) {
        // Use the injected PlaylistService to get playlist details
        final allPlaylists = await _playlistService.loadPlaylists(
          _collectionService,
        );
        try {
          final selectedPlaylist = allPlaylists.firstWhere(
            (p) => p.id == _selectedPlaylistId,
          );
          playlistTrackPaths = Set<String>.from(selectedPlaylist.trackPaths);
          print(
            "TrackDataBloc: Fetched ${playlistTrackPaths.length} track paths for playlist ID: $_selectedPlaylistId",
          );
        } catch (e) {
          print(
            "TrackDataBloc: Error finding playlist '$_selectedPlaylistId' during search. Clearing playlist filter.",
          );
          _selectedPlaylistId = null; // Clear invalid ID if playlist vanished
        }
      } else {
        print("TrackDataBloc: No playlist selected for search filter.");
      }

      // 3. Apply ALL filters (including the new search query and existing rating/playlist)
      // Note: Placeholder generation logic might be needed here if not done in getAllTracks
      final allTracksWithPlaceholders =
          allTracks.map((track) {
            bool waveformMissing =
                track.waveformData == null || track.waveformData!.isEmpty;
            if (track.sourceType == TrackSource.youtube && waveformMissing) {
              return track.copyWith(
                waveformData: _generatePlaceholderWaveform(),
              );
            }
            return track;
          }).toList();

      final filteredTracks = applyFilters(
        allTracks:
            allTracksWithPlaceholders, // Use the list (potentially with placeholders)
        searchQuery: _lastSearchQuery, // Use the *new* search query
        minRating: _lastMinimumRating, // Use the *existing* rating filter
        playlistTrackPaths:
            playlistTrackPaths, // Use the fetched playlist paths
      );
      print(
        "TrackDataBloc: Emitting search results. Filtered count: ${filteredTracks.length}",
      );

      // 4. Emit the final loaded state
      emit(
        TrackDataLoaded(
          tracks: filteredTracks,
          rootFolders: _getRootFoldersFromState(), // Preserve root folders
          searchQuery: _lastSearchQuery.isEmpty ? null : _lastSearchQuery,
          minimumRating: _lastMinimumRating,
          selectedPlaylistId:
              _selectedPlaylistId, // <<< Include the playlist ID
        ),
      );
    } catch (e, stackTrace) {
      print("TrackDataBloc: ERROR during search: $e\n$stackTrace");
      emit(TrackDataError("Failed to search: ${e.toString()}"));
      // Optionally reload data without filters on error
      add(ReloadDataPreservingFilters());
    }
  }

  Future<void> _onSetRatingFilter(
    SetRatingFilter event,
    Emitter<TrackDataState> emit,
  ) async {
    _lastMinimumRating = event.rating; // Store the latest filter

    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition == null) return;

    List<Track> allTracks = [];
    try {
      allTracks = await _collectionService.getAllTracks();
    } catch (e) {
      print("TrackDataBloc: Error getting all tracks for filter: $e");
      emit(TrackDataError("Failed to apply filter: ${e.toString()}"));
      return;
    }

    // --- Add placeholders before filtering ---
    final allTracksWithPlaceholders =
        allTracks.map((track) {
          bool waveformMissing =
              track.waveformData == null || track.waveformData!.isEmpty;
          if (track.sourceType == TrackSource.youtube && waveformMissing) {
            return track.copyWith(waveformData: _generatePlaceholderWaveform());
          }
          return track;
        }).toList();
    // --- End Add placeholders ---

    final filteredTracks = applyFilters(
      allTracks: allTracksWithPlaceholders, // <<< Filter list with placeholders
      searchQuery: _lastSearchQuery,
      minRating: _lastMinimumRating,
    );

    emit(
      TrackDataLoaded(
        tracks: filteredTracks,
        rootFolders: _getRootFoldersFromState(), // Preserve root folders
        searchQuery: _lastSearchQuery.isEmpty ? null : _lastSearchQuery,
        minimumRating: _lastMinimumRating,
      ),
    );
  }

  Future<void> _onSyncFolders(
    SyncFolders event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition == null) {
      print("TrackDataBloc: Skipping folder sync, no active collection.");
      return;
    }

    print(
      "TrackDataBloc: Starting folder sync for '${activeDefinition.name}'.",
    );

    try {
      final rootFolders = _collectionService.getRootFolders();
      if (rootFolders.isEmpty) {
        print("TrackDataBloc: No root folders defined for sync.");
        return;
      }

      final List<String> filesOnDisk = [];
      for (final rootPath in rootFolders) {
        final dir = Directory(rootPath);
        if (await dir.exists()) {
          await _findAudioFilesRecursively(
            dir,
            filesOnDisk,
            _supportedExtensions,
          );
        } else {
          print(
            "TrackDataBloc: Root folder '$rootPath' does not exist during sync.",
          );
        }
      }
      print(
        "TrackDataBloc: Found ${filesOnDisk.length} files on disk across ${rootFolders.length} root(s).",
      );

      final tracksInDb = await _collectionService.getAllTracks();
      final Set<String> pathsInDb =
          tracksInDb
              .where((t) => !t.isUrl)
              .map((t) => pathLib.normalize(t.path))
              .toSet();
      print("TrackDataBloc: Found ${pathsInDb.length} local tracks in DB.");

      final Set<String> normalizedFilesOnDisk =
          filesOnDisk.map((p) => pathLib.normalize(p)).toSet();

      final List<String> filesToAdd =
          normalizedFilesOnDisk
              .where((diskPath) => !pathsInDb.contains(diskPath))
              .toList();

      if (filesToAdd.isNotEmpty) {
        print(
          "TrackDataBloc: Sync found ${filesToAdd.length} new files to add.",
        );
        add(AddTracks(filesToAdd));
      } else {
        print("TrackDataBloc: Sync complete. No new files found.");
      }
    } catch (e, stackTrace) {
      print("TrackDataBloc: ERROR during folder sync: $e\n$stackTrace");
      emit(TrackDataError("Failed to sync folders: ${e.toString()}"));
    }
  }

  Future<void> _onUpdateTrackWaveform(
    UpdateTrackWaveform event,
    Emitter<TrackDataState> emit,
  ) async {
    final int? targetTrackId = int.tryParse(event.trackId);
    if (targetTrackId == null) {
      print(
        'Error: Invalid trackId received for waveform update: ${event.trackId}',
      );
      return;
    }

    final currentState = state;
    List<Track>? trackListToUpdate;
    List<String>? rootFoldersToKeep;
    String? currentSearchQuery;
    int? currentMinimumRating;
    bool wasProcessingNeeded = false;

    if (currentState is TrackDataLoaded) {
      trackListToUpdate = currentState.tracks;
      rootFoldersToKeep = currentState.rootFolders;
      currentSearchQuery = currentState.searchQuery;
      currentMinimumRating = currentState.minimumRating;
    } else if (currentState is TrackDataProcessingNeeded) {
      trackListToUpdate = currentState.tracks;
      rootFoldersToKeep = currentState.rootFolders;
      currentSearchQuery = currentState.searchQuery;
      currentMinimumRating = currentState.minimumRating;
      wasProcessingNeeded = true;
    } else if (currentState is TrackDataLoading) {
      trackListToUpdate = currentState.previousTracks;
      print(
        'Warning: Received waveform update while loading. Update will be applied on next load.',
      );
      try {
        final track = await _collectionService.getTrack(targetTrackId);
        if (track != null) {
          await _collectionService.updateTrack(
            track.copyWith(waveformData: event.waveformData),
          );
          print(
            '[TrackDataBloc._onUpdateTrackWaveform] Persisted waveform while loading for track $targetTrackId.',
          );
        }
      } catch (e) {
        print(
          '[TrackDataBloc._onUpdateTrackWaveform] Error persisting waveform while loading for track $targetTrackId: $e',
        );
      }
      return;
    } else {
      print(
        'Warning: Received waveform update while state is ${currentState.runtimeType}. Ignoring UI update.',
      );
      try {
        final track = await _collectionService.getTrack(targetTrackId);
        if (track != null) {
          await _collectionService.updateTrack(
            track.copyWith(waveformData: event.waveformData),
          );
          print(
            '[TrackDataBloc._onUpdateTrackWaveform] Persisted waveform during other state for track $targetTrackId.',
          );
        }
      } catch (e) {
        print(
          '[TrackDataBloc._onUpdateTrackWaveform] Error persisting waveform during other state for track $targetTrackId: $e',
        );
      }
      return;
    }

    // if (trackListToUpdate != null) {
    final trackIndex = trackListToUpdate.indexWhere(
      (t) => t.id == targetTrackId,
    );

    if (trackIndex != -1) {
      final List<Track> updatedTracks = List.from(trackListToUpdate);
      final originalTrack = updatedTracks[trackIndex];
      updatedTracks[trackIndex] = originalTrack.copyWith(
        waveformData: event.waveformData,
      );

      if (wasProcessingNeeded) {
        final processingState = currentState as TrackDataProcessingNeeded;
        emit(
          TrackDataProcessingNeeded(
            addedTracks: processingState.addedTracks,
            tracks: updatedTracks,
            rootFolders: rootFoldersToKeep,
            searchQuery: currentSearchQuery,
            minimumRating: currentMinimumRating,
          ),
        );
      } else {
        emit(
          TrackDataLoaded(
            tracks: updatedTracks,
            rootFolders: rootFoldersToKeep,
            searchQuery: currentSearchQuery,
            minimumRating: currentMinimumRating,
          ),
        );
      }

      try {
        await _collectionService.updateTrack(updatedTracks[trackIndex]);
      } catch (e) {
        print(
          '[TrackDataBloc._onUpdateTrackWaveform] Error persisting waveform for track $targetTrackId: $e',
        );
      }
    } else {
      print(
        'Warning: Track $targetTrackId not found for waveform update in state ${currentState.runtimeType}.',
      );
    }
    // }
  }

  // In TrackDataBloc

  // Modify or replace _onCheckForNewFiles with more comprehensive logic
  Future<void> _onCheckForNewFiles(
    CheckForNewFiles event,
    Emitter<TrackDataState> emit,
  ) async {
    if (_isCheckingFiles) {
      print(
        "TrackDataBloc: Already checking for files, skipping duplicate request.",
      );
      return;
    }
    _isCheckingFiles = true;
    print("TrackDataBloc: _onCheckForNewFiles comprehensively...");

    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      print("Skipping file check: No active collection.");
      _isCheckingFiles = false;
      return;
    }
    // Avoid re-triggering if a dialog is already pending
    if (state is FilesystemChangesDetected &&
        (state as FilesystemChangesDetected).hasChanges) {
      print(
        "Skipping new file check: Already awaiting user confirmation for file changes.",
      );
      _isCheckingFiles = false;
      return;
    }

    emit(
      TrackDataLoading(
        // Emit loading state
        previousTracks: _getTracksFromState(),
        previousRootFolders: _getRootFoldersFromState(),
        searchQuery: _lastSearchQuery,
        minimumRating: _lastMinimumRating,
        selectedPlaylistId: _selectedPlaylistId,
      ),
    );

    try {
      // 1. Get current files on disk
      final List<String> currentFilePathsOnDiskList = [];
      final List<String> rootFolders = _collectionService.getRootFolders();
      if (rootFolders.isEmpty && activeDef.type == CollectionType.local) {
        print(
          "No root folders to scan for local collection ${activeDef.name}.",
        );
        await _collectionService.saveLastScanState(
          activeDef.id,
          {},
        ); // Save empty for next time
        _isCheckingFiles = false;
        add(ReloadDataPreservingFilters()); // Reload to clear loading state
        return;
      }

      for (final rootPath in rootFolders) {
        final dir = Directory(rootPath);
        if (await dir.exists()) {
          await _findAudioFilesRecursively(
            dir,
            currentFilePathsOnDiskList,
            _supportedExtensions,
          );
        } else {
          print(
            "Warning: Root folder $rootPath not found during scan for collection ${activeDef.name}.",
          );
        }
      }
      final Set<String> currentFilesOnDisk =
          currentFilePathsOnDiskList.map(pathLib.normalize).toSet();
      print(
        "Scan found ${currentFilesOnDisk.length} supported files on disk for ${activeDef.name}.",
      );

      // 2. Get tracks from DB
      final List<Track> tracksInDb = await _collectionService.getAllTracks();
      final Map<String, Track> dbTracksByNormalizedPath = {
        for (var track in tracksInDb.where((t) => !t.isUrl && t.id != null))
          pathLib.normalize(track.path):
              track, // track.path is already absolute from getAllTracks
      };
      print(
        "Found ${dbTracksByNormalizedPath.length} local tracks in DB for ${activeDef.name}.",
      );

      // 3. Load last known files (optional, but helps distinguish truly new vs. just not in DB yet)
      // For simplicity in this pass, we'll primarily compare Disk vs DB.
      // A more advanced version would use lastKnownFiles to differentiate between
      // files that were deleted since last app run vs. files never known.

      // Identify differences
      final List<String> newDiskOnlyPaths = []; // Files on disk, not in DB
      final List<Track> dbOnlyTracks = []; // Tracks in DB, not on disk

      for (String diskPath in currentFilesOnDisk) {
        if (!dbTracksByNormalizedPath.containsKey(diskPath)) {
          newDiskOnlyPaths.add(diskPath);
        }
      }

      for (String dbPathKey in dbTracksByNormalizedPath.keys) {
        if (!currentFilesOnDisk.contains(dbPathKey)) {
          dbOnlyTracks.add(dbTracksByNormalizedPath[dbPathKey]!);
        }
      }
      print(
        "Initial detection: ${newDiskOnlyPaths.length} new disk paths, ${dbOnlyTracks.length} DB-only tracks.",
      );

      // Detect Moved Files
      final List<MovedFileUpdate> movedFileUpdates = [];
      final List<String> confirmedNewFilePaths = [];
      final List<Track> confirmedDeletedTracks = [];

      // Create a map of new filenames to their full paths for quick lookup
      Map<String, String> newDiskFilenamesToPath = {
        for (var p in newDiskOnlyPaths) pathLib.basename(p): p,
      };

      for (Track deletedTrackCandidate in dbOnlyTracks) {
        String deletedFilename = pathLib.basename(deletedTrackCandidate.path);
        if (newDiskFilenamesToPath.containsKey(deletedFilename)) {
          // This filename exists in both deleted (from DB perspective) and new (on disk)
          String newPath = newDiskFilenamesToPath[deletedFilename]!;
          movedFileUpdates.add(
            MovedFileUpdate(
              trackId: deletedTrackCandidate.id!,
              oldPath: deletedTrackCandidate.path, // This is already absolute
              newPath: newPath, // This is also absolute from disk scan
              trackTitle: deletedTrackCandidate.title,
            ),
          );
          // Remove from newDiskFilenamesToPath and newDiskOnlyPaths to avoid double processing
          newDiskFilenamesToPath.remove(deletedFilename);
          newDiskOnlyPaths.remove(newPath);
        } else {
          // Filename not found in new paths, so it's a confirmed deletion
          confirmedDeletedTracks.add(deletedTrackCandidate);
        }
      }
      // Remaining paths in newDiskOnlyPaths are truly new files
      confirmedNewFilePaths.addAll(newDiskOnlyPaths);
      print(
        "Final detection: ${confirmedNewFilePaths.length} new, ${confirmedDeletedTracks.length} deleted, ${movedFileUpdates.length} moved.",
      );

      if (confirmedNewFilePaths.isNotEmpty ||
          confirmedDeletedTracks.isNotEmpty ||
          movedFileUpdates.isNotEmpty) {
        emit(
          FilesystemChangesDetected(
            newFilePaths: confirmedNewFilePaths,
            deletedTracks: confirmedDeletedTracks,
            movedFileUpdates: movedFileUpdates,
            currentTracksInUI: _getTracksFromState(), // Pass current UI state
            currentRootFoldersInUI: _getRootFoldersFromState(),
            currentSearchQuery: _lastSearchQuery,
            currentMinimumRating: _lastMinimumRating,
            currentSelectedPlaylistId: _selectedPlaylistId,
          ),
        );
        print("Emitted FilesystemChangesDetected.");
      } else {
        print("No file system changes detected requiring user action.");
        await _collectionService.saveLastScanState(
          activeDef.id,
          currentFilesOnDisk,
        );
        add(
          ReloadDataPreservingFilters(),
        ); // Ensure UI is up-to-date if loading was emitted
      }
    } catch (e, stackTrace) {
      print(
        "TrackDataBloc: ERROR during comprehensive file check: $e\n$stackTrace",
      );
      emit(TrackDataError("Failed during file system check: ${e.toString()}"));
      // Fallback to a stable state
      add(ReloadDataPreservingFilters());
    } finally {
      _isCheckingFiles = false;
    }
  }

  Future<void> _onAddDetectedFiles(
    AddDetectedFiles event,
    Emitter<TrackDataState> emit,
  ) async {
    print(
      "User confirmed adding ${event.filePathsToAdd.length} detected files.",
    );
    // 1. Dispatch AddTracks
    add(AddTracks(event.filePathsToAdd));

    // 2. !!! IMPORTANT: Need mechanism to wait for AddTracks completion !!!
    //    This is complex with BLoC. Options:
    //    a) Make _onAddTracks async and return a Future. Await it here.
    //    b) Have AddTracks emit a specific "AddTracksCompleted" state that this handler listens for.
    //    c) Use `emit.forEach` or `await emit.forEach` if `AddTracks` generates a stream of updates.
    //    Simplest for now (but potentially racy): Assume AddTracks finishes quickly and rescan/save.
    await Future.delayed(
      Duration(seconds: 2),
    ); // Crude delay - **REPLACE WITH ROBUST METHOD**

    // 3. Save the *new* current state after adding
    await _saveCurrentDiskStateAfterScan();

    // 4. Reload data to reflect additions and clear NewFilesDetected state
    add(ReloadDataPreservingFilters());
  }

  Future<void> _saveCurrentDiskStateAfterScan() async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) return;
    final List<String> currentFilesOnDiskList = [];
    final rootFolders = _collectionService.getRootFolders();
    for (final rootPath in rootFolders) {
      final dir = Directory(rootPath);
      if (await dir.exists()) {
        await _findAudioFilesRecursively(
          dir,
          currentFilesOnDiskList,
          _supportedExtensions,
        );
      }
    }
    final Set<String> currentFilesOnDisk =
        currentFilesOnDiskList.map((p) => pathLib.normalize(p)).toSet();
    await _collectionService.saveLastScanState(
      activeDef.id,
      currentFilesOnDisk,
    );
    print("Updated last scanned file state for collection ${activeDef.name}.");
  }

  Future<void> _onSkipDetectedFiles(
    SkipDetectedFiles event,
    Emitter<TrackDataState> emit,
  ) async {
    print("User skipped adding detected files.");
    // Save the state representing files *before* adding the new ones
    // This requires getting the list scanned during _onCheckForNewFiles.
    // For simplicity now, we rescan and save, effectively skipping the prompt next time.
    await _saveCurrentDiskStateAfterScan();
    // Reload data to clear the NewFilesDetected state
    add(ReloadDataPreservingFilters());
  }

  Future<void> _onRemoveTrack(
    RemoveTrack event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      print(
        "TrackDataBloc._onRemoveTrack: No active collection, skipping delete for track ${event.trackId}",
      );
      return;
    }

    print(
      "TrackDataBloc._onRemoveTrack: Received event for track ${event.trackId}",
    );

    final tracksBeforeDelete = _getTracksFromState();
    List<Track> optimisticTracks =
        tracksBeforeDelete.where((t) => t.id != event.trackId).toList();

    print(
      "TrackDataBloc._onRemoveTrack: Emitting optimistic state with ${optimisticTracks.length} tracks.",
    );
    emit(
      TrackDataLoaded(
        tracks: optimisticTracks,
        rootFolders: _getRootFoldersFromState(),
        searchQuery: _lastSearchQuery,
        minimumRating: _lastMinimumRating,
      ),
    );

    try {
      print(
        "TrackDataBloc._onRemoveTrack: Calling collectionService.deleteTrack(${event.trackId}).",
      );
      final int deletedCount = await _collectionService.deleteTrack(
        event.trackId,
      );
      print(
        "TrackDataBloc._onRemoveTrack: Service deleteTrack completed. Rows affected: $deletedCount",
      );

      if (deletedCount == 0) {
        print(
          "TrackDataBloc._onRemoveTrack: Warning - Service reported 0 rows deleted for track ${event.trackId}. Data might be inconsistent.",
        );
        add(ReloadDataPreservingFilters());
      }
    } catch (e, stackTrace) {
      print(
        "TrackDataBloc._onRemoveTrack: ERROR removing track ${event.trackId} from service: $e\n$stackTrace",
      );
      add(ReloadDataPreservingFilters());
      emit(TrackDataError("Failed to remove track: ${e.toString()}"));
    }
  }

  Future<void> _onAddRootFolder(
    AddRootFolder event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef?.type != CollectionType.local) {
      print(
        "TrackDataBloc: Skipping AddRootFolder - only for local collections.",
      );
      return;
    }

    try {
      await _collectionService.addRootFolder(event.folderPath);
      add(ReloadDataPreservingFilters());
    } catch (e) {
      print('TrackDataBloc: Error adding root folder: $e');
      emit(TrackDataError('Failed to add root folder: ${e.toString()}'));
    }
  }

  Future<void> _onRemoveRootFolder(
    RemoveRootFolder event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef?.type != CollectionType.local) {
      print(
        "TrackDataBloc: Skipping RemoveRootFolder - only for local collections.",
      );
      return;
    }

    try {
      await _collectionService.removeRootFolder(event.folderPath);
      add(ReloadDataPreservingFilters());
    } catch (e) {
      print('TrackDataBloc: Error removing root folder: $e');
      emit(TrackDataError('Failed to remove root folder: ${e.toString()}'));
    }
  }

  Future<void> _onReloadDataPreservingFilters(
    ReloadDataPreservingFilters event,
    Emitter<TrackDataState> emit,
  ) async {
    add(LoadTracks()); // Trigger the standard load process
  }

  Future<void> _onDeleteFolder(
    DeleteFolder event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) return;

    print("TrackDataBloc: Received DeleteFolder event for ${event.folderPath}");

    try {
      final tracksToDelete = await _collectionService.getTracksInFolder(
        event.folderPath,
      );
      final trackIdsToDelete =
          tracksToDelete.map((t) => t.id).whereNotNull().toList();
      print(
        "Found ${trackIdsToDelete.length} tracks to delete within ${event.folderPath}",
      );

      for (final trackId in trackIdsToDelete) {
        try {
          await _collectionService.deleteTrack(trackId);
        } catch (e) {
          print("Error deleting track $trackId during folder delete: $e");
        }
      }
      print("Finished removing ${trackIdsToDelete.length} tracks from DB.");

      if (activeDef.type == CollectionType.local) {
        final rootFolders = _collectionService.getRootFolders();
        final normalizedPath = pathLib.normalize(event.folderPath);
        if (rootFolders.any(
          (root) => pathLib.equals(pathLib.normalize(root), normalizedPath),
        )) {
          try {
            await _collectionService.removeRootFolder(event.folderPath);
            print("Removed root folder entry: ${event.folderPath}");
          } catch (e) {
            print("Error removing root folder ${event.folderPath} from DB: $e");
          }
        }
      }

      if (event.folderPath != "Web Links" &&
          event.folderPath != "Imported Files" &&
          tracksToDelete.isNotEmpty &&
          activeDef.type == CollectionType.local) {
        emit(
          FolderDeletionConfirmationNeeded(
            folderPath: event.folderPath,
            folderName: pathLib.basename(event.folderPath),
            trackCount: tracksToDelete.length,
          ),
        );
        print(
          "Emitting FolderDeletionConfirmationNeeded for ${event.folderPath}",
        );
      } else {
        print("No confirmation needed or folder empty/shared. Reloading data.");
        add(ReloadDataPreservingFilters());
      }
    } catch (e, stackTrace) {
      print("TrackDataBloc ERROR during folder deletion: $e\n$stackTrace");
      emit(TrackDataError("Failed to delete folder: ${e.toString()}"));
      add(ReloadDataPreservingFilters());
    }
  }

  Future<void> _onConfirmDeleteFolderFiles(
    ConfirmDeleteFolderFiles event,
    Emitter<TrackDataState> emit,
  ) async {
    print(
      "TrackDataBloc: Received ConfirmDeleteFolderFiles for ${event.folderPath}. Delete from disk: ${event.deleteFilesFromDisk}",
    );

    if (event.deleteFilesFromDisk) {
      emit(
        TrackDataDeletingFolder(
          previousTracks: _getTracksFromState(),
          previousRootFolders: _getRootFoldersFromState(),
          searchQuery: _lastSearchQuery,
          minimumRating: _lastMinimumRating,
        ),
      );
      try {
        await _collectionService.deleteFolderFromDisk(event.folderPath);
        print("Deletion from disk requested for ${event.folderPath}");
      } catch (e) {
        print("Error during disk deletion call for ${event.folderPath}: $e");
        emit(
          TrackDataError("Failed to delete folder from disk: ${e.toString()}"),
        );
      }
    } else {
      print("Skipping deletion from disk for ${event.folderPath}");
    }

    print("Reloading data after folder deletion process.");
    add(ReloadDataPreservingFilters());
  }

  List<Track> _getTracksFromState() {
    final currentState = state;
    if (currentState is TrackDataLoaded) return currentState.tracks;
    if (currentState is TrackDataLoading) {
      return currentState.previousTracks ?? [];
    }
    if (currentState is TrackDataProcessingNeeded) {
      return currentState.tracks; // Use tracks from this state
    }
    if (currentState is TrackDataDeletingFolder) {
      return currentState.previousTracks ?? [];
    }
    return [];
  }

  List<String> _getRootFoldersFromState() {
    final currentState = state;
    if (currentState is TrackDataLoaded) return currentState.rootFolders;
    if (currentState is TrackDataLoading) {
      return currentState.previousRootFolders ?? [];
    }
    if (currentState is TrackDataProcessingNeeded) {
      return currentState.rootFolders;
    }
    if (currentState is TrackDataDeletingFolder) {
      return currentState.previousRootFolders ?? [];
    }
    return [];
  }

  Future<void> _findAudioFilesRecursively(
    Directory dir,
    List<String> audioFilePaths,
    List<String> supportedExtensions,
  ) async {
    try {
      await for (final entity in dir.list(
        recursive: false,
        followLinks: false,
      )) {
        FileSystemEntityType type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file) {
          final extension = pathLib
              .extension(entity.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (supportedExtensions.contains(extension)) {
            audioFilePaths.add(entity.path);
          }
        } else if (type == FileSystemEntityType.directory) {
          await _findAudioFilesRecursively(
            Directory(entity.path),
            audioFilePaths,
            supportedExtensions,
          );
        }
      }
    } catch (e) {
      print("TrackDataBloc: Error scanning directory ${dir.path}: $e");
    }
  }

  String _resolveAbsolutePath(Track track) {
    if (track.isUrl) {
      return track.path; // URLs are already absolute
    }
    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition?.type == CollectionType.shared &&
        activeDefinition?.rootPath != null &&
        !pathLib.isAbsolute(track.path)) {
      try {
        return pathLib.normalize(
          pathLib.join(activeDefinition!.rootPath!, track.path),
        );
      } catch (e) {
        print(
          "Error resolving relative path ${track.path} with root ${activeDefinition!.rootPath}: $e",
        );
        return track.path;
      }
    }
    return pathLib.normalize(track.path);
  }
}

extension WhereNotNull<T> on Iterable<T?> {
  List<T> whereNotNull() => where((e) => e != null).cast<T>().toList();
}
