import 'dart:async';
import 'dart:io'; // Required for Directory operations

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as pathLib; // Use alias
import 'package:path_provider/path_provider.dart'; // For local DB path
import 'package:uuid/uuid.dart'; // For generating collection IDs

// Import the UPDATED CollectionService and its models
import 'package:audio_looker/services/collection_service.dart';
// Keep AudioService import if waveform logic remains here
import 'package:audio_looker/services/audio_service.dart';

// --- Event Definitions ---

abstract class CollectionEvent extends Equatable {
  const CollectionEvent();

  @override
  List<Object?> get props => [];
}

// --- Existing Events (Largely Unchanged Signature) ---

class LoadCollection extends CollectionEvent {}

class AddTrackFromPath extends CollectionEvent {
  final String filePath;
  const AddTrackFromPath(this.filePath);
  @override
  List<Object> get props => [filePath];
}

class AddTracksFromPaths extends CollectionEvent {
  final List<String> filePaths;
  const AddTracksFromPaths(this.filePaths);
  @override
  List<Object> get props => [filePaths];
}

class AddTrackFromUrl extends CollectionEvent {
  final String url;
  const AddTrackFromUrl(this.url);
  @override
  List<Object?> get props => [url];
}

class RemoveTrack extends CollectionEvent {
  final int trackId;
  const RemoveTrack(this.trackId);
  @override
  List<Object?> get props => [trackId];
}

class SearchCollection extends CollectionEvent {
  final String query;
  const SearchCollection(this.query);
  @override
  List<Object?> get props => [query];
}

class UpdateTrackRating extends CollectionEvent {
  final int trackId;
  final int rating;
  const UpdateTrackRating(this.trackId, this.rating);
  @override
  List<Object?> get props => [trackId, rating];
}

class UpdateTrackComment extends CollectionEvent {
  final int trackId;
  final String comment;
  const UpdateTrackComment(this.trackId, this.comment);
  @override
  List<Object?> get props => [trackId, comment];
}

class AddTrackGeneralTag extends CollectionEvent {
  final int trackId;
  final String tag;
  const AddTrackGeneralTag(this.trackId, this.tag);
  @override
  List<Object?> get props => [trackId, tag];
}

class RemoveTrackGeneralTag extends CollectionEvent {
  final int trackId;
  final String tag;
  const RemoveTrackGeneralTag(this.trackId, this.tag);
  @override
  List<Object?> get props => [trackId, tag];
}

// Global Tag Events (Unchanged)
class LoadAllTags extends CollectionEvent {}

class CreateGeneralTag extends CollectionEvent {
  final String tagName;
  const CreateGeneralTag(this.tagName);
  @override
  List<Object> get props => [tagName];
}

class DeleteGeneralTag extends CollectionEvent {
  final String tagName;
  const DeleteGeneralTag(this.tagName);
  @override
  List<Object> get props => [tagName];
}

class SetGeneralTagColor extends CollectionEvent {
  final String tagName;
  final int? colorValue;
  const SetGeneralTagColor(this.tagName, this.colorValue);
  @override
  List<Object?> get props => [tagName, colorValue];
}

// Root Folder Events (Now specific to Local Collections)
class AddRootFolder extends CollectionEvent {
  final String folderPath;
  const AddRootFolder(this.folderPath);
  @override
  List<Object> get props => [folderPath];
}

class RemoveRootFolder extends CollectionEvent {
  final String folderPath;
  const RemoveRootFolder(this.folderPath);
  @override
  List<Object> get props => [folderPath];
}
// LoadRootFolders might not be needed if loaded within LoadCollection

// Import/Export Events (Operate on Active Collection)
class ImportCollectionFromFile extends CollectionEvent {
  final String path;
  const ImportCollectionFromFile(this.path);
  @override
  List<Object?> get props => [path];
}

class ExportCollectionToFile extends CollectionEvent {
  final String path;
  const ExportCollectionToFile(this.path);
  @override
  List<Object?> get props => [path];
}

// --- NEW Events for Collection Management ---

// Fetches the list of available collection definitions
class LoadCollectionList extends CollectionEvent {}

// Switches the active collection
class SwitchCollection extends CollectionEvent {
  final String collectionId; // ID of the collection definition to switch to
  const SwitchCollection(this.collectionId);
  @override
  List<Object> get props => [collectionId];
}

// Creates a new shared collection
class CreateSharedCollection extends CollectionEvent {
  final String name;
  final String rootPath; // The single root folder path
  const CreateSharedCollection({required this.name, required this.rootPath});
  @override
  List<Object> get props => [name, rootPath];
}

// Creates a new local collection
class CreateLocalCollection extends CollectionEvent {
  final String name;
  const CreateLocalCollection(this.name);
  @override
  List<Object> get props => [name];
}

// Deletes a collection definition (doesn't delete the DB file itself)
class DeleteCollection extends CollectionEvent {
  final String collectionId;
  const DeleteCollection(this.collectionId);
  @override
  List<Object> get props => [collectionId];
}

// --- State Definitions (Modified) ---

abstract class CollectionState extends Equatable {
  const CollectionState();

  @override
  List<Object?> get props => [];
}

class CollectionInitial extends CollectionState {}

// Modified: Includes active collection info and potentially the list
class CollectionLoading extends CollectionState {
  final CollectionDefinition?
  activeCollectionDefinition; // Info about collection being loaded
  final List<CollectionDefinition>?
  availableCollections; // List of all known collections
  final List<Track>?
  currentTracks; // Keep current tracks while loading new collection
  final List<Tag>? currentAllTags; // Keep current tags
  final List<String>?
  currentRootFolders; // <<< ADDED: Keep current root folders (for local collections)

  const CollectionLoading({
    this.activeCollectionDefinition,
    this.availableCollections,
    this.currentTracks,
    this.currentAllTags,
    this.currentRootFolders, // <<< ADDED to constructor
  });

  @override
  List<Object?> get props => [
    activeCollectionDefinition,
    availableCollections,
    currentTracks,
    currentAllTags,
    currentRootFolders, // <<< ADDED to props
  ];
}

// Modified: Includes active collection info and the list of available collections
class CollectionLoaded extends CollectionState {
  final CollectionDefinition
  activeCollectionDefinition; // Info about the loaded collection
  final List<CollectionDefinition>
  availableCollections; // List of all known collections
  final List<Track> tracks; // Tracks for the active collection
  final List<String> rootFolders; // Root folders (only relevant for local type)
  final List<Tag> allTags; // Global tags
  final String? searchQuery; // Active search query

  const CollectionLoaded({
    required this.activeCollectionDefinition,
    required this.availableCollections,
    required this.tracks,
    required this.rootFolders,
    required this.allTags,
    this.searchQuery,
  });

