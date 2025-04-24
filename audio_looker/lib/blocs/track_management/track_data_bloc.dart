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
// import '../waveform_processing/waveform_processing_bloc.dart';
// import '../waveform_processing/waveform_processing_event.dart';

part 'track_data_event.dart';
part 'track_data_state.dart';

/// BLoC responsible for loading, filtering, searching, and managing
/// the list of tracks and root folders for the active collection.
class TrackDataBloc extends Bloc<TrackDataEvent, TrackDataState> {
  final CollectionService _collectionService;
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

  TrackDataBloc({
    required CollectionService collectionService,
    // Add waveform dependencies
    required WaveformProcessingService waveformProcessingService,
    // required WaveformProcessingBloc waveformProcessingBloc, // Removed
  }) : _collectionService = collectionService,
       // Store waveform dependencies
       _waveformProcessingService = waveformProcessingService,
       //  _waveformProcessingBloc = waveformProcessingBloc, // Removed
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
    on<CheckForNewFiles>(_onCheckForNewFiles); // Add handler
    on<AddDetectedFiles>(_onAddDetectedFiles); // Add handler
    on<SkipDetectedFiles>(_onSkipDetectedFiles);
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
  // --- End Helper ---

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
      // --- END: Process Placeholders & Check for Missing Waveforms ---

      // Apply existing filters *after* potential placeholder generation
      final filteredTracksForState = _applyFilters(
        tracksForState, // Filter the list potentially containing placeholders
        _lastSearchQuery,
        _lastMinimumRating,
      );

      // --- Queue tracks that need actual processing ---
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
  // --- End Modified _onLoadTracks ---

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
          final filteredTracks = _applyFilters(
            allTracksWithPlaceholders,
            _lastSearchQuery,
            _lastMinimumRating,
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
    _lastSearchQuery = event.query; // Store the latest query

    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition == null) return; // Should have data if loaded

