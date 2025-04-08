// lib/blocs/collection_management/collection_management_bloc.dart

import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as pathLib;
import 'package:path_provider/path_provider.dart';

// Import Services and Models
import '../../services/collection_service.dart';

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
    // Preserve active collection if already loaded
    final currentActiveDef = state.activeCollectionDefinition;
    emit(
      CollectionManagementLoading(
        availableCollections:
            state.availableCollections, // Keep old list while loading
        activeCollectionDefinition: currentActiveDef,
      ),
    );
    try {
      final definitions = await _collectionService.loadCollectionDefinitions();
      print(
        "CollectionManagementBloc: Loaded ${definitions.length} definitions.",
      );

      // If no collection is active AND definitions were loaded, try activating the first one
      CollectionDefinition? newActiveDef = currentActiveDef;
      if (currentActiveDef == null && definitions.isNotEmpty) {
        // Attempt to open the first one as default (UI might override this later)
        try {
          print(
            "CollectionManagementBloc: No active collection, attempting to activate '${definitions.first.name}'.",
          );
          await _collectionService.openCollection(definitions.first);
          newActiveDef = definitions.first;
        } catch (e) {
          print(
            "CollectionManagementBloc: Failed to auto-activate first collection: $e. Staying inactive.",
          );
          newActiveDef = null; // Stay inactive if opening fails
          await _collectionService
              .closeCollection(); // Ensure it's closed if activation failed
        }
      } else if (currentActiveDef != null &&
          !definitions.any((d) => d.id == currentActiveDef.id)) {
        print(
          "CollectionManagementBloc: Previously active collection no longer exists. Deactivating.",
        );
        // Previously active collection was deleted, deactivate
        await _collectionService.closeCollection();
        newActiveDef = null;
      }

      emit(
        CollectionManagementLoaded(
          availableCollections: definitions,
          activeCollectionDefinition:
              newActiveDef, // Use potentially updated active definition
        ),
      );
      // Trigger TrackManagementBloc/PlaylistBloc to load data for the newly active collection
      // This is best handled by the UI layer (e.g., HomeScreen) listening to this state change.
    } catch (e, stackTrace) {
      print("CollectionManagementBloc ERROR loading list: $e\n$stackTrace");
      emit(
        CollectionManagementError(
          "Failed to load collection list: $e",
          availableCollections:
              state.availableCollections, // Keep old list on error
          activeCollectionDefinition: currentActiveDef,
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

    // Optionally show loading, though delete is usually fast
    // emit(CollectionManagementLoading(availableCollections: previousAvailable, activeCollectionDefinition: previousActive));

    try {
      await _collectionService.removeCollectionDefinition(event.collectionId);
      final wasActiveDeleted = previousActive?.id == event.collectionId;

      // Reload the list
      final updatedDefinitions =
          await _collectionService.loadCollectionDefinitions();

      CollectionDefinition? newActiveDef = previousActive;
      if (wasActiveDeleted) {
        print(
          "CollectionManagementBloc: Active collection was deleted. Deactivating.",
        );
        await _collectionService.closeCollection(); // Close DB if it was active
        newActiveDef = null; // No active collection now
        // Potentially auto-switch to another if desired, or let user choose
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
      // UI listener should handle state changes (e.g., if active became null)
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