  @override
  List<Object?> get props => [
    activeCollectionDefinition,
    availableCollections,
    tracks,
    rootFolders,
    allTags,
    searchQuery,
    // Use deep equality check for lists/maps if needed
    // Consider using listEquals from foundation.dart
  ];

  CollectionLoaded copyWith({
    CollectionDefinition? activeCollectionDefinition,
    List<CollectionDefinition>? availableCollections,
    List<Track>? tracks,
    List<String>? rootFolders,
    List<Tag>? allTags,
    String? searchQuery,
    // Helper to explicitly clear search query
    bool clearSearchQuery = false,
  }) {
    return CollectionLoaded(
      activeCollectionDefinition:
          activeCollectionDefinition ?? this.activeCollectionDefinition,
      availableCollections: availableCollections ?? this.availableCollections,
      tracks: tracks ?? this.tracks,
      rootFolders: rootFolders ?? this.rootFolders,
      allTags: allTags ?? this.allTags,
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
    );
  }
}

// Modified: Includes active collection info and potentially the list
class CollectionError extends CollectionState {
  final String message;
  final CollectionDefinition?
  activeCollectionDefinition; // Collection context for the error
  final List<CollectionDefinition>?
  availableCollections; // List of all known collections
  final List<Track>? tracks; // Keep tracks on error for better UX if possible
  final List<String>? rootFolders; // <<< ADDED: Keep root folders on error too

  const CollectionError(
    this.message, {
    this.activeCollectionDefinition,
    this.availableCollections,
    this.tracks,
    this.rootFolders, // <<< ADDED to constructor
  });

  @override
  List<Object?> get props => [
    message,
    activeCollectionDefinition,
    availableCollections,
    tracks,
    rootFolders, // <<< ADDED to props
  ];
}

// --- BLoC Implementation (Modified) ---

class CollectionBloc extends Bloc<CollectionEvent, CollectionState> {
  final CollectionService _collectionService;
  // Keep AudioService if waveform logic remains here
  final AudioService _audioService = AudioService();
  bool _isProcessingWaveforms = false;
  bool _audioServiceInitialized = false;

  // Store the list of available collections definitions in the BLoC
  List<CollectionDefinition> _availableCollections = [];

  CollectionBloc(this._collectionService) : super(CollectionInitial()) {
    // --- Register Handlers for NEW Events ---
    on<LoadCollectionList>(_onLoadCollectionList);
    on<SwitchCollection>(_onSwitchCollection);
    on<CreateSharedCollection>(_onCreateSharedCollection);
    on<CreateLocalCollection>(_onCreateLocalCollection);
    on<DeleteCollection>(_onDeleteCollection);

    // --- Register Handlers for Existing Events ---
    on<LoadCollection>(
      _onLoadCollection,
    ); // Loads data for the *active* collection
    on<AddTrackFromPath>(_onAddTrackFromPath);
    on<AddTracksFromPaths>(_onAddTracksFromPaths);
    on<AddTrackFromUrl>(_onAddTrackFromUrl);
    on<RemoveTrack>(_onRemoveTrack);
    on<SearchCollection>(_onSearchCollection);
    on<UpdateTrackRating>(_onUpdateTrackRating);
    on<UpdateTrackComment>(_onUpdateTrackComment);
    on<AddTrackGeneralTag>(_onAddTrackGeneralTag);
    on<RemoveTrackGeneralTag>(_onRemoveTrackGeneralTag);
    on<ImportCollectionFromFile>(_onImportCollectionFromFile);
    on<ExportCollectionToFile>(_onExportCollectionToFile);
    on<AddRootFolder>(_onAddRootFolder); // Now checks collection type
    on<RemoveRootFolder>(_onRemoveRootFolder); // Now checks collection type
    // on<LoadRootFolders>(_onLoadRootFolders); // Removed, handled in LoadCollection
    on<LoadAllTags>(_onLoadAllTags); // Global tags
    on<CreateGeneralTag>(_onCreateGeneralTag); // Global tags
    on<DeleteGeneralTag>(_onDeleteGeneralTag); // Global tags
    on<SetGeneralTagColor>(_onSetGeneralTagColor); // Global tags

    // Listen to loading state changes from service (remains the same)
    _collectionService.loadingStream.listen((isLoading) {
      if (isLoading && state is CollectionLoaded) {
        final currentState = state as CollectionLoaded;
        // Emit loading state, preserving current context
        emit(
          CollectionLoading(
            activeCollectionDefinition: currentState.activeCollectionDefinition,
            availableCollections: currentState.availableCollections,
            currentTracks: currentState.tracks,
            currentAllTags: currentState.allTags,
            currentRootFolders:
                currentState.rootFolders, // <<< Pass current folders
          ),
        );
      }
      // Note: Need to handle transition *back* from loading if service finishes
      // This might require more sophisticated state management or service events
    });

    // Initialize AudioService (if waveform logic is here)
    // _ensureAudioServiceInitialized(); // Call this before waveform operations
  }

  // --- Helper to get current state properties safely ---
  CollectionDefinition? _getActiveDefFromState() {
    final currentState = state;
    if (currentState is CollectionLoaded)
      return currentState.activeCollectionDefinition;
    if (currentState is CollectionLoading)
      return currentState.activeCollectionDefinition;
    if (currentState is CollectionError)
      return currentState.activeCollectionDefinition;
    return null;
  }

  List<CollectionDefinition> _getAvailableCollectionsFromState() {
    final currentState = state;
    if (currentState is CollectionLoaded)
      return currentState.availableCollections;
    if (currentState is CollectionLoading)
      return currentState.availableCollections ?? [];
    if (currentState is CollectionError)
      return currentState.availableCollections ?? [];
    return _availableCollections; // Fallback to BLoC's cache
  }

  List<Track> _getTracksFromState() {
    final currentState = state;
    if (currentState is CollectionLoaded) return currentState.tracks;
    if (currentState is CollectionLoading)
      return currentState.currentTracks ?? [];
    if (currentState is CollectionError) return currentState.tracks ?? [];
    return [];
  }

  List<Tag> _getTagsFromState() {
    final currentState = state;
    if (currentState is CollectionLoaded) return currentState.allTags;
    if (currentState is CollectionLoading)
      return currentState.currentAllTags ?? [];
    // Tags usually don't cause errors, maybe keep them on error?
    if (currentState is CollectionError)
      return []; // Or return previous tags if available
    return [];
  }

  // <<< ADDED Helper for Root Folders >>>
  List<String> _getRootFoldersFromState() {
    final currentState = state;
    if (currentState is CollectionLoaded) return currentState.rootFolders;
    if (currentState is CollectionLoading)
      return currentState.currentRootFolders ?? [];
    if (currentState is CollectionError) return currentState.rootFolders ?? [];
    return [];
  }

