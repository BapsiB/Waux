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
    on<AddTrackFromPath>(_onAddTrackFromPath);
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
          ),
        );
      }
    });
  }

  // --- Helper methods to get current data from state ---
  // These help manage state transitions smoothly, especially for loading/error states
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

  // --- Recursive File Finder (from original CollectionBloc) ---
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
      print("TrackManagementBloc: Error scanning directory ${dir.path}: $e");
      // Decide how to handle errors during scanning (e.g., emit specific error state?)
    }
  }

  // --- Handlers ---

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
        // Type check first
        // Explicitly cast 'state' before accessing the property
        final loadingState = state as TrackManagementLoading;
        if (loadingState.currentSearchQuery != null) {
          previousSearchQuery = loadingState.currentSearchQuery;
        }
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

      // TODO: Consider triggering waveform processing here if needed, based on loaded tracks
      // _triggerWaveformProcessingIfNeeded(tracks);
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

  Future<void> _onAddRootFolder(
    AddRootFolder event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef?.type != CollectionType.local) {
      print(
        "TrackManagementBloc: Skipping AddRootFolder - only applicable to local collections.",
      );
      return; // Only local collections have manually added root folders
    }

    // Get current state data
    final currentTracks = _getTracksFromState();
    final currentTags = _getTagsFromState();
    final currentRoots = _getRootFoldersFromState();

    try {
      await _collectionService.addRootFolder(event.folderPath);
      final updatedRootFolders =
          _collectionService.getRootFolders(); // Fetch updated list

      // Emit new loaded state with updated folders
      if (state is TrackManagementLoaded || state is TrackManagementLoading) {
        final currentState = state;
        String? currentSearchQuery;
        if (currentState is TrackManagementLoaded)
          currentSearchQuery = currentState.searchQuery;
        if (currentState is TrackManagementLoading)
          currentSearchQuery = currentState.currentSearchQuery;

        emit(
          TrackManagementLoaded(
            tracks: currentTracks,
            rootFolders: updatedRootFolders,
            allTags: currentTags,
            searchQuery: currentSearchQuery,
          ),
        );
      } else {
        // If in initial or error state, transition to loaded
        emit(
          TrackManagementLoaded(
            tracks: currentTracks, // Might be empty
            rootFolders: updatedRootFolders,
            allTags: currentTags, // Might be empty
          ),
        );
      }

      // --- Automatically scan the newly added folder for tracks ---
      print(
        "TrackManagementBloc: Scanning newly added root folder: ${event.folderPath}",
      );
      List<String> foundFilePaths = [];
      final dir = Directory(event.folderPath);
      if (await dir.exists()) {
        await _findAudioFilesRecursively(
          dir,
          foundFilePaths,
          _supportedExtensions,
        );
        if (foundFilePaths.isNotEmpty) {
          print(
            "TrackManagementBloc: Found ${foundFilePaths.length} tracks in new root. Adding...",
          );
          add(AddTracksFromPaths(foundFilePaths)); // Dispatch event to add them
        } else {
          print("TrackManagementBloc: No tracks found in new root folder.");
        }
      } else {
        print(
          "TrackManagementBloc: Warning - Added root folder path does not exist: ${event.folderPath}",
        );
        emit(
          TrackManagementError(
            "Added root folder path does not exist: ${event.folderPath}",
            tracks: currentTracks,
            rootFolders:
                updatedRootFolders, // Show the added (but non-existent) folder
          ),
        );
      }
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

    try {
      await _collectionService.removeRootFolder(event.folderPath);
      final updatedRootFolders = _collectionService.getRootFolders();

      // TODO: Decide whether to remove tracks belonging ONLY to this root folder.
      // This can be complex. For now, we just remove the root folder definition.
      // Tracks will remain but might appear under "Imported" if they don't belong
      // to any other root folder, or might become inaccessible if shared.
      // A cleanup mechanism might be needed.

      if (state is TrackManagementLoaded || state is TrackManagementLoading) {
        final currentState = state;
        String? currentSearchQuery;
        if (currentState is TrackManagementLoaded)
          currentSearchQuery = currentState.searchQuery;
        if (currentState is TrackManagementLoading)
          currentSearchQuery = currentState.currentSearchQuery;

        emit(
          TrackManagementLoaded(
            tracks: currentTracks, // Keep existing tracks for now
            rootFolders: updatedRootFolders,
            allTags: currentTags,
            searchQuery: currentSearchQuery,
          ),
        );
      } else {
        emit(
          TrackManagementLoaded(
            tracks: currentTracks,
            rootFolders: updatedRootFolders,
            allTags: currentTags,
          ),
        );
      }
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

  Future<void> _onAddTrackFromPath(
    AddTrackFromPath event,
    Emitter<TrackManagementState> emit,
  ) async {
    final activeDef = _collectionService.getActiveCollection();
    if (activeDef == null) {
      emit(TrackManagementError("Cannot add track: No active collection."));
      return;
    }

    final tracksBeforeAdd = _getTracksFromState();
    final tagsBeforeAdd = _getTagsFromState();
    final rootsBeforeAdd = _getRootFoldersFromState();

    // Emit loading state immediately
    emit(
      TrackManagementLoading(
        currentTracks: tracksBeforeAdd,
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd,
        currentSearchQuery:
            (state is TrackManagementLoaded)
                ? (state as TrackManagementLoaded).searchQuery
                : null,
      ),
    );

    try {
      // Add the single file using the service
      final addedOrFoundTrack = await _collectionService.addLocalFile(
        event.filePath,
      );
      print(
        'TrackManagementBloc: Added/found track: ${addedOrFoundTrack.title}',
      );

      // Reload all tracks to reflect the addition
      add(LoadTracksForActiveCollection());

      // Start background waveform processing for the single added track
      if (!_isProcessingWaveforms && !addedOrFoundTrack.isUrl) {
        print(
          "TrackManagementBloc: Starting background waveform extraction for single file.",
        );
        _startBackgroundWaveformExtraction([addedOrFoundTrack.path]);
      }
    } catch (e, stackTrace) {
      print(
        "TrackManagementBloc: ERROR adding track from path: $e\n$stackTrace",
      );
      emit(
        TrackManagementError(
          e.toString(),
          tracks: tracksBeforeAdd, // Revert to previous state on error
          rootFolders: rootsBeforeAdd,
        ),
      );
    }
  }

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

    // Emit Loading state *before* starting the potentially long add process
    emit(
      TrackManagementLoading(
        currentTracks: tracksBeforeAdd, // Show previous tracks while adding
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd,
        currentSearchQuery:
            (state is TrackManagementLoaded)
                ? (state as TrackManagementLoaded).searchQuery
                : null,
      ),
    );

    try {
      List<Track> addedOrFoundTracks = [];
      // Step 1: Add all tracks via service
      for (final filePath in event.filePaths) {
        try {
          final track = await _collectionService.addLocalFile(filePath);
          addedOrFoundTracks.add(track);
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

      // Step 2: Reload collection fully to get the updated state
      add(LoadTracksForActiveCollection());

      // Step 3: Start background waveform processing
      final absolutePathsToProcess =
          addedOrFoundTracks
              .where((t) => !t.isUrl)
              .map(
                (t) => t.path,
              ) // Assuming addLocalFile returns tracks with absolute paths
              .toList();

      print(
        "TrackManagementBloc: Checking waveform processing for ${absolutePathsToProcess.length} files after AddTracksFromPaths.",
      );
      if (!_isProcessingWaveforms && absolutePathsToProcess.isNotEmpty) {
        print(
          "TrackManagementBloc: Starting background waveform extraction from AddTracksFromPaths.",
        );
        _startBackgroundWaveformExtraction(absolutePathsToProcess);
      } else {
        print(
          "TrackManagementBloc: Waveform processing already running or no files needed processing.",
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

    emit(
      TrackManagementLoading(
        currentTracks: tracksBeforeAdd,
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd,
        currentSearchQuery:
            (state is TrackManagementLoaded)
                ? (state as TrackManagementLoaded).searchQuery
                : null,
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

    // Optimistic UI update (optional but good UX)
    List<Track> optimisticTracks =
        tracksBeforeDelete.where((t) => t.id != event.trackId).toList();
    String? currentSearchQuery;
    if (state is TrackManagementLoaded)
      currentSearchQuery = (state as TrackManagementLoaded).searchQuery;
    if (state is TrackManagementLoading)
      currentSearchQuery = (state as TrackManagementLoading).currentSearchQuery;

    emit(
      TrackManagementLoaded(
        tracks: optimisticTracks,
        rootFolders: rootsBeforeDelete,
        allTags: tagsBeforeDelete,
        searchQuery: currentSearchQuery,
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
    if (state is TrackManagementLoaded || state is TrackManagementLoading) {
      final currentState = state;
      try {
        print("TrackManagementBloc: Refreshing global tags...");
        final allTags = await _collectionService.getAllTags();
        print("TrackManagementBloc: Refreshed ${allTags.length} global tags.");

        if (currentState is TrackManagementLoaded) {
          emit(currentState.copyWith(allTags: allTags));
        } else if (currentState is TrackManagementLoading) {
          emit(
            TrackManagementLoading(
              currentTracks: currentState.currentTracks,
              currentRootFolders: currentState.currentRootFolders,
              currentAllTags: allTags, // Update tags in loading state
              currentSearchQuery: currentState.currentSearchQuery,
            ),
          );
        }
      } catch (e) {
        print('TrackManagementBloc Error refreshing global tags: $e');
        // Optionally emit error or just log
      }
    } else {
      // If initial or error state, load tags and potentially transition to loaded
      try {
        emit(TrackManagementLoading()); // Indicate loading
        final allTags = await _collectionService.getAllTags();
        // Need tracks and roots too, maybe trigger LoadTracksForActiveCollection instead?
        // For now, emit loaded with only tags (might be incomplete state)
        emit(
          TrackManagementLoaded(tracks: [], rootFolders: [], allTags: allTags),
        );
      } catch (e) {
        emit(TrackManagementError("Failed to load global tags: $e"));
      }
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
          emit(currentState.copyWith(currentAllTags: updatedAllTags));
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
        // if the deleted tag was used there. This requires iterating or a specific service call.
        // For now, just update the global list and the UI will eventually reflect changes.
        // Consider reloading tracks if immediate consistency is crucial.
        // add(LoadTracksForActiveCollection()); // Uncomment to force refresh

        if (currentState is TrackManagementLoaded) {
          emit(currentState.copyWith(allTags: updatedAllTags));
        } else if (currentState is TrackManagementLoading) {
          emit(currentState.copyWith(currentAllTags: updatedAllTags));
        }
        print(
          "TrackManagementBloc: Deleted global tag definition '${event.tagName}'. Tracks may need refresh.",
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
          emit(currentState.copyWith(currentAllTags: updatedAllTags));
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

  // --- Waveform Extraction Logic (Moved from CollectionBloc) ---
  // TODO: Review if this should live in CollectionService instead
  Future<void> _startBackgroundWaveformExtraction(
    List<String> absoluteFilePaths,
  ) async {
    if (_isProcessingWaveforms) {
      print(
        'TrackManagementBloc WAVEFORM: Already processing waveforms, skipping',
      );
      return;
    }
    _isProcessingWaveforms = true;
    print(
      'TrackManagementBloc WAVEFORM: Starting extraction for ${absoluteFilePaths.length} files',
    );

    try {
      await _ensureAudioServiceInitialized(); // Ensure AudioService is ready

      for (int i = 0; i < absoluteFilePaths.length; i++) {
        final filePath = absoluteFilePaths[i];
        final fileName = pathLib.basename(filePath);
        print(
          'TrackManagementBloc WAVEFORM: Processing file ${i + 1}/${absoluteFilePaths.length}: $fileName',
        );

        try {
          // Get track ID from service using the absolute path
          final track = await _collectionService.getTrackByPath(filePath);
          if (track?.id != null) {
            print(
              'TrackManagementBloc WAVEFORM: Found track ID: ${track!.id} for file: $fileName',
            );
            // Extract and update waveform data
            final success = await _extractWaveformData(track.id!, filePath);
            print(
              'TrackManagementBloc WAVEFORM: Extraction ${success ? "succeeded" : "failed"} for $fileName',
            );

            // --- Update UI Optimistically (or reload) ---
            if (success && state is TrackManagementLoaded) {
              // Fetch the single updated track
              final updatedTrack = await _collectionService.getTrack(track.id!);
              if (updatedTrack != null) {
                final currentState = state as TrackManagementLoaded;
                // Update the track list in the current state
                final newTrackList =
                    currentState.tracks.map((t) {
                      return t.id == updatedTrack.id ? updatedTrack : t;
                    }).toList();
                emit(currentState.copyWith(tracks: newTrackList));
                print(
                  'TrackManagementBloc WAVEFORM: Updated UI for track ${track.id}',
                );
              }
            }
            // --- End UI Update ---
          } else {
            print(
              'TrackManagementBloc WAVEFORM: Could not find track ID for $fileName',
            );
          }
        } catch (e) {
          print(
            'TrackManagementBloc WAVEFORM ERROR: Exception processing $fileName: $e',
          );
        }
        // Add a small delay between processing files to avoid overwhelming system? Optional.
        // await Future.delayed(const Duration(milliseconds: 50));
      }
      print(
        'TrackManagementBloc WAVEFORM: Completed extraction loop for all files',
      );
    } catch (e) {
      print(
        'TrackManagementBloc WAVEFORM ERROR: Exception in background extraction: $e',
      );
    } finally {
      _isProcessingWaveforms = false;
      print('TrackManagementBloc WAVEFORM: Processing finished.');
    }
  }

  Future<bool> _extractWaveformData(
    int trackId,
    String absoluteFilePath,
  ) async {
    print(
      'TrackManagementBloc EXTRACT: Starting for track $trackId: ${pathLib.basename(absoluteFilePath)}',
    );
    try {
      await _ensureAudioServiceInitialized();

      // Use AudioService to get waveform data
      // This assumes AudioService.loadAudio triggers extraction or loads from cache
      // And the waveform data becomes available via waveformStream or a getter.
      // We might need a more direct way to request extraction if loadAudio doesn't fit.

      // Option A: Rely on loadAudio triggering extraction
      // await _audioService.loadAudio(absoluteFilePath, isUrl: false); // Might trigger extraction
      // List<double>? waveformData = _audioService.waveformData; // Check if available immediately

      // Option B: A dedicated extraction method in AudioService (Preferred)
      // Let's assume AudioService has a method like this:
      // List<double>? waveformData = await _audioService.extractAndGetWaveform(absoluteFilePath);

      // --- Temporary Simulation (Replace with actual call to AudioService) ---
      // Simulate getting waveform via loadAudio and stream
      await _audioService.loadAudio(absoluteFilePath, isUrl: false);
      final completer = Completer<List<double>?>();
      StreamSubscription? sub;
      sub = _audioService.waveformStream.listen((data) {
        if (!completer.isCompleted) {
          completer.complete(data);
          sub?.cancel();
        }
      });
      // Timeout to prevent waiting forever
      Future.delayed(Duration(seconds: 15), () {
        // Reduced timeout
        if (!completer.isCompleted) {
          print(
            "TrackManagementBloc EXTRACT: Timeout waiting for waveform data for track $trackId",
          );
          completer.complete(null);
          sub?.cancel();
        }
      });
      final waveformData = await completer.future;
      // --- End Simulation ---

      if (waveformData != null && waveformData.isNotEmpty) {
        await _updateTrackWithWaveform(
          trackId,
          waveformData,
        ); // Update DB via CollectionService
        return true;
      } else {
        print(
          "TrackManagementBloc EXTRACT: No waveform data received for track $trackId",
        );
        return false;
      }
    } catch (e) {
      print(
        'TrackManagementBloc EXTRACT ERROR: Exception for track $trackId: $e',
      );
      return false;
    }
  }

  Future<void> _updateTrackWithWaveform(
    int trackId,
    List<double> waveformData,
  ) async {
    print(
      'TrackManagementBloc UPDATE DB: Saving waveform data for track $trackId',
    );
    // Get the existing track data (relative path) from CollectionService
    final track = await _collectionService.getTrack(
      trackId,
    ); // This should return resolved path
    if (track != null) {
      // Update the track using CollectionService's update method
      // The service's updateTrack handles preparing the path (making it relative if needed)
      await _collectionService.updateTrack(
        track.copyWith(waveformData: waveformData),
      );
      print(
        'TrackManagementBloc UPDATE DB: Successfully saved waveform data for track $trackId',
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
