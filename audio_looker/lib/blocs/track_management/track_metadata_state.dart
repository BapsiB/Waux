// lib/blocs/track_metadata/track_metadata_state.dart

part of 'track_metadata_bloc.dart';

abstract class TrackMetadataState extends Equatable {
  const TrackMetadataState();
  @override
  List<Object?> get props => [];
}

/// Initial state, no metadata operation in progress.
class TrackMetadataInitial extends TrackMetadataState {}

/// State indicating a metadata update is in progress for a specific track.
class TrackMetadataUpdating extends TrackMetadataState {
  final int trackId;
  const TrackMetadataUpdating({required this.trackId});
  @override
  List<Object?> get props => [trackId];
}

/// State indicating a metadata update succeeded for a specific track.
/// The UI layer should listen for this and trigger a reload in TrackDataBloc.
class TrackMetadataUpdateSuccess extends TrackMetadataState {
  final int trackId;
  const TrackMetadataUpdateSuccess({required this.trackId});
  @override
  List<Object?> get props => [trackId];
}

/// State indicating a metadata update failed for a specific track.
class TrackMetadataUpdateError extends TrackMetadataState {
  final int trackId;
  final String message;
  const TrackMetadataUpdateError({
    required this.trackId,
    required this.message,
  });
  @override
  List<Object?> get props => [trackId, message];
}
