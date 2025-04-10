// lib/blocs/track_management/track_management_bloc.dart

import 'dart:async';
import 'dart:io'; // Required for Directory operations

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as pathLib; // Use alias

// Import Services and Models
import '../../services/collection_service.dart'; // For Track, Tag, CollectionService, CollectionDefinition, CollectionType
import '../../services/audio_service.dart'; // For waveform extraction

part 'track_management_event.dart';
part 'track_management_state.dart';

class TrackManagementBloc
    extends Bloc<TrackManagementEvent, TrackManagementState> {
  final CollectionService _collectionService;
  // Keep AudioService if waveform logic remains here
  // TODO: Review if AudioService is truly needed here or if CollectionService should handle waveform updates
  final AudioService _audioService = AudioService();
  bool _isProcessingWaveforms = false;
  bool _audioServiceInitialized = false; // Should be managed centrally

  // Define supported extensions (consider making this configurable later)
  final List<String> _supportedExtensions = [
    'mp3',
    'wav',
    'ogg',
    'm4a',
    'aac',
    'flac',
  ];

  TrackManagementBloc(this._collectionService)
    : super(TrackManagementInitial()) {
    // Register Handlers for Track/Metadata/Folder Events
    on<LoadTracksForActiveCollection>(_onLoadTracksForActiveCollection);
    // on<AddTrackFromPath>(_onAddTrackFromPath);
    on<AddTracksFromPaths>(_onAddTracksFromPaths);
    on<AddTrackFromUrl>(_onAddTrackFromUrl);
    on<RemoveTrack>(_onRemoveTrack);
    on<SearchTracks>(_onSearchTracks);
    on<UpdateTrackRating>(_onUpdateTrackRating);
    on<UpdateTrackComment>(_onUpdateTrackComment);
    on<AddTrackGeneralTag>(_onAddTrackGeneralTag);
    on<RemoveTrackGeneralTag>(_onRemoveTrackGeneralTag);
    on<AddRootFolder>(_onAddRootFolder);
    on<RemoveRootFolder>(_onRemoveRootFolder);
    on<LoadAllTags>(_onLoadAllTags);
    on<CreateGeneralTag>(_onCreateGeneralTag);
    on<DeleteGeneralTag>(_onDeleteGeneralTag);
    on<SetGeneralTagColor>(_onSetGeneralTagColor);
    on<ImportCollectionFromFile>(_onImportCollectionFromFile);
    on<ExportCollectionToFile>(_onExportCollectionToFile);
    on<SyncActiveCollectionFolders>(_onSyncActiveCollectionFolders);
    on<SetMinimumRatingFilter>(_onSetMinimumRatingFilter);

    // Listen to CollectionService loading state if needed (optional)
    _collectionService.loadingStream.listen((isLoading) {
      // This might be too broad, consider more specific loading states
      if (isLoading && state is TrackManagementLoaded) {
        final currentState = state as TrackManagementLoaded;
        emit(
          TrackManagementLoading(
            // Preserve current data while loading
            currentTracks: currentState.tracks,
            currentAllTags: currentState.allTags,
            currentRootFolders: currentState.rootFolders,
            currentSearchQuery:
                currentState.searchQuery, // Preserve search query
          ),
        );
      }
    });
  }

  // --- Helper methods to get current data from state ---
  List<Track> _getTracksFromState() {
    final currentState = state;
    if (currentState is TrackManagementLoaded) return currentState.tracks;
    if (currentState is TrackManagementLoading)
      return currentState.currentTracks ?? [];
    if (currentState is TrackManagementError) return currentState.tracks ?? [];
    return [];
  }

  List<Tag> _getTagsFromState() {
    final currentState = state;
    if (currentState is TrackManagementLoaded) return currentState.allTags;
    if (currentState is TrackManagementLoading)
      return currentState.currentAllTags ?? [];
    if (currentState is TrackManagementError)
      return []; // Tags might not be relevant on error?
    return [];
  }

  List<String> _getRootFoldersFromState() {
    final currentState = state;
    if (currentState is TrackManagementLoaded) return currentState.rootFolders;
    if (currentState is TrackManagementLoading)
      return currentState.currentRootFolders ?? [];
    if (currentState is TrackManagementError)
      return currentState.rootFolders ?? [];
    return [];
  }

  // --- Recursive File Finder ---
  Future<void> _findAudioFilesRecursively(
    Directory dir,
    List<String> audioFilePaths,
    List<String> supportedExtensions,
  ) async {
    try {
      await for (final entity in dir.list(
        recursive: false, // Scan one level at a time
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
          // Recurse into subdirectories
          await _findAudioFilesRecursively(
            Directory(entity.path),
            audioFilePaths,
            supportedExtensions,
          );
        }
      }
    } catch (e) {
      print("TrackManagementBloc: Error scanning directory ${dir.path}: $e");
      // Decide how to handle errors during scanning (e.g., emit specific error state?)
    }
  }

  Future<void> _onSetMinimumRatingFilter(
    SetMinimumRatingFilter event,
    Emitter<TrackManagementState> emit,
  ) async {
    final currentState = state; // Capture current state
    if (currentState is TrackManagementLoaded) {
      emit(currentState.copyWith(minimumRating: event.rating));
    } else if (currentState is TrackManagementLoading) {
      // Preserve other loading state data
      emit(currentState.copyWith(currentMinimumRating: event.rating));
    } else if (currentState is TrackManagementProcessingWaveforms) {
      // Preserve other processing state data
      emit(currentState.copyWith(minimumRating: event.rating));
    }
    // No need to reload tracks; filtering happens based on this state value
    print("TrackManagementBloc: Set minimum rating filter to ${event.rating}");
  }

  Future<void> _onLoadTracksForActiveCollection(
    LoadTracksForActiveCollection event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition == null) {
      print(
        "TrackManagementBloc: Cannot load tracks, no active collection set in service.",
      );
      emit(
        TrackManagementInitial(),
      ); // Or a specific 'NoCollectionActive' state
      return;
    }

    emit(
      TrackManagementLoading(
        // Show loading, preserving previous data if available
        currentTracks: _getTracksFromState(),
        currentAllTags: _getTagsFromState(),
        currentRootFolders: _getRootFoldersFromState(),
        currentSearchQuery:
            (state is TrackManagementLoaded)
                ? (state as TrackManagementLoaded).searchQuery
                : (state is TrackManagementLoading
                    ? (state as TrackManagementLoading).currentSearchQuery
                    : null), // Preserve search
      ),
    );

    try {
      final tracks = await _collectionService.getAllTracks();
      final rootFolders =
          _collectionService
              .getRootFolders(); // Get roots for the active collection
      final allTags = await _collectionService.getAllTags(); // Global tags
      print(
        "TrackManagementBloc: Loaded ${tracks.length} tracks, ${rootFolders.length} roots, ${allTags.length} tags for collection '${activeDefinition.name}'.",
      );

      String? previousSearchQuery;
      if (state is TrackManagementLoaded) {
        previousSearchQuery = (state as TrackManagementLoaded).searchQuery;
      } else if (state is TrackManagementLoading) {
        previousSearchQuery =
            (state as TrackManagementLoading).currentSearchQuery;
      }

      emit(
        TrackManagementLoaded(
          tracks: tracks,
          rootFolders: rootFolders,
          allTags: allTags,
          searchQuery:
              previousSearchQuery, // Preserve search query if it existed
        ),
      );

      // Trigger waveform processing for tracks missing data
      final tracksNeedingWaveform =
          tracks
              .where(
                (t) =>
                    !t.isUrl &&
                    (t.waveformData == null || t.waveformData!.isEmpty),
              )
              .toList();
      if (tracksNeedingWaveform.isNotEmpty && !_isProcessingWaveforms) {
        print(
          "TrackManagementBloc: Triggering waveform processing for ${tracksNeedingWaveform.length} tracks after load.",
        );
        _startBackgroundWaveformExtraction(
          tracksNeedingWaveform.map((t) => t.path).toList(),
        );
      }
    } catch (e, stackTrace) {
      print(
        "TrackManagementBloc: ERROR loading collection data: $e\n$stackTrace",
      );
      emit(
        TrackManagementError(
          "Failed to load collection data: ${e.toString()}",
          // Preserve previous state data on error if possible
          tracks: _getTracksFromState(),
          rootFolders: _getRootFoldersFromState(),
        ),
      );
    }
  }

  // --- Handler for Syncing Folders (MODIFIED) ---
  Future<void> _onSyncActiveCollectionFolders(
    SyncActiveCollectionFolders event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition == null) {
      print("TrackManagementBloc: Skipping folder sync, no active collection.");
      return;
    }

    // --- REMOVED THIS CHECK to allow sync for SHARED collections ---
    // if (activeDefinition.type != CollectionType.local) {
    //   print("TrackManagementBloc: Skipping folder sync for non-local collection.");
    //   return;
    // }
    // --- END REMOVED CHECK ---

    print(
      "TrackManagementBloc: Starting folder sync for '${activeDefinition.name}'.",
    );
    // Optionally emit a specific "Syncing" state if needed
    // emit(TrackManagementSyncing(...)); // Consider adding this state

    try {
      // 1. Get all root folders defined for this collection
      // This works for both local (multiple) and shared (single)
      final rootFolders = _collectionService.getRootFolders();
      if (rootFolders.isEmpty) {
        print("TrackManagementBloc: No root folders defined for sync.");
        return;
      }

      // 2. Scan all root folders to find all audio files on the filesystem
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
            "TrackManagementBloc: Root folder '$rootPath' does not exist during sync.",
          );
        }
      }
      print(
        "TrackManagementBloc: Found ${filesOnDisk.length} files on disk across ${rootFolders.length} root(s).",
      );

      // 3. Get all tracks currently in the database for this collection
      // The paths returned by getAllTracks() are already resolved by the service.
      final tracksInDb = await _collectionService.getAllTracks();
      final Set<String> pathsInDb =
          tracksInDb
              .where((t) => !t.isUrl) // Exclude URLs
              .map(
                (t) => pathLib.normalize(t.path),
              ) // Normalize the resolved path
              .toSet();
      print(
        "TrackManagementBloc: Found ${pathsInDb.length} local tracks in DB.",
      );

      // 4. Compare and find files on disk that are NOT in the DB
      final Set<String> normalizedFilesOnDisk =
          filesOnDisk
              .map((p) => pathLib.normalize(p)) // Normalize disk paths
              .toSet();

      final List<String> filesToAdd =
          normalizedFilesOnDisk
              .where((diskPath) => !pathsInDb.contains(diskPath))
              .toList();

      // 5. Dispatch AddTracksFromPaths for the missing files
      if (filesToAdd.isNotEmpty) {
        print(
          "TrackManagementBloc: Found ${filesToAdd.length} new files to add.",
        );
        // Dispatch event to add them. This event already handles adding to DB
        // and triggering waveform analysis via its own logic.
        add(AddTracksFromPaths(filesToAdd));
        // The AddTracksFromPaths handler will eventually emit a new Loaded state.
        // No need to emit here, let the AddTracksFromPaths handler do it.
      } else {
        print("TrackManagementBloc: No new files found to add during sync.");
        // If sync completes and nothing was added, ensure the UI isn't stuck
        // in a potential "Syncing" state (if you added one).
        // Re-emit the current loaded state if necessary.
        // Example: if (state is TrackManagementSyncing) add(LoadTracksForActiveCollection());
      }
    } catch (e, stackTrace) {
      print("TrackManagementBloc: ERROR during folder sync: $e\n$stackTrace");
      // Emit an error state, preserving current data if possible
      emit(
        TrackManagementError(
          "Failed to sync folders: ${e.toString()}",
          tracks: _getTracksFromState(),
          rootFolders: _getRootFoldersFromState(),
        ),
      );
    }
  }
  // --- End Sync Handler ---

  Future<void> _onAddRootFolder(
    AddRootFolder event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    // This check remains correct: only LOCAL collections have manually added roots
    if (activeDef?.type != CollectionType.local) {
      print(
        "TrackManagementBloc: Skipping AddRootFolder - only applicable to local collections.",
      );
      return;
    }

    // Get current state data
    final currentTracks = _getTracksFromState();
    final currentTags = _getTagsFromState();
    final currentRoots = _getRootFoldersFromState();
    final currentState =
        state; // Capture current state for search query preservation
    String? currentSearchQuery;
    if (currentState is TrackManagementLoaded) {
      currentSearchQuery = currentState.searchQuery;
    } else if (currentState is TrackManagementLoading) {
      currentSearchQuery = currentState.currentSearchQuery;
    }

    try {
      await _collectionService.addRootFolder(event.folderPath);
      final updatedRootFolders =
          _collectionService.getRootFolders(); // Fetch updated list

      // Emit new loaded state with updated folders
      emit(
        TrackManagementLoaded(
          tracks: currentTracks,
          rootFolders: updatedRootFolders,
          allTags: currentTags,
          searchQuery: currentSearchQuery, // Preserve search query
        ),
      );

      // // --- Automatically scan the newly added folder for tracks ---
      // print(
      //   "TrackManagementBloc: Scanning newly added root folder: ${event.folderPath}",
      // );
      // List<String> foundFilePaths = [];
      // final dir = Directory(event.folderPath);
      // if (await dir.exists()) {
      //   await _findAudioFilesRecursively(
      //     dir,
      //     foundFilePaths,
      //     _supportedExtensions,
      //   );
      //   if (foundFilePaths.isNotEmpty) {
      //     print(
      //       "TrackManagementBloc: Found ${foundFilePaths.length} tracks in new root. Adding...",
      //     );
      //     add(AddTracksFromPaths(foundFilePaths)); // Dispatch event to add them
      //   } else {
      //     print("TrackManagementBloc: No tracks found in new root folder.");
      //   }
      // } else {
      //   print(
      //     "TrackManagementBloc: Warning - Added root folder path does not exist: ${event.folderPath}",
      //   );
      // Keep the loaded state, but maybe show a non-fatal warning elsewhere?
      // Or emit a specific state indicating a root folder issue?
      // For now, just log the warning.
      // }
      // --- End Auto-scan ---
    } catch (e) {
      print('TrackManagementBloc: Error adding root folder: $e');
      emit(
        TrackManagementError(
          'Failed to add root folder: ${e.toString()}',
          tracks: currentTracks,
          rootFolders: currentRoots, // Revert to old roots on error
        ),
      );
    }
  }

  Future<void> _onRemoveRootFolder(
    RemoveRootFolder event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    // This check remains correct
    if (activeDef?.type != CollectionType.local) {
      print(
        "TrackManagementBloc: Skipping RemoveRootFolder - only applicable to local collections.",
      );
      return;
    }

    // Get current state data
    final currentTracks = _getTracksFromState();
    final currentTags = _getTagsFromState();
    final currentRoots = _getRootFoldersFromState();
    final currentState = state;
    String? currentSearchQuery;
    if (currentState is TrackManagementLoaded) {
      currentSearchQuery = currentState.searchQuery;
    } else if (currentState is TrackManagementLoading) {
      currentSearchQuery = currentState.currentSearchQuery;
    }

    try {
      await _collectionService.removeRootFolder(event.folderPath);
      final updatedRootFolders = _collectionService.getRootFolders();

      // Decide whether to remove tracks belonging ONLY to this root folder.
      // This is complex. For now, we just remove the root folder definition.
      // Tracks will remain but might appear under "Imported" if they don't belong
      // to any other root folder, or might become inaccessible if shared.
      // A cleanup mechanism might be needed later.

      // TODO: Implement track cleanup logic if desired.
      // Example idea:
      // 1. Get all tracks.
      // 2. For each track, check if its path starts with the removed folderPath.
      // 3. If it does, check if it *also* starts with any *other* remaining root folder path.
      // 4. If it only belonged to the removed root, dispatch RemoveTrack(track.id).

      emit(
        TrackManagementLoaded(
          tracks: currentTracks, // Keep existing tracks for now
          rootFolders: updatedRootFolders,
          allTags: currentTags,
          searchQuery: currentSearchQuery, // Preserve search
        ),
      );
    } catch (e) {
      print('TrackManagementBloc: Error removing root folder: $e');
      emit(
        TrackManagementError(
          'Failed to remove root folder: ${e.toString()}',
          tracks: currentTracks,
          rootFolders: currentRoots, // Revert
        ),
      );
    }
  }

  // Future<void> _onAddTrackFromPath(
  //   AddTrackFromPath event,
  //   Emitter<TrackManagementState> emit,
  // ) async {
  //   final activeDef = _collectionService.getActiveCollection();
  //   if (activeDef == null) {
  //     emit(TrackManagementError("Cannot add track: No active collection."));
  //     return;
  //   }

  //   final tracksBeforeAdd = _getTracksFromState();
  //   final tagsBeforeAdd = _getTagsFromState();
  //   final rootsBeforeAdd = _getRootFoldersFromState();
  //   final currentState = state;
  //   String? currentSearchQuery;
  //   if (currentState is TrackManagementLoaded) {
  //     currentSearchQuery = currentState.searchQuery;
  //   } else if (currentState is TrackManagementLoading) {
  //     currentSearchQuery = currentState.currentSearchQuery;
  //   }

  //   // Emit loading state immediately
  //   emit(
  //     TrackManagementLoading(
  //       currentTracks: tracksBeforeAdd,
  //       currentAllTags: tagsBeforeAdd,
  //       currentRootFolders: rootsBeforeAdd,
  //       currentSearchQuery: currentSearchQuery, // Preserve search
  //     ),
  //   );

  //   try {
  //     // Add the single file using the service
  //     final addedOrFoundTrack = await _collectionService.addLocalFile(
  //       event.filePath,
  //     );
  //     print(
  //       'TrackManagementBloc: Added/found track: ${addedOrFoundTrack.title}',
  //     );

  //     // Reload all tracks to reflect the addition AND get updated waveform data if processed quickly
  //     add(LoadTracksForActiveCollection());

  //     // Start background waveform processing for the single added track
  //     // Check if waveform data is already present (might have been processed by addLocalFile)
  //     final potentiallyUpdatedTrack = await _collectionService.getTrack(
  //       addedOrFoundTrack.id!,
  //     );
  //     if (potentiallyUpdatedTrack != null &&
  //         (potentiallyUpdatedTrack.waveformData == null ||
  //             potentiallyUpdatedTrack.waveformData!.isEmpty) &&
  //         !_isProcessingWaveforms &&
  //         !potentiallyUpdatedTrack.isUrl) {
  //       print(
  //         "TrackManagementBloc: Starting background waveform extraction for single file.",
  //       );
  //       _startBackgroundWaveformExtraction([potentiallyUpdatedTrack.path]);
  //     }
  //   } catch (e, stackTrace) {
  //     print(
  //       "TrackManagementBloc: ERROR adding track from path: $e\n$stackTrace",
  //     );
  //     emit(
  //       TrackManagementError(
  //         e.toString(),
  //         tracks: tracksBeforeAdd, // Revert to previous state on error
  //         rootFolders: rootsBeforeAdd,
  //       ),
  //     );
  //   }
  // }

  Future<void> _onAddTracksFromPaths(
    AddTracksFromPaths event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      emit(TrackManagementError("Cannot add tracks: No active collection."));
      return;
    }
    print(
      "TrackManagementBloc: AddTracksFromPaths received ${event.filePaths.length} files for collection ${activeDef.name}",
    );

    final tracksBeforeAdd = _getTracksFromState();
    final tagsBeforeAdd = _getTagsFromState();
    final rootsBeforeAdd = _getRootFoldersFromState();
    final currentState = state;
    String? currentSearchQuery;
    if (currentState is TrackManagementLoaded) {
      currentSearchQuery = currentState.searchQuery;
    } else if (currentState is TrackManagementLoading) {
      currentSearchQuery = currentState.currentSearchQuery;
    }

    // Emit Loading state *before* starting the potentially long add process
    emit(
      TrackManagementLoading(
        currentTracks: tracksBeforeAdd, // Show previous tracks while adding
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd,
        currentSearchQuery: currentSearchQuery, // Preserve search
      ),
    );

    try {
      List<Track> addedOrFoundTracks = [];
      List<String> pathsForWaveformProcessing = [];

      // Step 1: Add all tracks via service
      for (final filePath in event.filePaths) {
        try {
          final track = await _collectionService.addLocalFile(filePath);
          addedOrFoundTracks.add(track);
          // Check if waveform needs processing right after adding
          if (!track.isUrl &&
              (track.waveformData == null || track.waveformData!.isEmpty)) {
            pathsForWaveformProcessing.add(track.path);
          }
        } catch (e) {
          print(
            'TrackManagementBloc ERROR: Failed to add file $filePath during AddTracksFromPaths: $e',
          );
          // Optionally collect errors
        }
      }
      print(
        "TrackManagementBloc: Finished adding/checking ${addedOrFoundTracks.length} tracks in service.",
      );

      // Step 2: Reload collection fully to get the updated state (including any waveforms processed by addLocalFile)
      add(LoadTracksForActiveCollection());

      // Step 3: Start background waveform processing for those identified earlier
      print(
        "TrackManagementBloc: Checking waveform processing for ${pathsForWaveformProcessing.length} files after AddTracksFromPaths.",
      );
      if (!_isProcessingWaveforms && pathsForWaveformProcessing.isNotEmpty) {
        print(
          "TrackManagementBloc: Starting background waveform extraction from AddTracksFromPaths.",
        );
        _startBackgroundWaveformExtraction(pathsForWaveformProcessing);
      } else if (pathsForWaveformProcessing.isNotEmpty) {
        print(
          "TrackManagementBloc: Waveform processing already running, skipping immediate start.",
        );
      } else {
        print(
          "TrackManagementBloc: No files needed waveform processing after add.",
        );
      }
    } catch (e, stackTrace) {
      print(
        'TrackManagementBloc ERROR: Exception in _onAddTracksFromPaths: $e\n$stackTrace',
      );
      emit(
        TrackManagementError(
          e.toString(),
          tracks: tracksBeforeAdd, // Revert state on error
          rootFolders: rootsBeforeAdd,
        ),
      );
    }
  }

  Future<void> _onAddTrackFromUrl(
    AddTrackFromUrl event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      emit(TrackManagementError("Cannot add URL: No active collection."));
      return;
    }

    final tracksBeforeAdd = _getTracksFromState();
    final tagsBeforeAdd = _getTagsFromState();
    final rootsBeforeAdd = _getRootFoldersFromState();
    final currentState = state;
    String? currentSearchQuery;
    if (currentState is TrackManagementLoaded) {
      currentSearchQuery = currentState.searchQuery;
    } else if (currentState is TrackManagementLoading) {
      currentSearchQuery = currentState.currentSearchQuery;
    }

    emit(
      TrackManagementLoading(
        currentTracks: tracksBeforeAdd,
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd,
        currentSearchQuery: currentSearchQuery, // Preserve search
      ),
    );

    try {
      await _collectionService.addUrl(event.url);
      add(LoadTracksForActiveCollection()); // Reload all tracks
    } catch (e, stackTrace) {
      print("TrackManagementBloc ERROR adding track from URL: $e\n$stackTrace");
      emit(
        TrackManagementError(
          e.toString(),
          tracks: tracksBeforeAdd,
          rootFolders: rootsBeforeAdd,
        ),
      );
    }
  }

  Future<void> _onRemoveTrack(
    RemoveTrack event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) return; // Should not happen if loaded

    final tracksBeforeDelete = _getTracksFromState();
    final tagsBeforeDelete = _getTagsFromState();
    final rootsBeforeDelete = _getRootFoldersFromState();
    final currentState = state;
    String? currentSearchQuery;
    if (currentState is TrackManagementLoaded) {
      currentSearchQuery = currentState.searchQuery;
    } else if (currentState is TrackManagementLoading) {
      currentSearchQuery = currentState.currentSearchQuery;
    }

    // Optimistic UI update (optional but good UX)
    List<Track> optimisticTracks =
        tracksBeforeDelete.where((t) => t.id != event.trackId).toList();

    emit(
      TrackManagementLoaded(
        tracks: optimisticTracks,
        rootFolders: rootsBeforeDelete,
        allTags: tagsBeforeDelete,
        searchQuery: currentSearchQuery, // Preserve search
      ),
    );

    try {
      await _collectionService.deleteTrack(event.trackId);
      print(
        "TrackManagementBloc: Deleted track ${event.trackId} from service.",
      );

      // If successful, the optimistic update is correct.
      // If delete fails, the error state will be emitted below, reverting.
      // Optional: Could reload here to be absolutely sure, but optimistic is often sufficient.
      // add(LoadTracksForActiveCollection());
    } catch (e, stackTrace) {
      print(
        "TrackManagementBloc ERROR removing track ${event.trackId}: $e\n$stackTrace",
      );
      // Revert optimistic update by emitting error with original tracks
      emit(
        TrackManagementError(
          "Failed to remove track: ${e.toString()}",
          tracks: tracksBeforeDelete,
          rootFolders: rootsBeforeDelete,
        ),
      );
    }
  }

  Future<void> _onSearchTracks(
    SearchTracks event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) return; // Cannot search without active collection

    // Preserve tags and root folders from current state
    final currentTags = _getTagsFromState();
    final currentRoots = _getRootFoldersFromState();

    // Show loading specifically for search? Optional.
    // emit(TrackManagementLoading(...));

    try {
      final tracks =
          event.query.isEmpty
              ? await _collectionService
                  .getAllTracks() // Get all for active collection
              : await _collectionService.searchTracks(
                event.query,
              ); // Service searches active collection

      emit(
        TrackManagementLoaded(
          tracks: tracks,
          rootFolders: currentRoots,
          allTags: currentTags,
          searchQuery:
              event.query.isEmpty ? null : event.query, // Store the query
        ),
      );
    } catch (e) {
      print("TrackManagementBloc ERROR searching tracks: $e");
      emit(
        TrackManagementError(
          e.toString(),
          tracks: _getTracksFromState(), // Revert tracks on error
          rootFolders: currentRoots,
        ),
      );
    }
  }

  // --- Metadata Update Handlers (Optimistic Updates) ---

  Future<void> _onUpdateTrackRating(
    UpdateTrackRating event,
    Emitter<TrackManagementState> emit,
  ) async {
    if (state is TrackManagementLoaded) {
      final currentState = state as TrackManagementLoaded;
      try {
        // Optimistic UI update
        final updatedTracks =
            currentState.tracks.map((track) {
              if (track.id == event.trackId) {
                return track.copyWith(rating: event.rating);
              }
              return track;
            }).toList();
        emit(
          currentState.copyWith(tracks: updatedTracks),
        ); // Emit updated state

        // Call service to update DB in the background
        await _collectionService.updateRating(event.trackId, event.rating);
        print("TrackManagementBloc: Updated rating for track ${event.trackId}");
      } catch (e) {
        print('TrackManagementBloc Error updating rating: $e');
        // Revert optimistic update on error
        emit(currentState.copyWith()); // Re-emit original state
        // Optionally emit specific error state:
        // emit(TrackManagementError("Failed to update rating: $e", tracks: currentState.tracks, rootFolders: currentState.rootFolders));
      }
    }
  }

  Future<void> _onUpdateTrackComment(
    UpdateTrackComment event,
    Emitter<TrackManagementState> emit,
  ) async {
    if (state is TrackManagementLoaded) {
      final currentState = state as TrackManagementLoaded;
      try {
        final updatedTracks =
            currentState.tracks.map((track) {
              if (track.id == event.trackId) {
                return track.copyWith(comment: event.comment);
              }
              return track;
            }).toList();
        emit(currentState.copyWith(tracks: updatedTracks));
        await _collectionService.updateComment(event.trackId, event.comment);
        print(
          "TrackManagementBloc: Updated comment for track ${event.trackId}",
        );
      } catch (e) {
        print('TrackManagementBloc Error updating comment: $e');
        emit(currentState.copyWith()); // Revert
      }
    }
  }

  Future<void> _onAddTrackGeneralTag(
    AddTrackGeneralTag event,
    Emitter<TrackManagementState> emit,
  ) async {
    if (state is TrackManagementLoaded) {
      final currentState = state as TrackManagementLoaded;
      try {
        final updatedTracks =
            currentState.tracks.map((track) {
              if (track.id == event.trackId) {
                final newTags = List<String>.from(track.generalTags);
                if (!newTags.contains(event.tag)) {
                  newTags.add(event.tag);
                }
                return track.copyWith(generalTags: newTags);
              }
              return track;
            }).toList();
        emit(currentState.copyWith(tracks: updatedTracks));
        await _collectionService.addGeneralTag(event.trackId, event.tag);
        print(
          "TrackManagementBloc: Added tag '${event.tag}' for track ${event.trackId}",
        );
      } catch (e) {
        print('TrackManagementBloc Error adding general tag: $e');
        emit(currentState.copyWith()); // Revert
      }
    }
  }

  Future<void> _onRemoveTrackGeneralTag(
    RemoveTrackGeneralTag event,
    Emitter<TrackManagementState> emit,
  ) async {
    if (state is TrackManagementLoaded) {
      final currentState = state as TrackManagementLoaded;
      try {
        final updatedTracks =
            currentState.tracks.map((track) {
              if (track.id == event.trackId) {
                final newTags = List<String>.from(track.generalTags)
                  ..remove(event.tag);
                return track.copyWith(generalTags: newTags);
              }
              return track;
            }).toList();
        emit(currentState.copyWith(tracks: updatedTracks));
        await _collectionService.removeGeneralTag(event.trackId, event.tag);
        print(
          "TrackManagementBloc: Removed tag '${event.tag}' for track ${event.trackId}",
        );
      } catch (e) {
        print('TrackManagementBloc Error removing general tag: $e');
        emit(currentState.copyWith()); // Revert
      }
    }
  }

  // --- Global Tag Handlers ---

  Future<void> _onLoadAllTags(
    LoadAllTags event,
    Emitter<TrackManagementState> emit,
  ) async {
    final currentState = state; // Capture current state

    // Get current tracks, roots, and search query to preserve them
    List<Track> currentTracks = _getTracksFromState();
    List<String> currentRoots = _getRootFoldersFromState();
    String? currentSearchQuery;
    if (currentState is TrackManagementLoaded) {
      currentSearchQuery = currentState.searchQuery;
    } else if (currentState is TrackManagementLoading) {
      currentSearchQuery = currentState.currentSearchQuery;
    }

    try {
      print("TrackManagementBloc: Refreshing global tags...");
      final allTags = await _collectionService.getAllTags();
      print("TrackManagementBloc: Refreshed ${allTags.length} global tags.");

      // Emit a new Loaded state with the updated tags and preserved other data
      emit(
        TrackManagementLoaded(
          tracks: currentTracks,
          rootFolders: currentRoots,
          allTags: allTags,
          searchQuery: currentSearchQuery,
        ),
      );
    } catch (e) {
      print('TrackManagementBloc Error refreshing global tags: $e');
      // Optionally emit error or just log
      // If emitting error, preserve existing data
      emit(
        TrackManagementError(
          "Failed to load global tags: $e",
          tracks: currentTracks,
          rootFolders: currentRoots,
        ),
      );
    }
  }

  Future<void> _onCreateGeneralTag(
    CreateGeneralTag event,
    Emitter<TrackManagementState> emit,
  ) async {
    if (state is TrackManagementLoaded || state is TrackManagementLoading) {
      final currentState = state;
      try {
        final newTag = Tag(name: event.tagName.trim(), colorValue: null);
        await _collectionService.addTag(newTag);
        final updatedAllTags =
            await _collectionService.getAllTags(); // Fetch updated list

        if (currentState is TrackManagementLoaded) {
          emit(currentState.copyWith(allTags: updatedAllTags));
        } else if (currentState is TrackManagementLoading) {
          // Preserve other loading state data
          emit(
            TrackManagementLoading(
              currentTracks: currentState.currentTracks,
              currentRootFolders: currentState.currentRootFolders,
              currentAllTags: updatedAllTags, // Update tags
              currentSearchQuery: currentState.currentSearchQuery,
            ),
          );
        }
      } catch (e) {
        print('TrackManagementBloc Error creating general tag: $e');
        // Handle error if needed
      }
    }
  }

  Future<void> _onDeleteGeneralTag(
    DeleteGeneralTag event,
    Emitter<TrackManagementState> emit,
  ) async {
    if (state is TrackManagementLoaded || state is TrackManagementLoading) {
      final currentState = state;
      try {
        await _collectionService.removeTag(event.tagName);
        final updatedAllTags = await _collectionService.getAllTags();

        // We might need to trigger an update across all tracks in the *active* collection
        // if the deleted tag was used there. Reloading tracks ensures consistency.
        add(LoadTracksForActiveCollection()); // Force refresh tracks

        // Update the global tag list in the current state type
        if (currentState is TrackManagementLoaded) {
          // Note: LoadTracksForActiveCollection will eventually emit a new Loaded state
          // so emitting here might be redundant, but can provide quicker feedback on the tag list itself.
          emit(currentState.copyWith(allTags: updatedAllTags));
        } else if (currentState is TrackManagementLoading) {
          emit(
            TrackManagementLoading(
              currentTracks: currentState.currentTracks,
              currentRootFolders: currentState.currentRootFolders,
              currentAllTags: updatedAllTags, // Update tags
              currentSearchQuery: currentState.currentSearchQuery,
            ),
          );
        }
        print(
          "TrackManagementBloc: Deleted global tag definition '${event.tagName}'. Reloading tracks.",
        );
      } catch (e) {
        print('TrackManagementBloc Error deleting general tag: $e');
      }
    }
  }

  Future<void> _onSetGeneralTagColor(
    SetGeneralTagColor event,
    Emitter<TrackManagementState> emit,
  ) async {
    if (state is TrackManagementLoaded || state is TrackManagementLoading) {
      final currentState = state;
      List<Tag> currentTags = [];
      if (currentState is TrackManagementLoaded)
        currentTags = currentState.allTags;
      if (currentState is TrackManagementLoading)
        currentTags = currentState.currentAllTags ?? [];

      try {
        // Find the tag - this assumes tag names are unique identifiers
        final tagToUpdate = currentTags.firstWhere(
          (t) => t.name == event.tagName,
          orElse: () => throw Exception("Tag not found"),
        );
        final updatedTag = Tag(
          name: tagToUpdate.name,
          colorValue: event.colorValue,
        );
        await _collectionService.updateTag(
          updatedTag,
        ); // Update in service/storage
        final updatedAllTags =
            await _collectionService.getAllTags(); // Fetch updated list

        if (currentState is TrackManagementLoaded) {
          emit(currentState.copyWith(allTags: updatedAllTags));
        } else if (currentState is TrackManagementLoading) {
          emit(
            TrackManagementLoading(
              currentTracks: currentState.currentTracks,
              currentRootFolders: currentState.currentRootFolders,
              currentAllTags: updatedAllTags, // Update tags
              currentSearchQuery: currentState.currentSearchQuery,
            ),
          );
        }
      } catch (e) {
        print('TrackManagementBloc Error setting tag color: $e');
        // Handle error
      }
    }
  }

  // --- Import/Export Handlers (Operate on Active Collection) ---

  Future<void> _onImportCollectionFromFile(
    ImportCollectionFromFile event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      emit(TrackManagementError("Cannot import: No active collection."));
      return;
    }
    emit(
      TrackManagementLoading(
        // Show loading
        currentTracks: _getTracksFromState(),
        currentAllTags: _getTagsFromState(),
        currentRootFolders: _getRootFoldersFromState(),
        currentSearchQuery:
            (state is TrackManagementLoaded)
                ? (state as TrackManagementLoaded).searchQuery
                : (state is TrackManagementLoading
                    ? (state as TrackManagementLoading).currentSearchQuery
                    : null), // Preserve search
      ),
    );
    try {
      await _collectionService.importFromFile(event.path);
      add(LoadTracksForActiveCollection()); // Reload after import
    } catch (e) {
      print("TrackManagementBloc Error importing collection: $e");
      emit(
        TrackManagementError(
          e.toString(),
          tracks: _getTracksFromState(), // Revert state
          rootFolders: _getRootFoldersFromState(),
        ),
      );
    }
  }

  Future<void> _onExportCollectionToFile(
    ExportCollectionToFile event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null || state is! TrackManagementLoaded) {
      print(
        "TrackManagementBloc: Cannot export, collection not loaded or no active collection.",
      );
      // Optionally emit an error state or just return
      return;
    }
    final currentState = state as TrackManagementLoaded;
    try {
      // Service export needs to handle resolving paths before saving
      await _collectionService.exportToFile(event.path);
      // No state change needed after export, maybe show a success message via a different mechanism (e.g., SnackBar in UI)
      print("TrackManagementBloc: Export successful to ${event.path}");
    } catch (e) {
      print("TrackManagementBloc Error exporting collection: $e");
      emit(
        TrackManagementError(
          // Emit error but keep current loaded state data
          e.toString(),
          tracks: currentState.tracks,
          rootFolders: currentState.rootFolders,
        ),
      );
    }
  }

  // --- Waveform Extraction Logic ---
  // lib/blocs/track_management/track_management_bloc.dart

  // --- Waveform Extraction Logic ---
  // --- Waveform Extraction Logic (Corrected) ---
  Future<void> _startBackgroundWaveformExtraction(
    List<String> absoluteFilePaths,
  ) async {
    // Prevent multiple concurrent processing runs
    if (_isProcessingWaveforms) {
      print(
        "TrackManagementBloc WAVEFORM: Processing already in progress. Skipping new request.",
      );
      return;
    }
    if (absoluteFilePaths.isEmpty) {
      print("TrackManagementBloc WAVEFORM: No files provided for processing.");
      return;
    }

    _isProcessingWaveforms = true;
    print(
      'TrackManagementBloc WAVEFORM: Starting background extraction for ${absoluteFilePaths.length} files.',
    );

    // --- Emit Initial Processing State ---
    // Get current state data to preserve it
    final currentStateBeforeProcessing = state;
    List<Track> tracksToShowDuringProcessing = [];
    List<Tag> tagsToShowDuringProcessing = [];
    List<String> rootsToShowDuringProcessing = [];
    String? searchToShowDuringProcessing;

    if (currentStateBeforeProcessing is TrackManagementLoaded) {
      tracksToShowDuringProcessing = currentStateBeforeProcessing.tracks;
      tagsToShowDuringProcessing = currentStateBeforeProcessing.allTags;
      rootsToShowDuringProcessing = currentStateBeforeProcessing.rootFolders;
      searchToShowDuringProcessing = currentStateBeforeProcessing.searchQuery;
    } else if (currentStateBeforeProcessing is TrackManagementLoading) {
      tracksToShowDuringProcessing =
          currentStateBeforeProcessing.currentTracks ?? [];
      tagsToShowDuringProcessing =
          currentStateBeforeProcessing.currentAllTags ?? [];
      rootsToShowDuringProcessing =
          currentStateBeforeProcessing.currentRootFolders ?? [];
      searchToShowDuringProcessing =
          currentStateBeforeProcessing.currentSearchQuery;
    }
    // Add other states if necessary

    emit(
      TrackManagementProcessingWaveforms(
        tracks: tracksToShowDuringProcessing,
        allTags: tagsToShowDuringProcessing,
        rootFolders: rootsToShowDuringProcessing,
        searchQuery: searchToShowDuringProcessing,
        processedCount: 0, // Start count at 0
        totalCount: absoluteFilePaths.length,
      ),
    );
    // --- End Emit Initial Processing State ---

    bool loopCompletedNaturally = false; // Flag to track if loop finished

    try {
      await _ensureAudioServiceInitialized();

      int attemptedCount = 0;

      for (int i = 0; i < absoluteFilePaths.length; i++) {
        // --- Check cancellation condition more robustly ---
        // Ensure the state is STILL TrackManagementProcessingWaveforms before proceeding
        if (!_isProcessingWaveforms ||
            state is! TrackManagementProcessingWaveforms) {
          print(
            "TrackManagementBloc WAVEFORM: Processing canceled or state changed (${state.runtimeType}). Exiting loop.",
          );
          loopCompletedNaturally = false; // Loop did not complete naturally
          break; // Exit the loop
        }
        // --- End cancellation check ---

        final filePath = absoluteFilePaths[i];
        final fileName = pathLib.basename(filePath);
        attemptedCount++;
        print(
          'TrackManagementBloc WAVEFORM: Processing file $attemptedCount/${absoluteFilePaths.length}: $fileName',
        );

        Track? track;
        bool success = false;
        try {
          track = await _collectionService.getTrackByPath(filePath);
          if (track?.id != null) {
            // Re-fetch track to ensure we have the latest data (including potentially updated waveform)
            final existingTrack = await _collectionService.getTrack(track!.id!);
            if (existingTrack != null &&
                !existingTrack.isUrl && // Don't process URLs
                (existingTrack.waveformData == null ||
                    existingTrack.waveformData!.isEmpty)) {
              print(
                'TrackManagementBloc WAVEFORM: Extracting for track ID: ${track.id}',
              );
              // --- Actual extraction ---
              success = await _extractWaveformData(track.id!, filePath);
              print(
                'TrackManagementBloc WAVEFORM: Extraction ${success ? "succeeded" : "failed"} for $fileName',
              );
            } else if (existingTrack != null && existingTrack.isUrl) {
              print(
                'TrackManagementBloc WAVEFORM: Skipping URL track ID: ${track.id}',
              );
              success = true; // Mark as success to update progress correctly
            } else if (existingTrack != null) {
              print(
                'TrackManagementBloc WAVEFORM: Waveform data already exists for track ID: ${track.id}. Skipping extraction.',
              );
              success = true; // Consider skip as success for UI update purpose
            } else {
              print(
                'TrackManagementBloc WAVEFORM: Could not re-fetch track ID ${track.id} after finding by path.',
              );
            }
          } else {
            print(
              'TrackManagementBloc WAVEFORM: Could not find track ID for path $fileName',
            );
          }
        } catch (e, stackTrace) {
          print(
            'TrackManagementBloc WAVEFORM ERROR: Exception processing $fileName: $e\n$stackTrace',
          );
          success = false;
        }

        // --- Update State After Each Attempt ---
        // Check state again before emitting, as it might have changed during extraction
        if (state is TrackManagementProcessingWaveforms) {
          final currentState = state as TrackManagementProcessingWaveforms;
          Track? updatedTrackData;
          if (success && track?.id != null) {
            // Re-fetch the track data ONLY if extraction was successful
            // to get the newly saved waveform data.
            updatedTrackData = await _collectionService.getTrack(track!.id!);
          }

          // Update track list optimistically ONLY IF extraction succeeded AND we got updated data
          final newTrackList =
              (success && updatedTrackData != null)
                  ? currentState.tracks.map((t) {
                    // Replace the old track data with the updated one
                    return t.id == updatedTrackData!.id ? updatedTrackData : t;
                  }).toList()
                  : currentState
                      .tracks; // Otherwise, keep the current track list

          // Emit progress update with the ATTEMPTED count
          emit(
            currentState.copyWith(
              tracks:
                  newTrackList, // Update track list with new data if available
              processedCount: attemptedCount, // Use ATTEMPTED count
            ),
          );
          // print(
          //   'TrackManagementBloc WAVEFORM: Updated Progress (Attempted: $attemptedCount/${absoluteFilePaths.length})',
          // );
        } else {
          // If state changed while processing this file, break the loop
          print(
            "TrackManagementBloc WAVEFORM: State changed during file processing ($fileName), could not emit progress. Exiting loop.",
          );
          loopCompletedNaturally = false;
          break;
        }
        // --- End Update State ---
      } // End for loop

      // If the loop finished without breaking early, set the flag
      if (attemptedCount == absoluteFilePaths.length) {
        loopCompletedNaturally = true;
      }

      print(
        'TrackManagementBloc WAVEFORM: Completed extraction loop attempts for all files. Loop completed naturally: $loopCompletedNaturally',
      );

      // *** RELOAD CONDITIONALLY: Only reload if the loop finished ***
      if (loopCompletedNaturally &&
          state is TrackManagementProcessingWaveforms) {
        print(
          'TrackManagementBloc WAVEFORM: Loop finished naturally, dispatching final LoadTracksForActiveCollection.',
        );
        // It's often better to emit the final loaded state directly from here
        // instead of dispatching another Load event, to avoid potential race conditions.
        // Fetch the final state data.
        final finalTracks = await _collectionService.getAllTracks();
        final finalRoots = _collectionService.getRootFolders();
        final finalTags = await _collectionService.getAllTags();
        final currentSearchQuery =
            (state as TrackManagementProcessingWaveforms).searchQuery;

        emit(
          TrackManagementLoaded(
            tracks: finalTracks,
            rootFolders: finalRoots,
            allTags: finalTags,
            searchQuery: currentSearchQuery,
          ),
        );
        print(
          'TrackManagementBloc WAVEFORM: Emitted final TrackManagementLoaded state.',
        );
      } else {
        print(
          'TrackManagementBloc WAVEFORM: Loop was cancelled or state changed before finishing (${state.runtimeType}). Final state emission/reload is skipped.',
        );
        // If the state is already Loaded/Error, it means another event likely took over.
      }
    } catch (e, stackTrace) {
      print(
        'TrackManagementBloc WAVEFORM ERROR: Exception during processing batch: $e\n$stackTrace',
      );
      // Emit error state, preserving data if possible
      final currentStateOnError = state;
      List<Track> tracksOnError = [];
      List<String> rootsOnError = [];
      if (currentStateOnError is TrackManagementProcessingWaveforms) {
        tracksOnError = currentStateOnError.tracks;
        rootsOnError = currentStateOnError.rootFolders;
      } else if (currentStateOnError is TrackManagementLoaded) {
        tracksOnError = currentStateOnError.tracks;
        rootsOnError = currentStateOnError.rootFolders;
      }
      emit(
        TrackManagementError(
          "Error during waveform processing: ${e.toString()}",
          tracks: tracksOnError,
          rootFolders: rootsOnError,
        ),
      );
    } finally {
      _isProcessingWaveforms = false;
      print(
        'TrackManagementBloc WAVEFORM: Background processing finished. Flag set to false.',
      );
      // *** Ensure add(LoadTracksForActiveCollection()) is NOT called here ***
    }
  } // End _startBackgroundWaveformExtraction

  // In lib/blocs/track_management/track_management_bloc.dart

  Future<bool> _extractWaveformData(
    int trackId,
    String absoluteFilePath,
  ) async {
    print(
      'TrackManagementBloc EXTRACT: Starting for track $trackId: ${pathLib.basename(absoluteFilePath)}',
    );
    try {
      await _ensureAudioServiceInitialized();

      // --- Load the audio first ---
      await _audioService.loadAudio(absoluteFilePath, isUrl: false);

      // --- *** NEW: Check AudioService directly for cached data *** ---
      final immediatelyAvailableData = _audioService.waveformData;
      if (immediatelyAvailableData != null &&
          immediatelyAvailableData.isNotEmpty) {
        print(
          "TrackManagementBloc EXTRACT: Got waveform data directly from AudioService for track $trackId (${immediatelyAvailableData.length} points)",
        );
        await _updateTrackWithWaveform(trackId, immediatelyAvailableData);
        return true; // Success, no need to listen to stream
      }
      // --- *** End New Check *** ---

      // --- Fallback to Stream Listening (if direct check failed) ---
      print(
        "TrackManagementBloc EXTRACT: No immediate data found, setting up stream listener for track $trackId",
      );
      final completer = Completer<List<double>?>();
      StreamSubscription? sub;

      // Timeout to prevent waiting forever if waveform stream doesn't emit
      final timeoutTimer = Timer(const Duration(seconds: 20), () {
        if (!completer.isCompleted) {
          print(
            "TrackManagementBloc EXTRACT: Timeout waiting for waveform data for track $trackId via stream",
          );
          completer.complete(null); // Complete with null on timeout
          sub?.cancel();
        }
      });

      sub = _audioService.waveformStream.listen(
        (data) {
          if (!completer.isCompleted) {
            // Check if data is for the correct source (optional but good practice)
            // This requires AudioService stream to perhaps emit source+data pairs
            // Or assume the stream only emits for the last loaded source.
            print(
              "TrackManagementBloc EXTRACT: Received waveform data via stream for track $trackId (${data.length} points)",
            );
            completer.complete(data);
            sub?.cancel();
            timeoutTimer.cancel(); // Cancel timeout if data received
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            print(
              "TrackManagementBloc EXTRACT: Error on waveform stream for track $trackId: $error",
            );
            completer.completeError(error); // Complete with error
            sub?.cancel();
            timeoutTimer.cancel();
          }
        },
        onDone: () {
          // Handle stream closing unexpectedly if needed
          if (!completer.isCompleted) {
            print(
              "TrackManagementBloc EXTRACT: Waveform stream closed before data received for track $trackId.",
            );
            completer.complete(
              null,
            ); // Complete with null if stream closes early
            timeoutTimer.cancel();
          }
        },
      );

      // Await the result from the stream listener or timeout
      List<double>? waveformDataFromStream;
      try {
        waveformDataFromStream = await completer.future;
      } catch (e) {
        print(
          "TrackManagementBloc EXTRACT: Error awaiting stream completer: $e",
        );
        waveformDataFromStream = null; // Treat error as no data received
      }

      if (waveformDataFromStream != null && waveformDataFromStream.isNotEmpty) {
        print(
          "TrackManagementBloc EXTRACT: Successfully processed stream data for track $trackId",
        );
        await _updateTrackWithWaveform(
          trackId,
          waveformDataFromStream,
        ); // Update DB via CollectionService
        return true;
      } else {
        print(
          "TrackManagementBloc EXTRACT: No waveform data received from stream or data was empty for track $trackId",
        );
        return false; // Failed to get data via stream
      }
    } catch (e, stackTrace) {
      print(
        'TrackManagementBloc EXTRACT ERROR: Exception for track $trackId: $e\n$stackTrace',
      );
      return false;
    }
  }

  Future<void> _updateTrackWithWaveform(
    int trackId,
    List<double> waveformData,
  ) async {
    // Get the existing track data from CollectionService
    final track = await _collectionService.getTrack(
      trackId,
    ); // This should return resolved path
    if (track != null) {
      // Update the track using CollectionService's update method
      // The service's updateTrack handles preparing the path (making it relative if needed)
      await _collectionService.updateTrack(
        track.copyWith(waveformData: waveformData),
      );
    } else {
      print(
        'TrackManagementBloc UPDATE DB ERROR: Track $trackId not found for waveform update',
      );
      // Optionally throw or handle the error
    }
  }

  Future<void> _ensureAudioServiceInitialized() async {
    // This logic might be better handled centrally (e.g., in main.dart)
    // or by making AudioService truly singleton initialized on first use.
    if (!_audioServiceInitialized) {
      print('TrackManagementBloc AUDIO: Initializing AudioService...');
      await _audioService.initialize(); // Assuming AudioService has async init
      _audioServiceInitialized = true;
      print('TrackManagementBloc AUDIO: AudioService initialized.');
    }
  }

  // --- Cleanup ---
  @override
  Future<void> close() {
    print("TrackManagementBloc closed.");
    // Cancel any ongoing stream subscriptions or timers if added
    return super.close();
  }
}