  // --- Handlers for NEW Collection Management Events ---

  Future<void> _onLoadCollectionList(
    LoadCollectionList event,
    Emitter<CollectionState> emit,
  ) async {
    // Emit loading only if not already loaded? Or always show loading?
    // Let's keep it simple for now and just load.
    print("BLOC: Loading collection list...");
    try {
      _availableCollections =
          await _collectionService.loadCollectionDefinitions();
      print(
        "BLOC: Loaded ${_availableCollections.length} collection definitions.",
      );

      // Update the current state with the new list
      final currentState = state;
      if (currentState is CollectionLoaded) {
        emit(
          currentState.copyWith(availableCollections: _availableCollections),
        );
      } else if (currentState is CollectionLoading) {
        emit(
          CollectionLoading(
            activeCollectionDefinition: currentState.activeCollectionDefinition,
            availableCollections: _availableCollections, // Update list
            currentTracks: currentState.currentTracks,
            currentAllTags: currentState.currentAllTags,
            currentRootFolders:
                currentState.currentRootFolders, // <<< Preserve folders
          ),
        );
      } else if (currentState is CollectionError) {
        emit(
          CollectionError(
            currentState.message,
            activeCollectionDefinition: currentState.activeCollectionDefinition,
            availableCollections: _availableCollections, // Update list
            tracks: currentState.tracks,
            rootFolders: currentState.rootFolders, // <<< Preserve folders
          ),
        );
      } else {
        // If initial state, maybe emit a specific state or just hold the list internally
        // For now, just update internal list. UI needs to dispatch this early.
        print(
          "BLOC: Collection list loaded, but state is Initial. List stored internally.",
        );
      }
    } catch (e, stackTrace) {
      print("BLOC ERROR loading collection list: $e\n$stackTrace");
      // Optionally emit an error state specifically for list loading
      // emit(CollectionListError("Failed to load collection list: $e"));
      // Or update the main error state
      emit(
        CollectionError(
          "Failed to load collection list: $e",
          availableCollections: _availableCollections,
        ),
      );
    }
  }

  Future<void> _onSwitchCollection(
    SwitchCollection event,
    Emitter<CollectionState> emit,
  ) async {
    print("BLOC: Switching collection to ID: ${event.collectionId}");
    final currentCollections = _getAvailableCollectionsFromState();
    // <<< Get current folders from state BEFORE switching >>>
    final currentRootFolders = _getRootFoldersFromState();

    if (currentCollections.isEmpty) {
      // Load list first if empty
      await _onLoadCollectionList(LoadCollectionList(), emit);
      // Re-fetch after loading
      _availableCollections =
          await _collectionService.loadCollectionDefinitions();
      if (_availableCollections.isEmpty) {
        emit(
          CollectionError(
            "No collections available to switch to.",
            availableCollections: [],
          ),
        );
        return;
      }
    }

    try {
      final targetDefinition = _availableCollections.firstWhere(
        (def) => def.id == event.collectionId,
        orElse: () => throw Exception("Collection ID not found"),
      );

      // Emit Loading state, indicating which collection is being loaded
      emit(
        CollectionLoading(
          activeCollectionDefinition: targetDefinition, // Target definition
          availableCollections: _availableCollections,
          currentTracks: _getTracksFromState(), // Preserve tracks during load
          currentAllTags: _getTagsFromState(), // Preserve tags
          currentRootFolders: currentRootFolders, // <<< Preserve folders
        ),
      );

      // Tell the service to open the new database
      await _collectionService.openCollection(targetDefinition);

      // Trigger loading the actual track data for the new collection
      add(LoadCollection()); // Dispatch LoadCollection event
    } catch (e, stackTrace) {
      print("BLOC ERROR switching collection: $e\n$stackTrace");
      emit(
        CollectionError(
          "Failed to switch collection: $e",
          activeCollectionDefinition:
              _getActiveDefFromState(), // Revert to previous active?
          availableCollections: _availableCollections,
          tracks: _getTracksFromState(), // Keep previous tracks on error
          rootFolders: currentRootFolders, // <<< Keep previous folders on error
        ),
      );
    }
  }

  Future<void> _onCreateSharedCollection(
    CreateSharedCollection event,
    Emitter<CollectionState> emit,
  ) async {
    print(
      "BLOC: Creating shared collection '${event.name}' at ${event.rootPath}",
    );
    try {
      final id = const Uuid().v4();
      // Define DB path within the root folder
      // Ensure the filename is safe
      final safeName = event.name
          .replaceAll(RegExp(r'[^\w\s-]'), '_')
          .replaceAll(' ', '_');
      final dbPath = pathLib.join(event.rootPath, '_collection_$safeName.db');

      final definition = CollectionDefinition(
        id: id,
        name: event.name,
        type: CollectionType.shared,
        dbPath: dbPath,
        rootPath: event.rootPath,
      );

      // 1. Add definition to storage
      await _collectionService.addCollectionDefinition(definition);
      _availableCollections.add(definition); // Update internal list

      // 2. Open the collection (this will create the DB file if it doesn't exist)
      // We open it briefly to ensure the DB is created by sqflite's onCreate
      await _collectionService.openCollection(definition);
      await _collectionService.closeCollection(); // Close it immediately

      // 3. Emit updated list and potentially switch to the new collection
      // For now, just update the list in the current state
      final currentState = state;
      if (currentState is CollectionLoaded) {
        emit(
          currentState.copyWith(availableCollections: _availableCollections),
        );
      } else {
        // If not loaded, just update internal list and maybe emit CollectionListUpdated?
        print("Shared collection created, list updated internally.");
      }
      // Optionally, automatically switch: add(SwitchCollection(id));
    } catch (e, stackTrace) {
      print("BLOC ERROR creating shared collection: $e\n$stackTrace");
      emit(
        CollectionError(
          "Failed to create shared collection: $e",
          activeCollectionDefinition: _getActiveDefFromState(),
          availableCollections: _availableCollections,
          tracks: _getTracksFromState(),
          rootFolders: _getRootFoldersFromState(), // <<< Pass folders
        ),
      );
    }
  }

