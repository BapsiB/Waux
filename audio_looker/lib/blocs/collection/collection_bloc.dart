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
// ... (Events remain the same) ...
abstract class CollectionEvent extends Equatable {
  const CollectionEvent();
  @override
  List<Object?> get props => [];
}

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

class LoadCollectionList extends CollectionEvent {}

class SwitchCollection extends CollectionEvent {
  final String collectionId;
  const SwitchCollection(this.collectionId);
  @override
  List<Object> get props => [collectionId];
}

class CreateSharedCollection extends CollectionEvent {
  final String name;
  final String rootPath;
  const CreateSharedCollection({required this.name, required this.rootPath});
  @override
  List<Object> get props => [name, rootPath];
}

class CreateLocalCollection extends CollectionEvent {
  final String name;
  const CreateLocalCollection(this.name);
  @override
  List<Object> get props => [name];
}

class DeleteCollection extends CollectionEvent {
  final String collectionId;
  const DeleteCollection(this.collectionId);
  @override
  List<Object> get props => [collectionId];
}

// --- State Definitions (Modified) ---
// ... (States remain the same as in previous BLoC update) ...
abstract class CollectionState extends Equatable {
  const CollectionState();
  @override
  List<Object?> get props => [];
}

class CollectionInitial extends CollectionState {}

class CollectionLoading extends CollectionState {
  final CollectionDefinition? activeCollectionDefinition;
  final List<CollectionDefinition>? availableCollections;
  final List<Track>? currentTracks;
  final List<Tag>? currentAllTags;
  final List<String>? currentRootFolders;
  const CollectionLoading({
    this.activeCollectionDefinition,
    this.availableCollections,
    this.currentTracks,
    this.currentAllTags,
    this.currentRootFolders,
  });
  @override
  List<Object?> get props => [
    activeCollectionDefinition,
    availableCollections,
    currentTracks,
    currentAllTags,
    currentRootFolders,
  ];
}