    List<Track> allTracks = [];
    try {
      allTracks = await _collectionService.getAllTracks();
    } catch (e) {
      print("TrackDataBloc: Error getting all tracks for search: $e");
      emit(TrackDataError("Failed to search: ${e.toString()}"));
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

    final filteredTracks = _applyFilters(
      allTracksWithPlaceholders, // <<< Filter list with placeholders
      _lastSearchQuery,
      _lastMinimumRating,
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

    final filteredTracks = _applyFilters(
      allTracksWithPlaceholders, // <<< Filter list with placeholders
      _lastSearchQuery,
      _lastMinimumRating,
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

  Future<void> _onCheckForNewFiles(
    CheckForNewFiles event,
    Emitter<TrackDataState> emit,
  ) async {
    // Prevent concurrent execution
    if (_isCheckingFiles) {
      print(
        "TrackDataBloc: Already checking for files, skipping duplicate request.",
      );
      return;
    }
    _isCheckingFiles = true; // Set flag

    print("TrackDataBloc: _onCheckForNewFiles entered.");

    final activeDef = _collectionService.getActiveCollection();
    // Currently only checking for local collections, adjust if needed for shared
    if (activeDef == null || activeDef.type != CollectionType.local) {
      print(
        "Skipping new file check: Not a local collection or no active collection.",
      );
      _isCheckingFiles = false; // Reset flag before returning
      return;
    }

    // Avoid checking if already in the NewFilesDetected state (user needs to respond first)
    if (state is NewFilesDetected) {
      print("Skipping new file check: Already awaiting user confirmation.");
      _isCheckingFiles = false; // Reset flag
      return;
    }

    print("TrackDataBloc: Checking for new files in ${activeDef.name}...");

    Set<String>? lastKnownFiles;
    Set<String> currentFilesOnDisk = {};
    bool scanError = false;
    List<String> rootFolders = []; // Store roots for state emission

    try {
      // 1. Load last state
      lastKnownFiles = await _collectionService.loadLastScanState(activeDef.id);
      print(
        "Last known files state loaded: ${lastKnownFiles?.length ?? 'None (first scan)'}",
      );

      // 2. Scan current files
      final List<String> currentFilesOnDiskList = [];
      rootFolders = _collectionService.getRootFolders(); // Get current roots
      if (rootFolders.isEmpty) {
        print("No root folders to scan for collection ${activeDef.name}.");
        // Save empty state if no roots defined, potentially clear last state?
        await _collectionService.saveLastScanState(activeDef.id, {});
        _isCheckingFiles = false; // Reset flag
        return; // Nothing to scan
      }

      for (final rootPath in rootFolders) {
        final dir = Directory(rootPath);
        if (await dir.exists()) {
          // Use the existing recursive helper from the BLoC
          await _findAudioFilesRecursively(
            dir,
            currentFilesOnDiskList,
            _supportedExtensions,
          );
        } else {
          print("Warning: Root folder $rootPath not found during scan.");
          // Optionally remove the root folder if it doesn't exist anymore?
          // await _collectionService.removeRootFolder(rootPath);
        }
      }
      currentFilesOnDisk =
          currentFilesOnDiskList.map((p) => pathLib.normalize(p)).toSet();
      print("Scan found ${currentFilesOnDisk.length} supported files on disk.");
    } catch (e, stackTrace) {
      print("Error during file scan or loading last state: $e\n$stackTrace");
      scanError = true;
      // Optionally emit an error state
      // emit(TrackDataError("Failed during new file check: $e"));
    }

    // Only proceed if scan didn't error out
    if (!scanError) {
      Set<String> newFiles = {};
      if (lastKnownFiles != null) {
        // 3. Compare
        newFiles = currentFilesOnDisk.difference(lastKnownFiles);
      } else {
        // 3a. First Scan Scenario
        print(
          "First scan for collection ${activeDef.name}. Saving current state.",
        );
        // Just save the current state, don't prompt on first scan
        await _collectionService.saveLastScanState(
          activeDef.id,
          currentFilesOnDisk,
        );
        _isCheckingFiles = false; // Reset flag
        return; // Exit, LoadTracks will handle showing initial files
      }

      // 4. Emit new state or save current state
      if (newFiles.isNotEmpty) {
        print("Detected ${newFiles.length} new files.");
        // Get current UI state data to pass along
        final currentTracksForState = _getTracksFromState();
        // We already fetched rootFolders above
        emit(
          NewFilesDetected(
            newFilePaths: newFiles.toList(),
            currentTracks: currentTracksForState,
            rootFolders: rootFolders, // Pass the fetched roots
          ),
        );
        print("TrackDataBloc: Emitted NewFilesDetected state.");
      } else {
        print("No new files detected.");
        // Save the current state as the last known state since scan was successful
        // and no new files were found (or it was the first scan handled above).
        await _collectionService.saveLastScanState(
          activeDef.id,
          currentFilesOnDisk,
        );
      }
    } // End if(!scanError)

    _isCheckingFiles = false; // Reset flag in all cases before exiting
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

  List<Track> _applyFilters(
    List<Track> allTracks,
    String searchQuery,
    int? minRating,
  ) {
    List<Track> filtered = allTracks;

    if (searchQuery.isNotEmpty) {
      final lowerCaseQuery = searchQuery.toLowerCase();
      filtered =
          filtered.where((track) {
            return track.title.toLowerCase().contains(lowerCaseQuery) ||
                track.artist.toLowerCase().contains(lowerCaseQuery) ||
                track.album.toLowerCase().contains(lowerCaseQuery) ||
                track.comment.toLowerCase().contains(lowerCaseQuery) ||
                track.generalTags.any(
                  (tag) => tag.toLowerCase().contains(lowerCaseQuery),
                ) ||
                track.path.toLowerCase().contains(lowerCaseQuery);
          }).toList();
    }

    if (minRating != null && minRating > 0) {
      filtered = filtered.where((track) => track.rating >= minRating).toList();
    }

    return filtered;
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