  Future<void> _onCreateLocalCollection(
    CreateLocalCollection event,
    Emitter<CollectionState> emit,
  ) async {
    print("BLOC: Creating local collection '${event.name}'");
    try {
      final id = const Uuid().v4();
      // Define DB path within app's documents directory
      final docDir = await getApplicationDocumentsDirectory();
      // Ensure the filename is safe
      final safeName = event.name
          .replaceAll(RegExp(r'[^\w\s-]'), '_')
          .replaceAll(' ', '_');
      final dbPath = pathLib.join(
        docDir.path,
        'collections',
        'local_$safeName.db',
      );

      final definition = CollectionDefinition(
        id: id,
        name: event.name,
        type: CollectionType.local,
        dbPath: dbPath,
        rootPath:
            null, // Local collections don't have a single rootPath property
      );

      // 1. Add definition to storage
      await _collectionService.addCollectionDefinition(definition);
      _availableCollections.add(definition);

      // 2. Open the collection to initialize DB
      await _collectionService.openCollection(definition);
      await _collectionService.closeCollection();

      // 3. Emit updated list
      final currentState = state;
      if (currentState is CollectionLoaded) {
        emit(
          currentState.copyWith(availableCollections: _availableCollections),
        );
      } else {
        print("Local collection created, list updated internally.");
      }
      // Optionally, automatically switch: add(SwitchCollection(id));
    } catch (e, stackTrace) {
      print("BLOC ERROR creating local collection: $e\n$stackTrace");
      emit(
        CollectionError(
          "Failed to create local collection: $e",
          activeCollectionDefinition: _getActiveDefFromState(),
          availableCollections: _availableCollections,
          tracks: _getTracksFromState(),
          rootFolders: _getRootFoldersFromState(), // <<< Pass folders
        ),
      );
    }
  }

  Future<void> _onDeleteCollection(
    DeleteCollection event,
    Emitter<CollectionState> emit,
  ) async {
    print("BLOC: Deleting collection definition ID: ${event.collectionId}");
    try {
      await _collectionService.removeCollectionDefinition(event.collectionId);
      final currentActiveDef = _getActiveDefFromState(); // Use helper
      final wasActiveDeleted = currentActiveDef?.id == event.collectionId;

      // Reload the list
      _availableCollections =
          await _collectionService.loadCollectionDefinitions();

      // If the active collection was deleted, switch to another one (e.g., first available)
      if (wasActiveDeleted) {
        print("BLOC: Active collection was deleted. Switching...");
        await _collectionService
            .closeCollection(); // Close the deleted DB connection
        if (_availableCollections.isNotEmpty) {
          add(
            SwitchCollection(_availableCollections.first.id),
          ); // Switch to first
        } else {
          // No collections left, emit an empty/error state?
          // Use a placeholder definition for the empty state
          final placeholderDef = CollectionDefinition(
            id: 'none',
            name: 'None',
            type: CollectionType.local,
            dbPath: '',
            rootPath: null,
          );
          emit(
            CollectionLoaded(
              activeCollectionDefinition: placeholderDef,
              availableCollections: [],
              tracks: [],
              rootFolders: [],
              allTags: _getTagsFromState(), // Keep global tags
            ),
          );
        }
      } else {
        // Just update the list in the current state if it wasn't the active one
        final currentState = state;
        if (currentState is CollectionLoaded) {
          emit(
            currentState.copyWith(availableCollections: _availableCollections),
          );
        } else if (currentState is CollectionLoading) {
          // <<< Handle loading state
          emit(
            CollectionLoading(
              activeCollectionDefinition:
                  currentState.activeCollectionDefinition,
              availableCollections: _availableCollections, // Update list
              currentTracks: currentState.currentTracks,
              currentAllTags: currentState.currentAllTags,
              currentRootFolders: currentState.currentRootFolders,
            ),
          );
        } else if (currentState is CollectionError) {
          // <<< Handle error state
          emit(
            CollectionError(
              currentState.message,
              activeCollectionDefinition:
                  currentState.activeCollectionDefinition,
              availableCollections: _availableCollections, // Update list
              tracks: currentState.tracks,
              rootFolders: currentState.rootFolders,
            ),
          );
        } else {
          print("Collection deleted, list updated internally.");
        }
      }
    } catch (e, stackTrace) {
      print("BLOC ERROR deleting collection: $e\n$stackTrace");
      emit(
        CollectionError(
          "Failed to delete collection: $e",
          activeCollectionDefinition: _getActiveDefFromState(),
          availableCollections:
              _availableCollections, // Show potentially outdated list on error
          tracks: _getTracksFromState(),
          rootFolders: _getRootFoldersFromState(), // <<< Pass folders
        ),
      );
    }
  }

  // --- Handlers for Existing Events (Adapting to Active Collection Context) ---

  Future<void> _onLoadCollection(
    LoadCollection event,
    Emitter<CollectionState> emit,
  ) async {
    final activeDefinition =
        _collectionService.getActiveCollection(); // Get from service
    if (activeDefinition == null) {
      print(
        "BLOC: Cannot load collection, no active collection set in service.",
      );
      // Try loading list and switching to default?
      add(LoadCollectionList());
      // TODO: Add logic to auto-select a default collection if none is active
      emit(
        CollectionError(
          "No active collection selected.",
          availableCollections: _availableCollections,
        ),
      );
      return;
    }

    // Emit loading state, ensuring we pass the *correct* active definition
    emit(
      CollectionLoading(
        activeCollectionDefinition: activeDefinition,
        availableCollections: _availableCollections, // Use BLoC's cached list
        currentTracks: _getTracksFromState(), // Preserve tracks during load
        currentAllTags: _getTagsFromState(), // Preserve tags
        currentRootFolders: _getRootFoldersFromState(), // <<< Preserve folders
      ),
    );

    try {
      // Service methods now operate on the active DB implicitly
      final tracks =
          await _collectionService
              .getAllTracks(); // Paths are resolved by service
      final rootFolders =
          _collectionService
              .getRootFolders(); // Gets roots for active collection
      final allTags = await _collectionService.getAllTags(); // Global tags

      print(
        "BLOC: Loaded ${tracks.length} tracks, ${rootFolders.length} roots, ${allTags.length} tags for collection '${activeDefinition.name}'.",
      );

      // Preserve search query if previous state was CollectionLoaded
      String? previousSearchQuery;
      if (state is CollectionLoaded) {
        previousSearchQuery = (state as CollectionLoaded).searchQuery;
      }

      emit(
        CollectionLoaded(
          activeCollectionDefinition: activeDefinition,
          availableCollections: _availableCollections,
          tracks: tracks,
          rootFolders: rootFolders,
          allTags: allTags,
          searchQuery: previousSearchQuery, // Preserve search query
        ),
      );
    } catch (e, stackTrace) {
      print("BLOC ERROR loading collection data: $e\n$stackTrace");
      emit(
        CollectionError(
          "Failed to load collection data: ${e.toString()}",
          activeCollectionDefinition: activeDefinition,
          availableCollections: _availableCollections,
          rootFolders: _getRootFoldersFromState(), // <<< Pass folders
          // Don't show tracks on error? Or show previous ones?
        ),
      );
    }
  }

