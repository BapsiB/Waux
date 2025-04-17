// lib/blocs/track_metadata/track_metadata_bloc.dart

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../services/audio_service.dart';

// Import Services and Models
import '../../services/collection_service.dart'; // For CollectionService

part 'track_metadata_event.dart';
part 'track_metadata_state.dart';

/// BLoC responsible for handling updates to individual track metadata
/// (rating, comment, general tags) for the active collection.
/// It does not hold the track list itself but signals success/failure.
class TrackMetadataBloc extends Bloc<TrackMetadataEvent, TrackMetadataState> {
  final CollectionService _collectionService;

  TrackMetadataBloc(this._collectionService) : super(TrackMetadataInitial()) {
    on<UpdateTrackRating>(_onUpdateTrackRating);
    on<UpdateTrackComment>(_onUpdateTrackComment);
    on<AddTrackGeneralTag>(_onAddTrackGeneralTag);
    on<RemoveTrackGeneralTag>(_onRemoveTrackGeneralTag);
    on<UpdateTrackMarkers>(_onUpdateTrackMarkers);
    on<UpdateTrackDuration>(_onUpdateTrackDuration);
  }

  Future<void> _onUpdateTrackDuration(
    UpdateTrackDuration event,
    Emitter<TrackMetadataState> emit,
  ) async {
    // Emit updating state *only* if we want UI feedback during this specific update.
    // Since it might happen in the background, maybe just success/error is enough.
    // emit(TrackMetadataUpdating(trackId: event.trackId));
    try {
      await _collectionService.updateTrackDuration(
        event.trackId,
        event.durationMs,
      );
      // Emit success - the UI (e.g., HomeScreen) should listen for this
      // and trigger a reload in TrackDataBloc to get the updated track list.
      emit(TrackMetadataUpdateSuccess(trackId: event.trackId));
      print(
        "TrackMetadataBloc: Duration update successful for track ${event.trackId}",
      );
    } catch (e) {
      print('TrackMetadataBloc Error updating duration: $e');
      emit(
        TrackMetadataUpdateError(
          trackId: event.trackId,
          message: "Failed to update duration: ${e.toString()}",
        ),
      );
    }
  }

  Future<void> _onUpdateTrackMarkers(
    UpdateTrackMarkers event,
    Emitter<TrackMetadataState> emit,
  ) async {
    emit(TrackMetadataUpdating(trackId: event.trackId));
    try {
      await _collectionService.updateTrackMarkers(event.trackId, event.markers);
      print(
        "TrackMetadataBloc: Updated ${event.markers.length} markers for track ${event.trackId}",
      );
      emit(TrackMetadataUpdateSuccess(trackId: event.trackId));
    } catch (e) {
      print('TrackMetadataBloc Error updating markers: $e');
      emit(
        TrackMetadataUpdateError(
          trackId: event.trackId,
          message: "Failed to update markers: ${e.toString()}",
        ),
      );
    }
  }

  Future<void> _onUpdateTrackRating(
    UpdateTrackRating event,
    Emitter<TrackMetadataState> emit,
  ) async {
    emit(TrackMetadataUpdating(trackId: event.trackId));
    try {
      await _collectionService.updateRating(event.trackId, event.rating);
      print(
        "TrackMetadataBloc: Updated rating for track ${event.trackId} to ${event.rating}",
      );
      emit(TrackMetadataUpdateSuccess(trackId: event.trackId));
    } catch (e) {
      print('TrackMetadataBloc Error updating rating: $e');
      emit(
        TrackMetadataUpdateError(
          trackId: event.trackId,
          message: "Failed to update rating: ${e.toString()}",
        ),
      );
    }
  }

  Future<void> _onUpdateTrackComment(
    UpdateTrackComment event,
    Emitter<TrackMetadataState> emit,
  ) async {
    emit(TrackMetadataUpdating(trackId: event.trackId));
    try {
      await _collectionService.updateComment(event.trackId, event.comment);
      print("TrackMetadataBloc: Updated comment for track ${event.trackId}");
      emit(TrackMetadataUpdateSuccess(trackId: event.trackId));
    } catch (e) {
      print('TrackMetadataBloc Error updating comment: $e');
      emit(
        TrackMetadataUpdateError(
          trackId: event.trackId,
          message: "Failed to update comment: ${e.toString()}",
        ),
      );
    }
  }

  Future<void> _onAddTrackGeneralTag(
    AddTrackGeneralTag event,
    Emitter<TrackMetadataState> emit,
  ) async {
    emit(TrackMetadataUpdating(trackId: event.trackId));
    try {
      // Note: CollectionService.addGeneralTag handles checking for duplicates
      await _collectionService.addGeneralTag(event.trackId, event.tag);
      print(
        "TrackMetadataBloc: Added tag '${event.tag}' for track ${event.trackId}",
      );
      emit(TrackMetadataUpdateSuccess(trackId: event.trackId));
    } catch (e) {
      print('TrackMetadataBloc Error adding general tag: $e');
      emit(
        TrackMetadataUpdateError(
          trackId: event.trackId,
          message: "Failed to add tag: ${e.toString()}",
        ),
      );
    }
  }

  Future<void> _onRemoveTrackGeneralTag(
    RemoveTrackGeneralTag event,
    Emitter<TrackMetadataState> emit,
  ) async {
    emit(TrackMetadataUpdating(trackId: event.trackId));
    try {
      await _collectionService.removeGeneralTag(event.trackId, event.tag);
      print(
        "TrackMetadataBloc: Removed tag '${event.tag}' for track ${event.trackId}",
      );
      emit(TrackMetadataUpdateSuccess(trackId: event.trackId));
    } catch (e) {
      print('TrackMetadataBloc Error removing general tag: $e');
      emit(
        TrackMetadataUpdateError(
          trackId: event.trackId,
          message: "Failed to remove tag: ${e.toString()}",
        ),
      );
    }
  }
}