class CollectionLoaded extends CollectionState {
  final CollectionDefinition activeCollectionDefinition;
  final List<CollectionDefinition> availableCollections;
  final List<Track> tracks;
  final List<String> rootFolders;
  final List<Tag> allTags;
  final String? searchQuery;
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
  ];
  CollectionLoaded copyWith({
    CollectionDefinition? activeCollectionDefinition,
    List<CollectionDefinition>? availableCollections,
    List<Track>? tracks,
    List<String>? rootFolders,
    List<Tag>? allTags,
    String? searchQuery,
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

class CollectionError extends CollectionState {
  final String message;
  final CollectionDefinition? activeCollectionDefinition;
  final List<CollectionDefinition>? availableCollections;
  final List<Track>? tracks;
  final List<String>? rootFolders;
  const CollectionError(
    this.message, {
    this.activeCollectionDefinition,
    this.availableCollections,
    this.tracks,
    this.rootFolders,
  });
  @override
  List<Object?> get props => [
    message,
    activeCollectionDefinition,
    availableCollections,
    tracks,
    rootFolders,
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

  // Define supported extensions (consider making this configurable later)
  final List<String> _supportedExtensions = [
    'mp3',
    'wav',
    'ogg',
    'm4a',
    'aac',
    'flac',
  ];

  CollectionBloc(this._collectionService) : super(CollectionInitial()) {
    // --- Register Handlers for NEW Events ---
    on<LoadCollectionList>(_onLoadCollectionList);
    on<SwitchCollection>(_onSwitchCollection);
    on<CreateSharedCollection>(
      _onCreateSharedCollection,
    ); // <<< Handler Updated
    on<CreateLocalCollection>(_onCreateLocalCollection);
    on<DeleteCollection>(_onDeleteCollection);

    // --- Register Handlers for Existing Events ---
    on<LoadCollection>(_onLoadCollection);
    on<AddTrackFromPath>(_onAddTrackFromPath);
    on<AddTracksFromPaths>(_onAddTracksFromPaths); // <<< Handler Updated
    on<AddTrackFromUrl>(_onAddTrackFromUrl);
    on<RemoveTrack>(_onRemoveTrack);
    on<SearchCollection>(_onSearchCollection);
    on<UpdateTrackRating>(_onUpdateTrackRating);
    on<UpdateTrackComment>(_onUpdateTrackComment);
    on<AddTrackGeneralTag>(_onAddTrackGeneralTag);
    on<RemoveTrackGeneralTag>(_onRemoveTrackGeneralTag);
    on<ImportCollectionFromFile>(_onImportCollectionFromFile);
    on<ExportCollectionToFile>(_onExportCollectionToFile);
    on<AddRootFolder>(_onAddRootFolder);
    on<RemoveRootFolder>(_onRemoveRootFolder);
    on<LoadAllTags>(_onLoadAllTags);
    on<CreateGeneralTag>(_onCreateGeneralTag);
    on<DeleteGeneralTag>(_onDeleteGeneralTag);
    on<SetGeneralTagColor>(_onSetGeneralTagColor);

    _collectionService.loadingStream.listen((isLoading) {
      if (isLoading && state is CollectionLoaded) {
        final currentState = state as CollectionLoaded;
        emit(
          CollectionLoading(
            activeCollectionDefinition: currentState.activeCollectionDefinition,
            availableCollections: currentState.availableCollections,
            currentTracks: currentState.tracks,
            currentAllTags: currentState.allTags,
            currentRootFolders: currentState.rootFolders,
          ),
        );
      }
      // Consider adding logic here to emit CollectionLoaded when isLoading becomes false
      // if the service doesn't trigger a state update itself upon completion.
    });
  }

  // --- Helper methods ---
  // ... (_getActiveDefFromState, _getAvailableCollectionsFromState, etc. remain the same) ...
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
    if (currentState is CollectionError) return [];
    return [];
  }

  List<String> _getRootFoldersFromState() {
    final currentState = state;
    if (currentState is CollectionLoaded) return currentState.rootFolders;
    if (currentState is CollectionLoading)
      return currentState.currentRootFolders ?? [];
    if (currentState is CollectionError) return currentState.rootFolders ?? [];
    return [];
  }

  // --- >>> NEW Helper: Recursive File Finder <<< ---
  Future<void> _findAudioFilesRecursively(
    Directory dir,
    List<String> audioFilePaths,
    List<String> supportedExtensions,
  ) async {
    // ... (Implementation remains the same as previous step) ...
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
      print("Error scanning directory ${dir.path}: $e");
    }
  }

  // --- >>> MODIFIED Helper: Scan Root and RETURN paths <<< ---
  Future<List<String>> _scanRootForTracks(
    String rootPath,
    Emitter<CollectionState> emit,
  ) async {
    print("BLOC: Scanning for tracks in root: $rootPath");
    List<String> foundFilePaths = []; // Initialize empty list
    try {
      final dir = Directory(rootPath);
      if (!await dir.exists()) {
        print("BLOC: Root path directory does not exist: $rootPath");
        emit(
          CollectionError(
            "Cannot scan: Directory not found $rootPath",
            activeCollectionDefinition: _getActiveDefFromState(),
            availableCollections: _getAvailableCollectionsFromState(),
          ),
        );
        return foundFilePaths; // Return empty list
      }
      await _findAudioFilesRecursively(
        dir,
        foundFilePaths,
        _supportedExtensions,
      );
      print(
        "BLOC: Scan complete. Found ${foundFilePaths.length} tracks in $rootPath.",
      );
    } catch (e, stackTrace) {
      print("BLOC: Error scanning root path $rootPath: $e\n$stackTrace");
      emit(
        CollectionError(
          "Error scanning folder $rootPath: $e",
          activeCollectionDefinition: _getActiveDefFromState(),
          availableCollections: _getAvailableCollectionsFromState(),
          tracks: _getTracksFromState(),
          rootFolders: _getRootFoldersFromState(),
        ),
      );
    }
    return foundFilePaths; // Return the list (might be empty)
  }

  // --- Handlers for NEW Collection Management Events ---

  Future<void> _onLoadCollectionList(
    LoadCollectionList event,
    Emitter<CollectionState> emit,
  ) async {
    // ... (Handler remains the same as previous step) ...
    print("BLOC: Loading collection list...");
    try {
      _availableCollections =
          await _collectionService.loadCollectionDefinitions();
      print(
        "BLOC: Loaded ${_availableCollections.length} collection definitions.",
      );
      final currentState = state;
      if (currentState is CollectionLoaded) {
        emit(
          currentState.copyWith(availableCollections: _availableCollections),
        );
      } else if (currentState is CollectionLoading) {
        emit(
          CollectionLoading(
            activeCollectionDefinition: currentState.activeCollectionDefinition,
            availableCollections: _availableCollections,
            currentTracks: currentState.currentTracks,
            currentAllTags: currentState.currentAllTags,
            currentRootFolders: currentState.currentRootFolders,
          ),
        );
      } else if (currentState is CollectionError) {
        emit(
          CollectionError(
            currentState.message,
            activeCollectionDefinition: currentState.activeCollectionDefinition,
            availableCollections: _availableCollections,
            tracks: currentState.tracks,
            rootFolders: currentState.rootFolders,
          ),
        );
      } else {
        emit(CollectionLoading(availableCollections: _availableCollections));
        print("BLOC: Collection list loaded from Initial state.");
      }
    } catch (e, stackTrace) {
      print("BLOC ERROR loading collection list: $e\n$stackTrace");
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
    // ... (Handler remains the same as previous step) ...
    print("BLOC: Switching collection to ID: ${event.collectionId}");
    final currentCollections = _getAvailableCollectionsFromState();
    final currentRootFolders = _getRootFoldersFromState();
    if (currentCollections.isEmpty) {
      await _onLoadCollectionList(LoadCollectionList(), emit);
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
      emit(
        CollectionLoading(
          activeCollectionDefinition: targetDefinition,
          availableCollections: _availableCollections,
          currentTracks: _getTracksFromState(),
          currentAllTags: _getTagsFromState(),
          currentRootFolders: currentRootFolders,
        ),
      );
      await _collectionService.openCollection(targetDefinition);
      add(LoadCollection());
    } catch (e, stackTrace) {
      print("BLOC ERROR switching collection: $e\n$stackTrace");
      emit(
        CollectionError(
          "Failed to switch collection: $e",
          activeCollectionDefinition: _getActiveDefFromState(),
          availableCollections: _availableCollections,
          tracks: _getTracksFromState(),
          rootFolders: currentRootFolders,
        ),
      );
    }
  }

  // --- >>> REVISED Handler <<< ---
  Future<void> _onCreateSharedCollection(
    CreateSharedCollection event,
    Emitter<CollectionState> emit,
  ) async {
    print(
      "BLOC: Creating shared collection '${event.name}' at ${event.rootPath}",
    );
    final previousState = state;
    final previousActiveDef = _getActiveDefFromState();
    final previousAvailable = _getAvailableCollectionsFromState();
    final previousTracks = _getTracksFromState();
    final previousTags = _getTagsFromState();
    final previousRoots = _getRootFoldersFromState();

    // Show loading immediately
    emit(
      CollectionLoading(
        activeCollectionDefinition: previousActiveDef,
        availableCollections: previousAvailable,
        currentTracks: previousTracks,
        currentAllTags: previousTags,
        currentRootFolders: previousRoots,
      ),
    );

    CollectionDefinition? definition;

    try {
      final id = const Uuid().v4();
      final safeName = event.name
          .replaceAll(RegExp(r'[^\w\s-]'), '_')
          .replaceAll(' ', '_');
      final dbPath = pathLib.join(event.rootPath, '_collection_$safeName.db');

      definition = CollectionDefinition(
        id: id,
        name: event.name,
        type: CollectionType.shared,
        dbPath: dbPath,
        rootPath: event.rootPath,
      );

      // 1. Add definition to storage
      await _collectionService.addCollectionDefinition(definition);

      // 2. Open the collection to initialize DB file (if it doesn't exist)
      //    Keep it open because AddTracksFromPaths will need it.
      await _collectionService.openCollection(definition);

      // 3. Scan the root path for tracks
      final foundPaths = await _scanRootForTracks(event.rootPath, emit);

      // 4. Reload the collection list (now includes the new one)
      _availableCollections =
          await _collectionService.loadCollectionDefinitions();
      print(
        "BLOC: Shared collection definition created. Found ${foundPaths.length} tracks to add.",
      );

      // 5. If tracks were found, dispatch event to add them.
      //    Otherwise, dispatch LoadCollection to show the empty collection.
      if (foundPaths.isNotEmpty) {
        // Dispatch AddTracksFromPaths. This event's handler (_onAddTracksFromPaths)
        // will now be responsible for emitting the final CollectionLoaded state.
        add(AddTracksFromPaths(foundPaths));
        // We emit a loading state here just to update the available collections list
        // while tracks are being added in the background by the AddTracksFromPaths handler.
        emit(
          CollectionLoading(
            activeCollectionDefinition:
                definition, // Show the new one as loading
            availableCollections: _availableCollections,
            currentTracks: [], // Start with empty tracks for the new collection
            currentAllTags: previousTags, // Keep global tags
            currentRootFolders: [definition.rootPath!], // Shared has one root
          ),
        );
      } else {
        // No tracks found, just load the empty collection state
        add(LoadCollection());
        // LoadCollection will emit Loading then Loaded(empty)
      }
    } catch (e, stackTrace) {
      print("BLOC ERROR creating shared collection: $e\n$stackTrace");
      if (definition != null &&
          _collectionService.getActiveCollection()?.id == definition.id) {
        await _collectionService.closeCollection();
      }
      emit(
        CollectionError(
          "Failed to create shared collection: $e",
          activeCollectionDefinition: previousActiveDef,
          availableCollections: previousAvailable,
          tracks: previousTracks,
          rootFolders: previousRoots,
        ),
      );
    }
  }

  Future<void> _onCreateLocalCollection(
    CreateLocalCollection event,
    Emitter<CollectionState> emit,
  ) async {
    // ... (Handler remains the same as previous step - no auto-scan needed) ...
    print("BLOC: Creating local collection '${event.name}'");
    final previousState = state;
    final previousActiveDef = _getActiveDefFromState();
    final previousAvailable = _getAvailableCollectionsFromState();
    final previousTracks = _getTracksFromState();
    final previousTags = _getTagsFromState();
    final previousRoots = _getRootFoldersFromState();

    emit(
      CollectionLoading(
        activeCollectionDefinition: previousActiveDef,
        availableCollections: previousAvailable,
        currentTracks: previousTracks,
        currentAllTags: previousTags,
        currentRootFolders: previousRoots,
      ),
    );

    CollectionDefinition? definition;

    try {
      final id = const Uuid().v4();
      final docDir = await getApplicationDocumentsDirectory();
      final safeName = event.name
          .replaceAll(RegExp(r'[^\w\s-]'), '_')
          .replaceAll(' ', '_');
      final dbPath = pathLib.join(
        docDir.path,
        'collections',
        'local_$safeName.db',
      );

      definition = CollectionDefinition(
        id: id,
        name: event.name,
        type: CollectionType.local,
        dbPath: dbPath,
        rootPath: null,
      );
      await _collectionService.addCollectionDefinition(definition);
      await _collectionService.openCollection(definition);
      await _collectionService.closeCollection();
      _availableCollections =
          await _collectionService.loadCollectionDefinitions();
      print(
        "BLOC: Local collection created. New list size: ${_availableCollections.length}",
      );

      if (previousState is CollectionLoaded) {
        emit(
          previousState.copyWith(availableCollections: _availableCollections),
        );
      } else if (previousState is CollectionLoading) {
        emit(
          CollectionLoading(
            activeCollectionDefinition: previousActiveDef,
            availableCollections: _availableCollections,
            currentTracks: previousTracks,
            currentAllTags: previousTags,
            currentRootFolders: previousRoots,
          ),
        );
      } else if (previousState is CollectionError) {
        emit(
          CollectionError(
            previousState.message,
            activeCollectionDefinition: previousActiveDef,
            availableCollections: _availableCollections,
            tracks: previousTracks,
            rootFolders: previousRoots,
          ),
        );
      } else {
        emit(CollectionLoading(availableCollections: _availableCollections));
      }
    } catch (e, stackTrace) {
      print("BLOC ERROR creating local collection: $e\n$stackTrace");
      if (definition != null &&
          _collectionService.getActiveCollection()?.id == definition.id) {
        await _collectionService.closeCollection();
      }
      emit(
        CollectionError(
          "Failed to create local collection: $e",
          activeCollectionDefinition: previousActiveDef,
          availableCollections: previousAvailable,
          tracks: previousTracks,
          rootFolders: previousRoots,
        ),
      );
    }
  }

  Future<void> _onDeleteCollection(
    DeleteCollection event,
    Emitter<CollectionState> emit,
  ) async {
    // ... (Handler remains the same as previous step) ...
    print("BLOC: Deleting collection definition ID: ${event.collectionId}");
    try {
      await _collectionService.removeCollectionDefinition(event.collectionId);
      final currentActiveDef = _getActiveDefFromState();
      final wasActiveDeleted = currentActiveDef?.id == event.collectionId;
      _availableCollections =
          await _collectionService.loadCollectionDefinitions();
      if (wasActiveDeleted) {
        print("BLOC: Active collection was deleted. Switching...");
        await _collectionService.closeCollection();
        if (_availableCollections.isNotEmpty) {
          add(SwitchCollection(_availableCollections.first.id));
        } else {
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
              allTags: _getTagsFromState(),
            ),
          );
        }
      } else {
        final currentState = state;
        if (currentState is CollectionLoaded) {
          emit(
            currentState.copyWith(availableCollections: _availableCollections),
          );
        } else if (currentState is CollectionLoading) {
          emit(
            CollectionLoading(
              activeCollectionDefinition:
                  currentState.activeCollectionDefinition,
              availableCollections: _availableCollections,
              currentTracks: currentState.currentTracks,
              currentAllTags: currentState.currentAllTags,
              currentRootFolders: currentState.currentRootFolders,
            ),
          );
        } else if (currentState is CollectionError) {
          emit(
            CollectionError(
              currentState.message,
              activeCollectionDefinition:
                  currentState.activeCollectionDefinition,
              availableCollections: _availableCollections,
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
          availableCollections: _availableCollections,
          tracks: _getTracksFromState(),
          rootFolders: _getRootFoldersFromState(),
        ),
      );
    }
  }

  // --- Handlers for Existing Events (Adapting to Active Collection Context) ---

  Future<void> _onLoadCollection(
    LoadCollection event,
    Emitter<CollectionState> emit,
  ) async {
    // ... (Handler remains the same as previous step) ...
    final activeDefinition = _collectionService.getActiveCollection();
    if (activeDefinition == null) {
      print(
        "BLOC: Cannot load collection, no active collection set in service.",
      );
      add(LoadCollectionList());
      emit(
        CollectionError(
          "No active collection selected.",
          availableCollections: _availableCollections,
        ),
      );
      return;
    }
    emit(
      CollectionLoading(
        activeCollectionDefinition: activeDefinition,
        availableCollections: _availableCollections,
        currentTracks: _getTracksFromState(),
        currentAllTags: _getTagsFromState(),
        currentRootFolders: _getRootFoldersFromState(),
      ),
    );
    try {
      final tracks = await _collectionService.getAllTracks();
      final rootFolders = _collectionService.getRootFolders();
      final allTags = await _collectionService.getAllTags();
      print(
        "BLOC: Loaded ${tracks.length} tracks, ${rootFolders.length} roots, ${allTags.length} tags for collection '${activeDefinition.name}'.",
      );
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
          searchQuery: previousSearchQuery,
        ),
      );
    } catch (e, stackTrace) {
      print("BLOC ERROR loading collection data: $e\n$stackTrace");
      emit(
        CollectionError(
          "Failed to load collection data: ${e.toString()}",
          activeCollectionDefinition: activeDefinition,
          availableCollections: _availableCollections,
          rootFolders: _getRootFoldersFromState(),
        ),
      );
    }
  }

  Future<void> _onAddRootFolder(
    AddRootFolder event,
    Emitter<CollectionState> emit,
  ) async {
    // ... (Handler remains the same as previous step) ...
    final activeDef = _getActiveDefFromState();
    if (activeDef?.type != CollectionType.local) {
      print(
        "BLOC: Skipping AddRootFolder - only applicable to local collections.",
      );
      return;
    }
    if (state is CollectionLoaded || state is CollectionLoading) {
      final currentState = state;
      final currentTracks = _getTracksFromState();
      final currentTags = _getTagsFromState();
      final currentAvailableCollections = _getAvailableCollectionsFromState();
      try {
        await _collectionService.addRootFolder(event.folderPath);
        final updatedRootFolders = _collectionService.getRootFolders();
        if (currentState is CollectionLoaded) {
          emit(currentState.copyWith(rootFolders: updatedRootFolders));
        } else if (currentState is CollectionLoading) {
          emit(
            CollectionLoading(
              activeCollectionDefinition:
                  currentState.activeCollectionDefinition,
              availableCollections: currentState.availableCollections,
              currentTracks: currentState.currentTracks,
              currentAllTags: currentState.currentAllTags,
              currentRootFolders: updatedRootFolders,
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
            rootFolders: _getRootFoldersFromState(),
          ),
        );
      }
    }
  }

  Future<void> _onRemoveRootFolder(
    RemoveRootFolder event,
    Emitter<CollectionState> emit,
  ) async {
    // ... (Handler remains the same as previous step) ...
    final activeDef = _getActiveDefFromState();
    if (activeDef?.type != CollectionType.local) {
      print(
        "BLOC: Skipping RemoveRootFolder - only applicable to local collections.",
      );
      return;
    }
    if (state is CollectionLoaded || state is CollectionLoading) {
      final currentState = state;
      final currentTracks = _getTracksFromState();
      final currentTags = _getTagsFromState();
      final currentAvailableCollections = _getAvailableCollectionsFromState();
      try {
        await _collectionService.removeRootFolder(event.folderPath);
        final updatedRootFolders = _collectionService.getRootFolders();
        if (currentState is CollectionLoaded) {
          emit(currentState.copyWith(rootFolders: updatedRootFolders));
        } else if (currentState is CollectionLoading) {
          emit(
            CollectionLoading(
              activeCollectionDefinition:
                  currentState.activeCollectionDefinition,
              availableCollections: currentState.availableCollections,
              currentTracks: currentState.currentTracks,
              currentAllTags: currentState.currentAllTags,
              currentRootFolders: updatedRootFolders,
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
            rootFolders: _getRootFoldersFromState(),
          ),
        );
      }
    }
  }

  Future<void> _onAddTrackFromPath(
    AddTrackFromPath event,
    Emitter<CollectionState> emit,
  ) async {
    // ... (Handler logic remains similar, relies on service) ...
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
    final tracksBeforeAdd = _getTracksFromState();
    final tagsBeforeAdd = _getTagsFromState();
    final rootsBeforeAdd = _getRootFoldersFromState();
    emit(
      CollectionLoading(
        activeCollectionDefinition: activeDef,
        availableCollections: _availableCollections,
        currentTracks: tracksBeforeAdd,
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd,
      ),
    );
    try {
      await _collectionService.addLocalFile(event.filePath);
      add(LoadCollection()); // Reload all tracks
    } catch (e, stackTrace) {
      print("BLOC ERROR adding track from path: $e\n$stackTrace");
      emit(
        CollectionError(
          e.toString(),
          activeCollectionDefinition: activeDef,
          availableCollections: _availableCollections,
          tracks: tracksBeforeAdd,
          rootFolders: rootsBeforeAdd,
        ),
      );
    }
  }

  Future<void> _onAddTrackFromUrl(
    AddTrackFromUrl event,
    Emitter<CollectionState> emit,
  ) async {
    // ... (Handler logic remains similar, relies on service) ...
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
    final rootsBeforeAdd = _getRootFoldersFromState();
    emit(
      CollectionLoading(
        activeCollectionDefinition: activeDef,
        availableCollections: _availableCollections,
        currentTracks: tracksBeforeAdd,
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd,
      ),
    );
    try {
      await _collectionService.addUrl(event.url);
      add(LoadCollection());
    } catch (e, stackTrace) {
      print("BLOC ERROR adding track from URL: $e\n$stackTrace");
      emit(
        CollectionError(
          e.toString(),
          activeCollectionDefinition: activeDef,
          availableCollections: _availableCollections,
          tracks: tracksBeforeAdd,
          rootFolders: rootsBeforeAdd,
        ),
      );
    }
  }

  // --- >>> REVISED Handler <<< ---
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
      "BLOC: AddTracksFromPaths received ${event.filePaths.length} files for collection ${activeDef.name}",
    );
    final tracksBeforeAdd = _getTracksFromState();
    final tagsBeforeAdd = _getTagsFromState();
    final rootsBeforeAdd = _getRootFoldersFromState();

    // Emit Loading state *before* starting the potentially long add process
    emit(
      CollectionLoading(
        activeCollectionDefinition: activeDef,
        availableCollections: _availableCollections,
        currentTracks: tracksBeforeAdd, // Show previous tracks while adding
        currentAllTags: tagsBeforeAdd,
        currentRootFolders: rootsBeforeAdd,
      ),
    );

    try {
      List<Track> addedOrFoundTracks = [];
      // Step 1: Add all tracks via service (handles relative/absolute paths and checks existence)
      // This loop adds tracks one by one to the DB.
      for (final filePath in event.filePaths) {
        try {
          final track = await _collectionService.addLocalFile(filePath);
          addedOrFoundTracks.add(track);
          // print('BLOC: Added/found track during AddTracksFromPaths: ${track.title}');
        } catch (e) {
          print(
            'BLOC ERROR: Failed to add file $filePath during AddTracksFromPaths: $e',
          );
          // Optionally collect errors to show user later
        }
      }
      print(
        "BLOC: Finished adding/checking ${addedOrFoundTracks.length} tracks in service.",
      );

      // Step 2: Emit final loaded state with all tracks from the DB
      // This ensures the UI reflects the complete state *after* adding.
      final currentTracks = await _collectionService.getAllTracks();
      final currentRootFolders = _collectionService.getRootFolders();
      final currentTags =
          await _collectionService
              .getAllTags(); // Reload global tags too? Optional.

      print(
        "BLOC: Emitting CollectionLoaded after AddTracksFromPaths. Track count: ${currentTracks.length}",
      );

      emit(
        CollectionLoaded(
          activeCollectionDefinition: activeDef,
          availableCollections: _availableCollections, // Use cached list
          tracks: currentTracks,
          rootFolders: currentRootFolders,
          allTags: currentTags,
          searchQuery:
              (state is CollectionLoaded)
                  ? (state as CollectionLoaded).searchQuery
                  : null, // Preserve search
        ),
      );

      // Step 3: Start background waveform processing (if applicable)
      // Use the ABSOLUTE paths from the addedOrFoundTracks list
      final absolutePathsToProcess =
          addedOrFoundTracks.where((t) => !t.isUrl).map((t) => t.path).toList();
      print(
        "BLOC: Checking waveform processing for ${absolutePathsToProcess.length} files after AddTracksFromPaths.",
      );
      if (!_isProcessingWaveforms && absolutePathsToProcess.isNotEmpty) {
        print(
          "BLOC: Starting background waveform extraction from AddTracksFromPaths.",
        );
        _startBackgroundWaveformExtraction(absolutePathsToProcess);
      } else {
        print(
          "BLOC: Waveform processing already running or no files needed processing.",
        );
      }
    } catch (e, stackTrace) {
      print('BLOC ERROR: Exception in _onAddTracksFromPaths: $e\n$stackTrace');
      // Emit error state, reverting to state before the add attempt
      emit(
        CollectionError(
          e.toString(),
          activeCollectionDefinition: activeDef,
          availableCollections: _availableCollections,
          tracks: tracksBeforeAdd,
          rootFolders: rootsBeforeAdd,
        ),
      );
    }
  }

  Future<void> _startBackgroundWaveformExtraction(
    List<String> absoluteFilePaths,
  ) async {
    // ... (Handler remains the same as previous step) ...
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
        final filePath = absoluteFilePaths[i];
        final fileName = pathLib.basename(filePath);
        print(
          'WAVEFORM: Processing file ${i + 1}/${absoluteFilePaths.length}: $fileName',
        );
        try {
          final track = await _collectionService.getTrackByPath(filePath);
          if (track?.id != null) {
            print('WAVEFORM: Found track ID: ${track!.id} for file: $fileName');
            final success = await _extractWaveformData(track.id!, filePath);
            print(
              'WAVEFORM: Extraction ${success ? "succeeded" : "failed"} for $fileName',
            );
            final currentActiveDef = _collectionService.getActiveCollection();
            if (state is CollectionLoaded &&
                (state as CollectionLoaded).activeCollectionDefinition.id ==
                    currentActiveDef?.id) {
              print('WAVEFORM: Updating UI after processing file ${i + 1}');
              final updatedTracks = await _collectionService.getAllTracks();
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
        await Future.delayed(const Duration(milliseconds: 500));
      }
      print('WAVEFORM: Completed extraction for all files');
    } catch (e) {
      print('WAVEFORM ERROR: Exception in background extraction: $e');
    } finally {
      _isProcessingWaveforms = false;
    }
  }

  Future<bool> _extractWaveformData(
    int trackId,
    String absoluteFilePath,
  ) async {
    // ... (Handler remains the same as previous step) ...
    print(
      'EXTRACT: Starting for track $trackId: ${pathLib.basename(absoluteFilePath)}',
    );
    try {
      await _ensureAudioServiceInitialized();
      await _audioService.loadAudio(absoluteFilePath, isUrl: false);
      final completer = Completer<List<double>?>();
      StreamSubscription? sub;
      sub = _audioService.waveformStream.listen((data) {
        if (!completer.isCompleted) {
          completer.complete(data);
          sub?.cancel();
        }
      });
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
    // ... (Handler remains the same as previous step) ...
    print('UPDATE: Saving waveform data for track $trackId');
    final track = await _collectionService.getTrack(trackId);
    if (track != null) {
      await _collectionService.updateTrack(
        track.copyWith(waveformData: waveformData),
      );
      print('UPDATE: Successfully saved waveform data for track $trackId');
    } else {
      print('UPDATE ERROR: Track $trackId not found');
      throw Exception('Track not found');
    }
  }

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

  Future<void> _ensureAudioServiceInitialized() async {
    if (!_audioServiceInitialized) {
      print('AUDIO: Initializing AudioService');
      // Assuming AudioService has an async initialize method
      // await _audioService.initialize();
      _audioServiceInitialized = true;
      print('AUDIO: AudioService initialization complete');
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