  Future<void> _onAddRootFolder(
    AddRootFolder event,
    Emitter<CollectionState> emit,
  ) async {
    final activeDef = _getActiveDefFromState();
    if (activeDef?.type != CollectionType.local) {
      print(
        "BLOC: Skipping AddRootFolder - only applicable to local collections.",
      );
      // Optionally emit an error or warning state
      return;
    }
    // Ensure state is loaded or loading before proceeding
    if (state is CollectionLoaded || state is CollectionLoading) {
      final currentState = state;
      // Get current tracks and tags to preserve them
      final currentTracks = _getTracksFromState();
      final currentTags = _getTagsFromState();
      final currentAvailableCollections = _getAvailableCollectionsFromState();

      try {
        await _collectionService.addRootFolder(event.folderPath);
        final updatedRootFolders = _collectionService.getRootFolders();

        if (currentState is CollectionLoaded) {
          emit(currentState.copyWith(rootFolders: updatedRootFolders));
        } else if (currentState is CollectionLoading) {
          // Update the loading state with the new root folders
          emit(
            CollectionLoading(
              activeCollectionDefinition:
                  currentState.activeCollectionDefinition,
              availableCollections: currentState.availableCollections,
              currentTracks: currentState.currentTracks,
              currentAllTags: currentState.currentAllTags,
              currentRootFolders: updatedRootFolders, // <<< Update folders here
            ),
          );
        }
      } catch (e) {
        print('BLOC Error adding root folder: $e');
        emit(
          CollectionError(
            'Failed to add root folder: ${e.toString()}',
            activeCollectionDefinition: activeDef,
            availableCollections: currentAvailableCollections,
            tracks: currentTracks,
            rootFolders:
                _getRootFoldersFromState(), // Pass current folders on error
          ),
        );
      }
    }
  }

  Future<void> _onRemoveRootFolder(
    RemoveRootFolder event,
    Emitter<CollectionState> emit,
  ) async {
    final activeDef = _getActiveDefFromState();
    if (activeDef?.type != CollectionType.local) {
      print(
        "BLOC: Skipping RemoveRootFolder - only applicable to local collections.",
      );
      return;
    }
    if (state is CollectionLoaded || state is CollectionLoading) {
      final currentState = state;
      // Get current tracks and tags to preserve them
      final currentTracks = _getTracksFromState();
      final currentTags = _getTagsFromState();
      final currentAvailableCollections = _getAvailableCollectionsFromState();

      try {
        await _collectionService.removeRootFolder(event.folderPath);
        final updatedRootFolders = _collectionService.getRootFolders();

        if (currentState is CollectionLoaded) {
          emit(currentState.copyWith(rootFolders: updatedRootFolders));
        } else if (currentState is CollectionLoading) {
          // Update the loading state with the new root folders
          emit(
            CollectionLoading(
              activeCollectionDefinition:
                  currentState.activeCollectionDefinition,
              availableCollections: currentState.availableCollections,
              currentTracks: currentState.currentTracks,
              currentAllTags: currentState.currentAllTags,
              currentRootFolders: updatedRootFolders, // <<< Update folders here
            ),
          );
        }
      } catch (e) {
        print('BLOC Error removing root folder: $e');
        emit(
          CollectionError(
            'Failed to remove root folder: ${e.toString()}',
            activeCollectionDefinition: activeDef,
            availableCollections: currentAvailableCollections,
            tracks: currentTracks,
            rootFolders:
                _getRootFoldersFromState(), // Pass current folders on error
          ),
        );
      }
    }
  }

  Future<void> _onAddTrackFromPath(
    AddTrackFromPath event,
    Emitter<CollectionState> emit,
  ) async {
    final activeDef = _getActiveDefFromState();
    if (activeDef == null) {
      emit(
        CollectionError(
          "Cannot add track: No active collection.",
          availableCollections: _availableCollections,
        ),
      );
      return;
    }
    // Keep track of current state for potential error recovery
    final tracksBeforeAdd = _getTracksFromState();
    final tagsBeforeAdd = _getTagsFromState();
    final rootsBeforeAdd = _getRootFoldersFromState(); // <<< Get folders

    emit(
      CollectionLoading(
        activeCollectionDefinition: activeDef,
        availableCollections: _availableCollections,
        currentTracks: tracksBeforeAdd,
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd, // <<< Pass folders
      ),
    );

    try {
      // Service now handles relative/absolute path logic
      await _collectionService.addLocalFile(event.filePath);
      // Reload all tracks for the active collection
      add(LoadCollection()); // Trigger full reload
    } catch (e, stackTrace) {
      print("BLOC ERROR adding track from path: $e\n$stackTrace");
      emit(
        CollectionError(
          e.toString(),
          activeCollectionDefinition: activeDef,
          availableCollections: _availableCollections,
          tracks: tracksBeforeAdd, // Revert to tracks before failed add
          rootFolders: rootsBeforeAdd, // <<< Pass folders
        ),
      );
    }
  }

  Future<void> _onAddTrackFromUrl(
    AddTrackFromUrl event,
    Emitter<CollectionState> emit,
  ) async {
    final activeDef = _getActiveDefFromState();
    if (activeDef == null) {
      emit(
        CollectionError(
          "Cannot add URL: No active collection.",
          availableCollections: _availableCollections,
        ),
      );
      return;
    }
    final tracksBeforeAdd = _getTracksFromState();
    final tagsBeforeAdd = _getTagsFromState();
    final rootsBeforeAdd = _getRootFoldersFromState(); // <<< Get folders

    emit(
      CollectionLoading(
        activeCollectionDefinition: activeDef,
        availableCollections: _availableCollections,
        currentTracks: tracksBeforeAdd,
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd, // <<< Pass folders
      ),
    );

    try {
      await _collectionService.addUrl(event.url);
      add(LoadCollection()); // Trigger full reload
    } catch (e, stackTrace) {
      print("BLOC ERROR adding track from URL: $e\n$stackTrace");
      emit(
        CollectionError(
          e.toString(),
          activeCollectionDefinition: activeDef,
          availableCollections: _availableCollections,
          tracks: tracksBeforeAdd,
          rootFolders: rootsBeforeAdd, // <<< Pass folders
        ),
      );
    }
  }

  // --- Waveform Processing Logic (Keep for now, ensure absolute paths used) ---
  // Make sure _ensureAudioServiceInitialized is called before these are used.

  Future<void> _ensureAudioServiceInitialized() async {
    if (!_audioServiceInitialized) {
      print('AUDIO: Initializing AudioService');
      // Assuming AudioService has an async initialize method
      // await _audioService.initialize();
      _audioServiceInitialized = true;
      print('AUDIO: AudioService initialization complete');
    }
  }

