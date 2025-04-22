// lib/blocs/global_tag/global_tag_bloc.dart

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

// Import Services and Models
import '../../services/collection_service.dart'; // For Tag model and CollectionService

part 'global_tag_event.dart';
part 'global_tag_state.dart';

/// BLoC responsible for managing the global list of tag definitions
/// (name, color) stored typically via SharedPreferences.
class GlobalTagBloc extends Bloc<GlobalTagEvent, GlobalTagState> {
  final CollectionService _collectionService;

  GlobalTagBloc(this._collectionService) : super(GlobalTagInitial()) {
    on<LoadGlobalTags>(_onLoadGlobalTags);
    on<AddGlobalTag>(_onAddGlobalTag);
    on<RemoveGlobalTag>(_onRemoveGlobalTag);
    on<UpdateGlobalTagColor>(_onUpdateGlobalTagColor);
  }

  Future<void> _onLoadGlobalTags(
    LoadGlobalTags event,
    Emitter<GlobalTagState> emit,
  ) async {
    // Optionally emit loading state
    // emit(GlobalTagLoading());
    try {
      final tags = await _collectionService.getAllTags();
      print("GlobalTagBloc: Loaded ${tags.length} global tags.");
      emit(GlobalTagLoaded(tags));
    } catch (e) {
      print("GlobalTagBloc Error loading tags: $e");
      emit(GlobalTagError("Failed to load global tags: ${e.toString()}"));
    }
  }

  Future<void> _onAddGlobalTag(
    AddGlobalTag event,
    Emitter<GlobalTagState> emit,
  ) async {
    final currentState = state;
    // List<Tag> currentTags = [];
    // if (currentState is GlobalTagLoaded) {
    //   currentTags = currentState.allTags;
    // }

    try {
      // Service handles checking for duplicates
      await _collectionService.addTag(event.tag);
      final updatedTags = await _collectionService.getAllTags();
      print("GlobalTagBloc: Added tag '${event.tag.name}'.");
      emit(GlobalTagLoaded(updatedTags));
    } catch (e) {
      print("GlobalTagBloc Error adding tag: $e");
      // Re-emit previous loaded state on error
      emit(GlobalTagError("Failed to add tag: ${e.toString()}"));
      if (currentState is GlobalTagLoaded) emit(currentState);
    }
  }

  Future<void> _onRemoveGlobalTag(
    RemoveGlobalTag event,
    Emitter<GlobalTagState> emit,
  ) async {
    final currentState = state;
    if (currentState is! GlobalTagLoaded) return; // Can only remove if loaded

    try {
      await _collectionService.removeTag(event.tagName);
      final updatedTags = await _collectionService.getAllTags();
      print("GlobalTagBloc: Removed tag '${event.tagName}'.");
      emit(GlobalTagLoaded(updatedTags));
      // Note: Removing a global tag definition doesn't automatically remove
      // it from tracks where it's already assigned in the DB.
      // A separate mechanism or UI prompt might be needed for that cleanup.
    } catch (e) {
      print("GlobalTagBloc Error removing tag: $e");
      emit(GlobalTagError("Failed to remove tag: ${e.toString()}"));
      emit(currentState); // Re-emit previous loaded state
    }
  }

  Future<void> _onUpdateGlobalTagColor(
    UpdateGlobalTagColor event,
    Emitter<GlobalTagState> emit,
  ) async {
    final currentState = state;
    if (currentState is! GlobalTagLoaded) return;

    try {
      // Create the updated tag object
      final tagToUpdate = currentState.allTags.firstWhere(
        (t) => t.name == event.tagName,
        orElse:
            () =>
                throw Exception(
                  "Tag '${event.tagName}' not found to update color.",
                ),
      );
      final updatedTag = Tag(
        name: tagToUpdate.name,
        colorValue: event.colorValue,
      );

      await _collectionService.updateTag(updatedTag);
      final updatedTags = await _collectionService.getAllTags();
      print("GlobalTagBloc: Updated color for tag '${event.tagName}'.");
      emit(GlobalTagLoaded(updatedTags));
    } catch (e) {
      print("GlobalTagBloc Error updating tag color: $e");
      emit(GlobalTagError("Failed to update tag color: ${e.toString()}"));
      emit(currentState); // Re-emit previous loaded state
    }
  }
}
