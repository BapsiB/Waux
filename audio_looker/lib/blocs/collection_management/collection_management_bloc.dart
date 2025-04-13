// lib/blocs/collection_management/collection_management_bloc.dart

import 'dart:async';
import 'dart:io';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as pathLib;
import 'package:path_provider/path_provider.dart';
import 'package:audio_looker/services/collection_service.dart';

part 'collection_management_event.dart';
part 'collection_management_state.dart';

/// BLoC responsible for managing collection definitions (list, active, CRUD).
class CollectionManagementBloc
    extends Bloc<CollectionManagementEvent, CollectionManagementState> {
  final CollectionService _collectionService;

  CollectionManagementBloc(this._collectionService)
    : super(CollectionManagementInitial()) {
    on<LoadCollectionList>(_onLoadCollectionList);
    on<SwitchCollection>(_onSwitchCollection);
    on<CreateSharedCollection>(_onCreateSharedCollection);
    on<CreateLocalCollection>(_onCreateLocalCollection);
    on<AddExistingSharedCollection>(_onAddExistingSharedCollection);
    on<DeleteCollection>(_onDeleteCollection);
  }

  Future<void> _onLoadCollectionList(
    LoadCollectionList event,
    Emitter<CollectionManagementState> emit,
  ) async {
    // Preserve active collection if already loaded from a previous state
    final currentActiveDef = state.activeCollectionDefinition;
    emit(
      CollectionManagementLoading(
        availableCollections: state.availableCollections,
        activeCollectionDefinition: currentActiveDef,
      ),
    );
    try {
      // --- MODIFIED START ---
      // 1. Load the last active ID *before* loading definitions
      final String? lastActiveId =
          await _collectionService.loadLastActiveCollectionId();
      print("CollectionManagementBloc: Found last active ID: $lastActiveId");

      // 2. Load all definitions
      final definitions = await _collectionService.loadCollectionDefinitions();
      print(
        "CollectionManagementBloc: Loaded ${definitions.length} definitions.",
      );

      CollectionDefinition? collectionToActivate;

      // 3. Check if last active ID is valid and exists in the loaded definitions
      if (lastActiveId != null &&
          definitions.any((d) => d.id == lastActiveId)) {
        collectionToActivate = definitions.firstWhere(
          (d) => d.id == lastActiveId,
        );
        print(
          "CollectionManagementBloc: Will attempt to activate last active: ${collectionToActivate.name}",
        );
      }
      // --- MODIFIED END ---
      // If no valid lastActiveId found, and no collection currently active, default to first (optional)
      else if (currentActiveDef == null && definitions.isNotEmpty) {
        // Default to first only if no last active ID was found
        // collectionToActivate = definitions.first;
        // print("CollectionManagementBloc: No valid last active ID, defaulting to first: ${collectionToActivate.name}");
        print(
          "CollectionManagementBloc: No valid last active ID found, remaining inactive for now.",
        );
        collectionToActivate = null; // Or keep it null to not auto-activate any
      } else if (currentActiveDef != null &&
          !definitions.any((d) => d.id == currentActiveDef.id)) {
        // Handle case where previously active was deleted
        print(
          "CollectionManagementBloc: Previously active collection no longer exists. Deactivating.",
        );
        await _collectionService.closeCollection();
        collectionToActivate = null;
      } else {
        // Keep the current one active if it still exists, or stay inactive
        collectionToActivate =
            currentActiveDef != null &&
                    definitions.any((d) => d.id == currentActiveDef.id)
                ? currentActiveDef
                : null;
        print(
          "CollectionManagementBloc: Keeping current state: ${collectionToActivate?.name ?? 'Inactive'}",
        );
      }

      // --- Attempt to open the determined collection (if any) ---
      CollectionDefinition? finalActiveDefinition = collectionToActivate;
      if (collectionToActivate != null) {
        try {
          print(
            "CollectionManagementBloc: Opening collection: ${collectionToActivate.name}",
          );
          await _collectionService.openCollection(collectionToActivate);
        } catch (e) {
          print(
            "CollectionManagementBloc: Failed to open collection '${collectionToActivate.name}': $e. Deactivating.",
          );
          finalActiveDefinition =
              null; // Failed to open, so no active collection
          await _collectionService.saveLastActiveCollectionId(
            null,
          ); // Clear invalid saved ID
          await _collectionService.closeCollection(); // Ensure DB is closed
        }
      } else {
        print("CollectionManagementBloc: No collection to activate.");
        // Ensure service is closed if no collection is active
        await _collectionService.closeCollection();
      }

      emit(
        CollectionManagementLoaded(
          availableCollections: definitions,
          activeCollectionDefinition:
              finalActiveDefinition, // Use the one that was successfully opened (or null)
        ),
      );
      // UI layer listens to this state to trigger Track/Playlist loads
    } catch (e, stackTrace) {
      print("CollectionManagementBloc ERROR loading list: $e\n$stackTrace");
      emit(
        CollectionManagementError(
          "Failed to load collection list: $e",
          availableCollections: state.availableCollections,
          activeCollectionDefinition:
              currentActiveDef, // Revert to previous on error
        ),
      );
    }
  }

  Future<void> _onSwitchCollection(
    SwitchCollection event,
    Emitter<CollectionManagementState> emit,
  ) async {
    final currentCollections = state.availableCollections;
    // Emit loading state showing which collection we're trying to switch TO
    CollectionDefinition? targetDefinition;
    try {
      targetDefinition = currentCollections.firstWhere(
        (def) => def.id == event.collectionId,
      );
    } catch (e) {
      emit(
        CollectionManagementError(
          "Collection ID ${event.collectionId} not found.",
          availableCollections: currentCollections,
          activeCollectionDefinition:
              state.activeCollectionDefinition, // Keep old active on error
        ),
      );
      return;
    }

    emit(
      CollectionManagementLoading(
        availableCollections: currentCollections,
        activeCollectionDefinition: targetDefinition, // Show target as loading
      ),
    );

    try {
      await _collectionService.openCollection(targetDefinition);
      print(
        "CollectionManagementBloc: Switched active collection to '${targetDefinition.name}'.",
      );

      // --- MODIFIED START ---
      // Save the successfully activated collection ID
      await _collectionService.saveLastActiveCollectionId(targetDefinition.id);
      // --- MODIFIED END ---

      emit(
        CollectionManagementLoaded(
          availableCollections: currentCollections,
          activeCollectionDefinition: targetDefinition, // Confirm switch
        ),
      );
      // UI layer should listen and trigger TrackManagementBloc/PlaylistBloc load.
    } catch (e, stackTrace) {
      print(
        "CollectionManagementBloc ERROR switching collection: $e\n$stackTrace",
      );
      // Revert to previous active definition on error
      emit(
        CollectionManagementError(
          "Failed to switch collection: $e",
          availableCollections: currentCollections,
          activeCollectionDefinition:
              state is CollectionManagementLoaded
                  ? state.activeCollectionDefinition
                  : null,
        ),
      );
      // Ensure collection is closed if switch failed
      await _collectionService.closeCollection();
    }
  }

  Future<void> _onCreateSharedCollection(
    CreateSharedCollection event,
    Emitter<CollectionManagementState> emit,
  ) async {
    // Keep current state while creating
    final previousAvailable = state.availableCollections;
    final previousActive = state.activeCollectionDefinition;
    emit(
      CollectionManagementLoading(
        availableCollections: previousAvailable,
        activeCollectionDefinition: previousActive,
      ),
    ); // Indicate loading

    CollectionDefinition? newDefinition;
    try {
      final id = const Uuid().v4();
      final safeName = event.name
          .replaceAll(RegExp(r'[^\w\s-]'), '_')
          .replaceAll(' ', '_');
      // Place DB inside the root path
      final dbPath = pathLib.join(event.rootPath, '_collection_$safeName.db');

      newDefinition = CollectionDefinition(
        id: id,
        name: event.name,
        type: CollectionType.shared,
        dbPath: dbPath,
        rootPath: event.rootPath,
      );

      // 1. Add definition to storage
      await _collectionService.addCollectionDefinition(newDefinition);
      // 2. Initialize the DB file by opening the collection via the service
      await _collectionService.openCollection(newDefinition);
      // 3. Immediately close it - let subsequent SwitchCollection handle activation if needed
      await _collectionService.closeCollection();
      // 4. Reload the list
      final updatedDefinitions =
          await _collectionService.loadCollectionDefinitions();

      // 5. Emit loaded state, keeping previous collection active
      emit(
        CollectionManagementLoaded(
          availableCollections: updatedDefinitions,
          activeCollectionDefinition: previousActive,
        ),
      );
      print(
        "CollectionManagementBloc: Created shared collection definition '${event.name}'.",
      );
      // TrackManagementBloc will be triggered later if user switches to this collection.
    } catch (e, stackTrace) {
      print(
        "CollectionManagementBloc ERROR creating shared collection: $e\n$stackTrace",
      );
      // Clean up potentially created definition if error occurred
      if (newDefinition != null) {
        await _collectionService
            .removeCollectionDefinition(newDefinition.id)
            .catchError((_) {});
      }
      emit(
        CollectionManagementError(
          "Failed to create shared collection: $e",
          availableCollections: previousAvailable, // Revert list
          activeCollectionDefinition: previousActive, // Revert active
        ),
      );
    }
  }

  Future<void> _onCreateLocalCollection(
    CreateLocalCollection event,
    Emitter<CollectionManagementState> emit,
  ) async {
    final previousAvailable = state.availableCollections;
    final previousActive = state.activeCollectionDefinition;
    emit(
      CollectionManagementLoading(
        availableCollections: previousAvailable,
        activeCollectionDefinition: previousActive,
      ),
    );

    CollectionDefinition? newDefinition;
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

      newDefinition = CollectionDefinition(
        id: id,
        name: event.name,
        type: CollectionType.local,
        dbPath: dbPath,
        rootPath:
            null, // Local collections don't have a single root stored here
      );

      // 1. Add definition
      await _collectionService.addCollectionDefinition(newDefinition);
      // 2. Initialize DB by opening and closing
      await _collectionService.openCollection(newDefinition);
      await _collectionService.closeCollection();
      // 3. Reload list
      final updatedDefinitions =
          await _collectionService.loadCollectionDefinitions();

      // 4. Emit loaded state, keeping previous active
      emit(
        CollectionManagementLoaded(
          availableCollections: updatedDefinitions,
          activeCollectionDefinition: previousActive,
        ),
      );
      print(
        "CollectionManagementBloc: Created local collection definition '${event.name}'.",
      );
    } catch (e, stackTrace) {
      print(
        "CollectionManagementBloc ERROR creating local collection: $e\n$stackTrace",
      );
      if (newDefinition != null) {
        await _collectionService
            .removeCollectionDefinition(newDefinition.id)
            .catchError((_) {});
      }
      emit(
        CollectionManagementError(
          "Failed to create local collection: $e",
          availableCollections: previousAvailable,
          activeCollectionDefinition: previousActive,
        ),
      );
    }
  }

  Future<void> _onAddExistingSharedCollection(
    AddExistingSharedCollection event,
    Emitter<CollectionManagementState> emit,
  ) async {
    final previousAvailable = state.availableCollections;
    final previousActive = state.activeCollectionDefinition;
    emit(
      CollectionManagementLoading(
        availableCollections: previousAvailable,
        activeCollectionDefinition: previousActive,
      ),
    );

    try {
      final id = const Uuid().v4(); // Generate new unique ID for the definition
      final definition = CollectionDefinition(
        id: id,
        name: event.name,
        type: CollectionType.shared,
        dbPath: event.dbPath, // Use the provided existing DB path
        rootPath: event.rootPath,
      );

      // 1. Add definition to storage
      await _collectionService.addCollectionDefinition(definition);
      // 2. DO NOT open/initialize DB - it already exists.
      // 3. Reload list
      final updatedDefinitions =
          await _collectionService.loadCollectionDefinitions();

      // 4. Emit loaded state, keeping previous active
      emit(
        CollectionManagementLoaded(
          availableCollections: updatedDefinitions,
          activeCollectionDefinition: previousActive,
        ),
      );
      print(
        "CollectionManagementBloc: Added existing shared collection '${event.name}'.",
      );
    } catch (e, stackTrace) {
      print(
        "CollectionManagementBloc ERROR adding existing shared collection: $e\n$stackTrace",
      );
      emit(
        CollectionManagementError(
          "Failed to add existing shared collection: $e",
          availableCollections: previousAvailable,
          activeCollectionDefinition: previousActive,
        ),
      );
    }
  }

  Future<void> _onDeleteCollection(
    DeleteCollection event,
    Emitter<CollectionManagementState> emit,
  ) async {
    final previousAvailable = state.availableCollections;
    final previousActive = state.activeCollectionDefinition;

    // --- Find the definition to be deleted ---
    CollectionDefinition? definitionToDelete;
    try {
      definitionToDelete = previousAvailable.firstWhere(
        (def) => def.id == event.collectionId,
      );
    } catch (e) {
      print(
        "CollectionManagementBloc: Could not find definition for ID ${event.collectionId} to delete.",
      );
      emit(
        CollectionManagementError(
          "Collection to delete not found.",
          availableCollections: previousAvailable,
          activeCollectionDefinition: previousActive,
        ),
      );
      return; // Stop if definition not found
    }

    try {
      final String? lastActiveId =
          await _collectionService.loadLastActiveCollectionId();
      final bool wasActiveDeleted = previousActive?.id == event.collectionId;
      final bool wasLastSavedDeleted = lastActiveId == event.collectionId;

      if (definitionToDelete.type == CollectionType.local) {
        try {
          final dbFile = File(definitionToDelete.dbPath);
          if (await dbFile.exists()) {
            await dbFile.delete();
            print(
              "CollectionManagementBloc: Deleted local collection DB file: ${definitionToDelete.dbPath}",
            );
          } else {
            print(
              "CollectionManagementBloc: Local collection DB file not found, skipping deletion: ${definitionToDelete.dbPath}",
            );
          }
        } catch (e) {
          print(
            "CollectionManagementBloc: Error deleting local DB file ${definitionToDelete.dbPath}: $e",
          );
          // Decide if you want to stop the process or just log the error.
          // Optionally re-throw or emit an error specific to file deletion failure.
        }
      } else {
        print(
          "CollectionManagementBloc: Skipping DB file deletion for shared collection: ${definitionToDelete.name}",
        );
      }

      // Remove the definition from the list
      await _collectionService.removeCollectionDefinition(event.collectionId);
      final updatedDefinitions =
          await _collectionService.loadCollectionDefinitions();

      CollectionDefinition? newActiveDef = previousActive;

      // If the one being deleted was the active one OR the last saved one, clear state
      if (wasActiveDeleted || wasLastSavedDeleted) {
        print(
          "CollectionManagementBloc: Deleted collection was active or last saved. Deactivating and clearing saved ID.",
        );
        if (wasActiveDeleted) {
          await _collectionService
              .closeCollection(); // Close DB if it was active
        }
        await _collectionService.saveLastActiveCollectionId(
          null,
        ); // Clear saved ID
        newActiveDef = null; // No active collection now
      }

      emit(
        CollectionManagementLoaded(
          availableCollections: updatedDefinitions,
          activeCollectionDefinition:
              newActiveDef, // May be null if active was deleted
        ),
      );
      print(
        "CollectionManagementBloc: Deleted collection definition ID: ${event.collectionId}",
      );
    } catch (e, stackTrace) {
      print(
        "CollectionManagementBloc ERROR deleting collection: $e\n$stackTrace",
      );
      emit(
        CollectionManagementError(
          "Failed to delete collection: $e",
          availableCollections: previousAvailable, // Revert list on error
          activeCollectionDefinition: previousActive, // Revert active on error
        ),
      );
    }
  }
}