  Future<void> _onAddTracksFromPaths(
    AddTracksFromPaths event,
    Emitter<CollectionState> emit,
  ) async {
    final activeDef = _getActiveDefFromState();
    if (activeDef == null) {
      emit(
        CollectionError(
          "Cannot add tracks: No active collection.",
          availableCollections: _availableCollections,
        ),
      );
      return;
    }
    print(
      "BATCH: Processing ${event.filePaths.length} files for collection ${activeDef.name}",
    );
    final tracksBeforeAdd = _getTracksFromState();
    final tagsBeforeAdd = _getTagsFromState();
    final rootsBeforeAdd = _getRootFoldersFromState(); // <<< Get folders

    emit(
      CollectionLoading(
        activeCollectionDefinition: activeDef,
        availableCollections: _availableCollections,
        currentTracks: tracksBeforeAdd,
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd, // <<< Pass folders
      ),
    );

    try {
      List<Track> addedTracks = [];
      // Step 1: Add all tracks via service (handles relative/absolute paths)
      for (final filePath in event.filePaths) {
        try {
          // addLocalFile returns the added/existing track with resolved path
          final track = await _collectionService.addLocalFile(filePath);
          addedTracks.add(track);
          print('BATCH: Added/found track: ${track.title}');
        } catch (e) {
          print('BATCH ERROR: Failed to add file $filePath: $e');
        }
      }

      // Step 2: Update UI immediately to show added tracks
      print("BATCH: Updating UI with added tracks");
      final currentTracks =
          await _collectionService
              .getAllTracks(); // Get all for active collection
      final currentRootFolders =
          _collectionService.getRootFolders(); // Refresh roots

      // Preserve search query if previous state was CollectionLoaded
      String? previousSearchQuery;
      if (state is CollectionLoaded) {
        previousSearchQuery = (state as CollectionLoaded).searchQuery;
      }

      emit(
        CollectionLoaded(
          activeCollectionDefinition: activeDef,
          availableCollections: _availableCollections,
          tracks: currentTracks,
          rootFolders: currentRootFolders, // Use updated roots
          allTags: tagsBeforeAdd, // Tags haven't changed yet
          searchQuery: previousSearchQuery, // Preserve search
        ),
      );

      // Step 3: Start background waveform processing only if not already in progress
      // Use the ABSOLUTE paths from the addedTracks list for waveform extraction
      final absolutePathsToProcess =
          addedTracks.where((t) => !t.isUrl).map((t) => t.path).toList();
      print(
        "BATCH: Checking if waveform processing can start for ${absolutePathsToProcess.length} files",
      );
      if (!_isProcessingWaveforms && absolutePathsToProcess.isNotEmpty) {
        print("BATCH: Starting background waveform extraction");
        _startBackgroundWaveformExtraction(
          absolutePathsToProcess,
        ); // Pass absolute paths
      } else {
        print(
          "BATCH: Waveform processing already in progress or no files to process, skipping",
        );
      }
    } catch (e, stackTrace) {
      print('BATCH ERROR: Exception in _onAddTracksFromPaths: $e\n$stackTrace');
      _collectionService.setLoading(false); // Ensure loading state is cleared
      emit(
        CollectionError(
          e.toString(),
          activeCollectionDefinition: activeDef,
          availableCollections: _availableCollections,
          tracks: tracksBeforeAdd,
          rootFolders: rootsBeforeAdd, // <<< Pass folders
        ),
      );
    }
  }

  Future<void> _startBackgroundWaveformExtraction(
    List<String> absoluteFilePaths,
  ) async {
    if (_isProcessingWaveforms) {
      print('WAVEFORM: Already processing waveforms, skipping');
      return;
    }
    _isProcessingWaveforms = true;
    print(
      'WAVEFORM: Starting extraction for ${absoluteFilePaths.length} files',
    );

    try {
      await _ensureAudioServiceInitialized();

      for (int i = 0; i < absoluteFilePaths.length; i++) {
        final filePath = absoluteFilePaths[i]; // This is already absolute
        final fileName = pathLib.basename(filePath);
        print(
          'WAVEFORM: Processing file ${i + 1}/${absoluteFilePaths.length}: $fileName',
        );

        try {
          // Find track ID using the absolute path
          final track = await _collectionService.getTrackByPath(filePath);
          if (track?.id != null) {
            print('WAVEFORM: Found track ID: ${track!.id} for file: $fileName');
            // Extract waveform using absolute path
            final success = await _extractWaveformData(track.id!, filePath);
            print(
              'WAVEFORM: Extraction ${success ? "succeeded" : "failed"} for $fileName',
            );

            // Update UI after each file if still on the same collection
            final currentActiveDef = _collectionService.getActiveCollection();
            // Check if the state is still CollectionLoaded AND if the active definition matches
            if (state is CollectionLoaded &&
                (state as CollectionLoaded).activeCollectionDefinition.id ==
                    currentActiveDef?.id) {
              print('WAVEFORM: Updating UI after processing file ${i + 1}');
              final updatedTracks = await _collectionService.getAllTracks();
              // Ensure state is still CollectionLoaded before emitting
              if (state is CollectionLoaded) {
                emit(
                  (state as CollectionLoaded).copyWith(tracks: updatedTracks),
                );
              }
            } else {
              print(
                'WAVEFORM: State changed or collection switched during waveform extraction for $fileName. UI not updated.',
              );
            }
          } else {
            print('WAVEFORM: Could not find track ID for $fileName');
          }
        } catch (e) {
          print('WAVEFORM ERROR: Exception processing $fileName: $e');
        }
        await Future.delayed(const Duration(milliseconds: 500)); // Pause
      }
      print('WAVEFORM: Completed extraction for all files');
    } catch (e) {
      print('WAVEFORM ERROR: Exception in background extraction: $e');
    } finally {
      _isProcessingWaveforms = false;
    }
  }

