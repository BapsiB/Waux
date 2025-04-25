// lib/blocs/track_metadata/track_metadata_event.dart

part of 'track_metadata_bloc.dart';

abstract class TrackMetadataEvent extends Equatable {
  const TrackMetadataEvent();
  @override
  List<Object?> get props => [];
}

class UpdateTrackTitle extends TrackMetadataEvent {
  final int trackId;
  final String title;
  const UpdateTrackTitle(this.trackId, this.title);
  @override
  List<Object?> get props => [trackId, title];
}

/// Event to update the artist of a specific track.
class UpdateTrackArtist extends TrackMetadataEvent {
  final int trackId;
  final String artist;
  const UpdateTrackArtist(this.trackId, this.artist);
  @override
  List<Object?> get props => [trackId, artist];
}

/// Event to update the album of a specific track.
class UpdateTrackAlbum extends TrackMetadataEvent {
  final int trackId;
  final String album;
  const UpdateTrackAlbum(this.trackId, this.album);
  @override
  List<Object?> get props => [trackId, album];
}

/// Event to update the rating of a specific track.
class UpdateTrackRating extends TrackMetadataEvent {
  final int trackId;
  final int rating;
  const UpdateTrackRating(this.trackId, this.rating);
  @override
  List<Object?> get props => [trackId, rating];
}

class UpdateTrackDuration extends TrackMetadataEvent {
  final int trackId;
  final int durationMs;
  const UpdateTrackDuration(this.trackId, this.durationMs);
  @override
  List<Object?> get props => [trackId, durationMs];
}

class UpdateTrackMarkers extends TrackMetadataEvent {
  final int trackId;
  // --- TimeMarker type is recognized via the main bloc file's import ---
  final List<TimeMarker> markers;
  const UpdateTrackMarkers(this.trackId, this.markers);
  @override
  List<Object?> get props => [trackId, markers];
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
