// lib/blocs/track_metadata/track_metadata_event.dart

part of 'track_metadata_bloc.dart';

abstract class TrackMetadataEvent extends Equatable {
  const TrackMetadataEvent();
  @override
  List<Object?> get props => [];
}

/// Event to update the rating of a specific track.
class UpdateTrackRating extends TrackMetadataEvent {
  final int trackId;
  final int rating;
  const UpdateTrackRating(this.trackId, this.rating);
  @override
  List<Object?> get props => [trackId, rating];
}

/// Event to update the comment/notes of a specific track.
class UpdateTrackComment extends TrackMetadataEvent {
  final int trackId;
  final String comment;
  const UpdateTrackComment(this.trackId, this.comment);
  @override
  List<Object?> get props => [trackId, comment];
}

/// Event to add a general tag to a specific track.
class AddTrackGeneralTag extends TrackMetadataEvent {
  final int trackId;
  final String tag;
  const AddTrackGeneralTag(this.trackId, this.tag);
  @override
  List<Object?> get props => [trackId, tag];
}

/// Event to remove a general tag from a specific track.
class RemoveTrackGeneralTag extends TrackMetadataEvent {
  final int trackId;
  final String tag;
  const RemoveTrackGeneralTag(this.trackId, this.tag);
  @override
  List<Object?> get props => [trackId, tag];
}