  // _extractWaveformData, _updateTrackWithWaveform remain largely the same,
  // but ensure they use the absolute path passed in.
  Future<bool> _extractWaveformData(
    int trackId,
    String absoluteFilePath,
  ) async {
    print(
      'EXTRACT: Starting for track $trackId: ${pathLib.basename(absoluteFilePath)}',
    );
    // ... (rest of the waveform extraction logic using absoluteFilePath) ...
    // Make sure loadAudio is called with the absoluteFilePath and isUrl: false
    try {
      // Ensure AudioService is ready
      await _ensureAudioServiceInitialized();
      // Assuming loadAudio triggers waveform generation/caching in AudioService
      await _audioService.loadAudio(absoluteFilePath, isUrl: false);

      // Wait for waveform data via stream or direct access (adjust based on AudioService)
      // This part depends heavily on how AudioService provides the data
      // Example using stream:
      final completer = Completer<List<double>?>();
      StreamSubscription? sub;
      sub = _audioService.waveformStream.listen((data) {
        if (!completer.isCompleted) {
          completer.complete(data);
          sub?.cancel();
        }
      });

      // Add a timeout
      Future.delayed(Duration(seconds: 60), () {
        if (!completer.isCompleted) {
          print(
            "EXTRACT: Timeout waiting for waveform data for track $trackId",
          );
          completer.complete(null);
          sub?.cancel();
        }
      });

      final waveformData = await completer.future;

      if (waveformData != null && waveformData.isNotEmpty) {
        await _updateTrackWithWaveform(trackId, waveformData);
        return true;
      } else {
        print("EXTRACT: No waveform data received for track $trackId");
        return false;
      }
    } catch (e) {
      print('EXTRACT ERROR: Exception for track $trackId: $e');
      return false;
    }
  }

  Future<void> _updateTrackWithWaveform(
    int trackId,
    List<double> waveformData,
  ) async {
    print('UPDATE: Saving waveform data for track $trackId');
    // Get track using ID (service resolves path)
    final track = await _collectionService.getTrack(trackId);
    if (track != null) {
      // Update track using service (service handles relative/absolute storage)
      await _collectionService.updateTrack(
        track.copyWith(waveformData: waveformData),
      );
      print('UPDATE: Successfully saved waveform data for track $trackId');
    } else {
      print('UPDATE ERROR: Track $trackId not found');
      throw Exception('Track not found');
    }
  }

  // --- Other Existing Handlers (Adaptations) ---

  Future<void> _onRemoveTrack(
    RemoveTrack event,
    Emitter<CollectionState> emit,
  ) async {
    final activeDef = _getActiveDefFromState();
    if (activeDef == null) return; // Should not happen if loaded

    // Capture state before delete
    final tracksBeforeDelete = _getTracksFromState();
    final availableCollectionsBeforeDelete =
        _getAvailableCollectionsFromState();
    final tagsBeforeDelete = _getTagsFromState();
    final rootsBeforeDelete = _getRootFoldersFromState(); // <<< Get folders

    // Emit loading state? Optional, delete is usually fast. Let's skip for now.
    // emit(CollectionLoading(...));

    try {
      await _collectionService.deleteTrack(event.trackId);
      print("BLOC: Deleted track ${event.trackId} from service.");

      // Refetch tracks for the current collection
      final finalTracks = await _collectionService.getAllTracks();
      // No need to refetch roots/tags unless delete operation could change them

      // Preserve search query if previous state was CollectionLoaded
      String? previousSearchQuery;
      if (state is CollectionLoaded) {
        previousSearchQuery = (state as CollectionLoaded).searchQuery;
      }

      emit(
        CollectionLoaded(
          activeCollectionDefinition: activeDef,
          availableCollections:
              availableCollectionsBeforeDelete, // Assume list didn't change
          tracks: finalTracks,
          rootFolders: rootsBeforeDelete, // Assume roots didn't change
          allTags: tagsBeforeDelete, // Assume tags didn't change
          searchQuery: previousSearchQuery, // Preserve search
        ),
      );
      print(
        "BLOC: Emitted final CollectionLoaded state after removing track ${event.trackId}",
      );
    } catch (e, stackTrace) {
      print("BLOC ERROR removing track ${event.trackId}: $e\n$stackTrace");
      emit(
        CollectionError(
          "Failed to remove track: ${e.toString()}",
          activeCollectionDefinition: activeDef,
          availableCollections: availableCollectionsBeforeDelete,
          tracks: tracksBeforeDelete, // Show tracks before failed delete
          rootFolders: rootsBeforeDelete, // <<< Pass folders
        ),
      );
    }
  }

  Future<void> _onSearchCollection(
    SearchCollection event,
    Emitter<CollectionState> emit,
  ) async {
    final activeDef = _getActiveDefFromState();
    if (activeDef == null || state is! CollectionLoaded) return;

    final currentState = state as CollectionLoaded;

    // Emit loading? Optional for search. Let's update directly.
    // emit(CollectionLoading(
    //    activeCollectionDefinition: activeDef,
    //    availableCollections: currentState.availableCollections,
    //    currentTracks: currentState.tracks,
    //    currentAllTags: currentState.allTags,
    // ));

    try {
      final tracks =
          event.query.isEmpty
              ? await _collectionService
                  .getAllTracks() // Service gets all for active collection
              : await _collectionService.searchTracks(
                event.query,
              ); // Service searches active collection

      emit(
        currentState.copyWith(
          tracks: tracks,
          searchQuery: event.query.isEmpty ? null : event.query,
          clearSearchQuery:
              event.query.isEmpty, // Explicitly clear if query is empty
          // Roots and tags remain the same during search
        ),
      );
    } catch (e) {
      print("BLOC ERROR searching collection: $e");
      emit(
        CollectionError(
          e.toString(),
          activeCollectionDefinition: activeDef,
          availableCollections: currentState.availableCollections,
          tracks: currentState.tracks, // Revert tracks on error
          rootFolders: currentState.rootFolders, // <<< Pass folders
        ),
      );
    }
  }

