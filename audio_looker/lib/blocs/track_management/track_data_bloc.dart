// lib/blocs/track_data/track_data_bloc.dart

import 'dart:async';
import 'dart:io'; // Required for Directory operations

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as pathLib; // Use alias

// Import Services and Models
import '../../services/collection_service.dart'; // For Track, CollectionService, CollectionDefinition, CollectionType
import '../../services/waveform_processing_service.dart';
import '../waveform_processing/waveform_processing_bloc.dart';
import '../waveform_processing/waveform_processing_event.dart';

part 'track_data_event.dart';
part 'track_data_state.dart';

/// BLoC responsible for loading, filtering, searching, and managing
/// the list of tracks and root folders for the active collection.
class TrackDataBloc extends Bloc<TrackDataEvent, TrackDataState> {
  final CollectionService _collectionService;
  final WaveformProcessingService _waveformProcessingService;
  // final WaveformProcessingBloc _waveformProcessingBloc;
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

  TrackDataBloc({
    required CollectionService collectionService,
    // Add waveform dependencies
    required WaveformProcessingService waveformProcessingService,
    // required WaveformProcessingBloc waveformProcessingBloc,
  }) : _collectionService = collectionService,
       // Store waveform dependencies
       _waveformProcessingService = waveformProcessingService,
       //  _waveformProcessingBloc = waveformProcessingBloc,
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
  }

  // --- Event Handlers ---

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
      ); // Emit empty loaded state
      return;
    }

    emit(
      TrackDataLoading(
        // Preserve previous data for smoother UI
        previousTracks: _getTracksFromState(),
        previousRootFolders: _getRootFoldersFromState(),
        searchQuery: _lastSearchQuery,
        minimumRating: _lastMinimumRating,
      ),
    );

    try {
      final allTracks = await _collectionService.getAllTracks();
      final rootFolders = _collectionService.getRootFolders();
      print(
        "TrackDataBloc: Loaded ${allTracks.length} tracks and ${rootFolders.length} roots for '${activeDefinition.name}'.",
      );

      // Apply existing filters before emitting
      final filteredTracks = _applyFilters(
        allTracks,
        _lastSearchQuery,
        _lastMinimumRating,
      );

      emit(
        TrackDataLoaded(
          tracks: filteredTracks,
          rootFolders: rootFolders,
          searchQuery: _lastSearchQuery,
          minimumRating: _lastMinimumRating,
        ),
      );

      // Optionally trigger sync after initial load if desired
      // add(SyncFolders());
    } catch (e, stackTrace) {
      print("TrackDataBloc: ERROR loading tracks: $e\n$stackTrace");
      emit(TrackDataError("Failed to load tracks: ${e.toString()}"));
    }
  }

  Future<void> _onSearchTracks(
    SearchTracks event,
    Emitter<TrackDataState> emit,
  ) async {
    _lastSearchQuery = event.query; // Store the latest query

    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition == null) return; // Should have data if loaded

    // Get the base list of tracks (all tracks from service)
    // Avoid searching within an already filtered list
    List<Track> allTracks = [];
    try {
      allTracks = await _collectionService.getAllTracks();
    } catch (e) {
      print("TrackDataBloc: Error getting all tracks for search: $e");
      emit(TrackDataError("Failed to search: ${e.toString()}"));
      return;
    }

    // Apply filters (search and rating)
    final filteredTracks = _applyFilters(
      allTracks,
      _lastSearchQuery,
      _lastMinimumRating,
    );

    // Emit the loaded state with the filtered results
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

    // Get the base list of tracks
    List<Track> allTracks = [];
    try {
      allTracks = await _collectionService.getAllTracks();
    } catch (e) {
      print("TrackDataBloc: Error getting all tracks for filter: $e");
      emit(TrackDataError("Failed to apply filter: ${e.toString()}"));
      return;
    }

    // Apply filters (search and rating)
    final filteredTracks = _applyFilters(
      allTracks,
      _lastSearchQuery,
      _lastMinimumRating,
    );

    // Emit the loaded state with the filtered results
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
    // Optionally emit a specific "Syncing" state if needed
    // emit(TrackDataSyncing(...));

    try {
      final rootFolders = _collectionService.getRootFolders();
      if (rootFolders.isEmpty) {
        print("TrackDataBloc: No root folders defined for sync.");
        // If syncing state exists, emit loaded state
        // if (state is TrackDataSyncing) add(ReloadDataPreservingFilters());
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
        // Dispatch AddTracks event. This will handle adding and then reloading.
        add(AddTracks(filesToAdd));
      } else {
        print("TrackDataBloc: Sync complete. No new files found.");
        // If syncing state exists, emit loaded state
        // if (state is TrackDataSyncing) add(ReloadDataPreservingFilters());
      }
    } catch (e, stackTrace) {
      print("TrackDataBloc: ERROR during folder sync: $e\n$stackTrace");
      emit(TrackDataError("Failed to sync folders: ${e.toString()}"));
    }
  }

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

    // Keep track of tracks successfully added/found to trigger waveform processing
    final List<Track> addedOrFoundTracks = [];

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
          // *** ASSUMPTION: _collectionService.addLocalFile returns Track? ***
          final Track? addedTrack = await _collectionService.addLocalFile(
            filePath,
          );
          if (addedTrack != null) {
            addedOrFoundTracks.add(
              addedTrack,
            ); // Collect successfully added/found tracks
          }
        } catch (e) {
          print('TrackDataBloc ERROR: Failed to add file $filePath: $e');
          // Optionally collect errors to show user
        }
      }
      print(
        "[TrackDataBloc] Finished adding/checking ${event.filePaths.length} tracks in service. ${addedOrFoundTracks.length} added/found.",
      );

      // --- Trigger Waveform Processing ---
      if (addedOrFoundTracks.isNotEmpty) {
        print(
          '[TrackDataBloc] Triggering waveform processing for ${addedOrFoundTracks.length} tracks...',
        );
        // 1. Prepare data for the service (only local files with paths and IDs)
        final List<Map<String, String>> trackDataForService =
            addedOrFoundTracks
                .where(
                  (track) =>
                      !track.isUrl &&
                      track.path != null &&
                      track.path!.isNotEmpty &&
                      track.id != null,
                ) // Ensure ID is present
                // *** FIX: Convert track.id to String ***
                .map(
                  (track) => {'id': track.id!.toString(), 'path': track.path!},
                )
                .toList();

        if (trackDataForService.isNotEmpty) {
          // 2. Add tracks to the processing queue
          _waveformProcessingService.addTracksToQueue(trackDataForService);

          // 3. Notify the WaveformProcessingBloc that a batch has started
          // final List<String> trackIds =
          //     trackDataForService.map((data) => data['id']!).toList();
          // _waveformProcessingBloc.add(
          //   WaveformProcessingBatchStarted(
          //     trackIds: trackIds,
          //     totalTracks: trackDataForService.length,
          //   ),
          // );
          print(
            '[TrackDataBloc] Added ${trackDataForService.length} tracks to waveform queue.',
          );
        } else {
          print(
            '[TrackDataBloc] No valid tracks found needing waveform processing after add operation.',
          );
        }
      }
      // --- End Trigger Waveform Processing ---

      // Reload data to reflect additions, preserving filters
      add(ReloadDataPreservingFilters());
    } catch (e, stackTrace) {
      print('TrackDataBloc ERROR: Exception in _onAddTracks: $e\n$stackTrace');
      emit(TrackDataError("Failed to add tracks: ${e.toString()}"));
      // Consider reloading even on error?
      add(ReloadDataPreservingFilters());
    }
  }

  Future<void> _onUpdateTrackWaveform(
    UpdateTrackWaveform event,
    Emitter<TrackDataState> emit,
  ) async {
    if (state is TrackDataLoaded) {
      final currentState = state as TrackDataLoaded;
      final List<Track> updatedTracks = List.from(currentState.tracks);
      final trackIndex = updatedTracks.indexWhere((t) => t.id == event.trackId);

      if (trackIndex != -1) {
        // Create a new Track object with updated waveform data
        // Assuming Track model has a `copyWith` method or similar constructor
        final originalTrack = updatedTracks[trackIndex];
        updatedTracks[trackIndex] = originalTrack.copyWith(
          waveformData: event.waveformData,
          // Potentially update a flag indicating waveform presence/absence if needed
        );

        // Emit the new state with the updated track list
        emit(currentState.copyWith(tracks: updatedTracks));

        // Optional: Persist the change if waveform data should be saved immediately
        // await _collectionService.updateTrackWaveform(event.trackId, event.waveformData);
        // Consider if persistence happens here or after the whole batch
      } else {
        // Handle case where track ID is not found (log warning, etc.)
        print('Warning: Track ${event.trackId} not found for waveform update.');
      }
    }
    // If state is not TrackDataLoaded, maybe log or ignore
  }

  Future<void> _onAddTrackUrl(
    AddTrackUrl event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      emit(TrackDataError("Cannot add URL: No active collection."));
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
      await _collectionService.addUrl(event.url);
      add(ReloadDataPreservingFilters()); // Reload data
    } catch (e, stackTrace) {
      print("TrackDataBloc ERROR adding track from URL: $e\n$stackTrace");
      emit(TrackDataError("Failed to add URL: ${e.toString()}"));
    }
  }

  // In TrackDataBloc class:

  Future<void> _onRemoveTrack(
    RemoveTrack event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      print(
        "TrackDataBloc._onRemoveTrack: No active collection, skipping delete for track ${event.trackId}",
      );
      return; // No active collection
    }

    print(
      "TrackDataBloc._onRemoveTrack: Received event for track ${event.trackId}",
    ); // <<< Added Log

    final tracksBeforeDelete = _getTracksFromState();
    List<Track> optimisticTracks =
        tracksBeforeDelete.where((t) => t.id != event.trackId).toList();

    print(
      "TrackDataBloc._onRemoveTrack: Emitting optimistic state with ${optimisticTracks.length} tracks.",
    ); // <<< Added Log
    // Optimistic UI update
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
      ); // <<< Added Log
      // --- Call the service ---
      final int deletedCount = await _collectionService.deleteTrack(
        event.trackId,
      );
      // --- End Call ---
      print(
        "TrackDataBloc._onRemoveTrack: Service deleteTrack completed. Rows affected: $deletedCount",
      ); // <<< Added Log

      if (deletedCount == 0) {
        print(
          "TrackDataBloc._onRemoveTrack: Warning - Service reported 0 rows deleted for track ${event.trackId}. Data might be inconsistent.",
        );
        // Consider reloading data if deletion reported failure
        add(ReloadDataPreservingFilters());
      }
      // If successful, optimistic state is correct. No need to emit again unless error.
    } catch (e, stackTrace) {
      print(
        "TrackDataBloc._onRemoveTrack: ERROR removing track ${event.trackId} from service: $e\n$stackTrace",
      ); // <<< Added Log
      // Revert optimistic update by reloading
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
      // Reload data to show new root folder and potentially trigger sync/scan later
      add(ReloadDataPreservingFilters());
      // Optionally trigger sync immediately: add(SyncFolders());
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
      // Reload data to update root folder list
      add(ReloadDataPreservingFilters());
      // Note: Tracks from the removed root are NOT automatically deleted from the DB.
      // A separate "clean-up" mechanism might be needed if desired.
    } catch (e) {
      print('TrackDataBloc: Error removing root folder: $e');
      emit(TrackDataError('Failed to remove root folder: ${e.toString()}'));
    }
  }

  Future<void> _onReloadDataPreservingFilters(
    ReloadDataPreservingFilters event,
    Emitter<TrackDataState> emit,
  ) async {
    // This is essentially the same as _onLoadTracks but ensures
    // filters (_lastSearchQuery, _lastMinimumRating) are reapplied.
    add(LoadTracks()); // Trigger the standard load process
  }

  // --- Helper Methods ---

  List<Track> _getTracksFromState() {
    final currentState = state;
    if (currentState is TrackDataLoaded) return currentState.tracks;
    if (currentState is TrackDataLoading)
      return currentState.previousTracks ?? [];
    // Add other states if they hold track data (e.g., TrackDataSyncing)
    return [];
  }

  List<String> _getRootFoldersFromState() {
    final currentState = state;
    if (currentState is TrackDataLoaded) return currentState.rootFolders;
    if (currentState is TrackDataLoading)
      return currentState.previousRootFolders ?? [];
    // Add other states if they hold root folder data
    return [];
  }

  /// Applies search and rating filters to a list of tracks.
  List<Track> _applyFilters(
    List<Track> allTracks,
    String searchQuery,
    int? minRating,
  ) {
    List<Track> filtered = allTracks;

    // Apply search query
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
                // Consider if searching path is desired
                track.path.toLowerCase().contains(lowerCaseQuery);
          }).toList();
    }

    // Apply rating filter
    if (minRating != null && minRating > 0) {
      filtered = filtered.where((track) => track.rating >= minRating).toList();
    }

    return filtered;
  }

  /// Recursively finds audio files in a directory.
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

  Future<void> _onDeleteFolder(
    DeleteFolder event,
    Emitter<TrackDataState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) return; // No active collection

    print("TrackDataBloc: Received DeleteFolder event for ${event.folderPath}");

    // Optionally emit a loading/deleting state
    // emit(TrackDataDeletingFolder(...));

    try {
      // 1. Find all tracks within the folder (recursively) using the service
      final tracksToDelete = await _collectionService.getTracksInFolder(
        event.folderPath,
      );
      final trackIdsToDelete =
          tracksToDelete.map((t) => t.id).whereNotNull().toList();
      print(
        "Found ${trackIdsToDelete.length} tracks to delete within ${event.folderPath}",
      );

      // 2. Remove tracks from the database first
      for (final trackId in trackIdsToDelete) {
        try {
          await _collectionService.deleteTrack(trackId);
        } catch (e) {
          print("Error deleting track $trackId during folder delete: $e");
          // Optionally collect errors to report
        }
      }
      print("Finished removing ${trackIdsToDelete.length} tracks from DB.");

      // 3. Check if the deleted folder is a root folder (for local collections)
      if (activeDef.type == CollectionType.local) {
        final rootFolders = _collectionService.getRootFolders();
        final normalizedPath = event.folderPath.replaceAll('\\', '/');
        if (rootFolders.contains(normalizedPath)) {
          try {
            await _collectionService.removeRootFolder(event.folderPath);
            print("Removed root folder entry: ${event.folderPath}");
          } catch (e) {
            print("Error removing root folder ${event.folderPath} from DB: $e");
          }
        }
      }

      // 4. Emit confirmation state to ask the user about deleting files from disk
      // Only ask if the folder is not special (e.g., web links) and tracks were found
      if (event.folderPath != "Web Links" &&
          event.folderPath != "Imported Files" &&
          tracksToDelete.isNotEmpty) {
        emit(
          FolderDeletionConfirmationNeeded(
            folderPath: event.folderPath,
            folderName: pathLib.basename(
              event.folderPath,
            ), // Use basename for display
            trackCount: tracksToDelete.length,
          ),
        );
        print(
          "Emitting FolderDeletionConfirmationNeeded for ${event.folderPath}",
        );
      } else {
        // If no confirmation needed (e.g., special folder or empty), just reload
        print("No confirmation needed or folder empty. Reloading data.");
        add(ReloadDataPreservingFilters());
      }
    } catch (e, stackTrace) {
      print("TrackDataBloc ERROR during folder deletion: $e\n$stackTrace");
      emit(TrackDataError("Failed to delete folder: ${e.toString()}"));
      // Reload data even on error to reflect DB changes
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
      // Optionally emit deleting state
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
        // Emit an error state or show a snackbar via UI listener
        emit(
          TrackDataError("Failed to delete folder from disk: ${e.toString()}"),
        );
      }
    } else {
      print("Skipping deletion from disk for ${event.folderPath}");
    }

    // Always reload data after handling confirmation (or skipping)
    print("Reloading data after folder deletion process.");
    add(ReloadDataPreservingFilters());
  }
}

extension WhereNotNull<T> on Iterable<T?> {
  List<T> whereNotNull() => where((e) => e != null).cast<T>().toList();
}