  Future<void> _onUpdateTrackRating(
    UpdateTrackRating event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentState = state as CollectionLoaded;
      try {
        // Call service to update DB
        await _collectionService.updateRating(event.trackId, event.rating);

        // Optimistic UI update
        final updatedTracks =
            currentState.tracks.map((track) {
              if (track.id == event.trackId) {
                return track.copyWith(rating: event.rating);
              }
              return track;
            }).toList();

        emit(currentState.copyWith(tracks: updatedTracks));
      } catch (e) {
        print('BLOC Error updating rating: $e');
        // Optionally revert or show error state
        emit(
          CollectionError(
            e.toString(),
            activeCollectionDefinition: currentState.activeCollectionDefinition,
            availableCollections: currentState.availableCollections,
            tracks: currentState.tracks, // Revert optimistic update on error
            rootFolders: currentState.rootFolders, // <<< Pass folders
          ),
        );
      }
    }
  }

  Future<void> _onUpdateTrackComment(
    UpdateTrackComment event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentState = state as CollectionLoaded;
      try {
        await _collectionService.updateComment(event.trackId, event.comment);
        final updatedTracks =
            currentState.tracks.map((track) {
              if (track.id == event.trackId) {
                return track.copyWith(comment: event.comment);
              }
              return track;
            }).toList();
        emit(currentState.copyWith(tracks: updatedTracks));
      } catch (e) {
        print('BLOC Error updating comment: $e');
        emit(
          CollectionError(
            e.toString(),
            activeCollectionDefinition: currentState.activeCollectionDefinition,
            availableCollections: currentState.availableCollections,
            tracks: currentState.tracks,
            rootFolders: currentState.rootFolders, // <<< Pass folders
          ),
        );
      }
    }
  }

  Future<void> _onAddTrackGeneralTag(
    AddTrackGeneralTag event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentState = state as CollectionLoaded;
      try {
        await _collectionService.addGeneralTag(event.trackId, event.tag);
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
      } catch (e) {
        print('BLOC Error adding general tag: $e');
        emit(
          CollectionError(
            e.toString(),
            activeCollectionDefinition: currentState.activeCollectionDefinition,
            availableCollections: currentState.availableCollections,
            tracks: currentState.tracks,
            rootFolders: currentState.rootFolders, // <<< Pass folders
          ),
        );
      }
    }
  }

  Future<void> _onRemoveTrackGeneralTag(
    RemoveTrackGeneralTag event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentState = state as CollectionLoaded;
      try {
        await _collectionService.removeGeneralTag(event.trackId, event.tag);
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
      } catch (e) {
        print('BLOC Error removing general tag: $e');
        emit(
          CollectionError(
            e.toString(),
            activeCollectionDefinition: currentState.activeCollectionDefinition,
            availableCollections: currentState.availableCollections,
            tracks: currentState.tracks,
            rootFolders: currentState.rootFolders, // <<< Pass folders
          ),
        );
      }
    }
  }

  // --- Global Tag Handlers (Unchanged) ---
  Future<void> _onLoadAllTags(
    LoadAllTags event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentState = state as CollectionLoaded;
      try {
        print("BLOC: Refreshing global tags...");
        final allTags = await _collectionService.getAllTags();
        print("BLOC: Refreshed ${allTags.length} global tags.");
        emit(currentState.copyWith(allTags: allTags));
      } catch (e) {
        print('BLOC Error refreshing global tags: $e');
        // Optionally emit error
      }
    }
  }

  Future<void> _onCreateGeneralTag(
    CreateGeneralTag event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentState = state as CollectionLoaded;
      try {
        final newTag = Tag(name: event.tagName.trim(), colorValue: null);
        await _collectionService.addTag(newTag);
        final updatedAllTags = await _collectionService.getAllTags();
        emit(currentState.copyWith(allTags: updatedAllTags));
      } catch (e) {
        print('BLOC Error creating general tag: $e');
      }
    }
  }

  Future<void> _onDeleteGeneralTag(
    DeleteGeneralTag event,
    Emitter<CollectionState> emit,
  ) async {
    // Note: Deleting a global tag definition doesn't automatically remove
    // it from tracks in *all* collections. This might need more complex logic later.
    if (state is CollectionLoaded) {
      final currentState = state as CollectionLoaded;
      try {
        await _collectionService.removeTag(event.tagName);
        final updatedAllTags = await _collectionService.getAllTags();
        // We might need to trigger an update across all tracks in the *active* collection
        // if the deleted tag was used there. For now, just update the global list.
        emit(currentState.copyWith(allTags: updatedAllTags));
        print(
          "BLOC: Deleted global tag definition '${event.tagName}'. Tracks using it may still show it until refreshed/edited.",
        );
      } catch (e) {
        print('BLOC Error deleting general tag: $e');
      }
    }
  }

  Future<void> _onSetGeneralTagColor(
    SetGeneralTagColor event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentState = state as CollectionLoaded;
      try {
        // Find the tag - this assumes tag names are unique identifiers
        final tagToUpdate = currentState.allTags.firstWhere(
          (t) => t.name == event.tagName,
        );
        final updatedTag = Tag(
          name: tagToUpdate.name,
          colorValue: event.colorValue,
        );
        await _collectionService.updateTag(updatedTag);
        final updatedAllTags = await _collectionService.getAllTags();
        emit(currentState.copyWith(allTags: updatedAllTags));
      } catch (e) {
        print('BLOC Error setting tag color: $e');
      }
    }
  }

  // --- Import/Export Handlers (Operate on Active Collection) ---
  Future<void> _onImportCollectionFromFile(
    ImportCollectionFromFile event,
    Emitter<CollectionState> emit,
  ) async {
    final activeDef = _getActiveDefFromState();
    if (activeDef == null) {
      emit(
        CollectionError(
          "Cannot import: No active collection.",
          availableCollections: _availableCollections,
        ),
      );
      return;
    }
    emit(
      CollectionLoading(
        activeCollectionDefinition: activeDef,
        availableCollections: _availableCollections,
        currentTracks: _getTracksFromState(),
        currentAllTags: _getTagsFromState(),
        currentRootFolders: _getRootFoldersFromState(), // <<< Pass folders
      ),
    );
    try {
      // TODO: Service needs updated import logic to handle relative paths if importing to shared
      await _collectionService.importFromFile(event.path);
      add(LoadCollection()); // Reload after import
    } catch (e) {
      print("BLOC Error importing collection: $e");
      emit(
        CollectionError(
          e.toString(),
          activeCollectionDefinition: activeDef,
          availableCollections: _availableCollections,
          tracks: _getTracksFromState(), // Revert state
          rootFolders: _getRootFoldersFromState(), // <<< Pass folders
        ),
      );
    }
  }

  Future<void> _onExportCollectionToFile(
    ExportCollectionToFile event,
    Emitter<CollectionState> emit,
  ) async {
    final activeDef = _getActiveDefFromState();
    if (activeDef == null || state is! CollectionLoaded) {
      // Maybe allow export even if loading? For now, require loaded state.
      print(
        "BLOC: Cannot export, collection not loaded or no active collection.",
      );
      return;
    }
    final currentState = state as CollectionLoaded;
    try {
      // Service export needs to handle resolving paths before saving
      await _collectionService.exportToFile(event.path);
      // No state change needed after export, maybe show a success message via a different mechanism
      print("BLOC: Export successful to ${event.path}");
    } catch (e) {
      print("BLOC Error exporting collection: $e");
      emit(
        CollectionError(
          e.toString(),
          activeCollectionDefinition: currentState.activeCollectionDefinition,
          availableCollections: currentState.availableCollections,
          tracks: currentState.tracks, // Preserve state on error
          rootFolders: currentState.rootFolders, // <<< Pass folders
        ),
      );
    }
  }

  // --- Cleanup ---
  @override
  Future<void> close() async {
    if (_audioServiceInitialized) {
      // await _audioService.dispose(); // Dispose if owned by BLoC
    }
    // Ensure the service's active collection is closed when BLoC closes
    await _collectionService.closeCollection();
    print("CollectionBloc closed.");
    return super.close();
  }
}
