// lib/blocs/track_management/track_management_event.dart

part of 'track_management_bloc.dart';

abstract class TrackManagementEvent extends Equatable {
  const TrackManagementEvent();
  @override
  List<Object?> get props => [];
}

// Event to load data for the currently active collection
class LoadTracksForActiveCollection extends TrackManagementEvent {}

// Track Addition Events
class AddTrackFromPath extends TrackManagementEvent {
  final String filePath;
  const AddTrackFromPath(this.filePath);
  @override
  List<Object> get props => [filePath];
}

class AddTracksFromPaths extends TrackManagementEvent {
  final List<String> filePaths;
  const AddTracksFromPaths(this.filePaths);
  @override
  List<Object> get props => [filePaths];
}

class AddTrackFromUrl extends TrackManagementEvent {
  final String url;
  const AddTrackFromUrl(this.url);
  @override
  List<Object?> get props => [url];
}

// Track Removal Event
class RemoveTrack extends TrackManagementEvent {
  final int trackId;
  const RemoveTrack(this.trackId);
  @override
  List<Object?> get props => [trackId];
}

// Search Event
class SearchTracks extends TrackManagementEvent {
  final String query;
  const SearchTracks(this.query);
  @override
  List<Object?> get props => [query];
}

// Metadata Update Events
class UpdateTrackRating extends TrackManagementEvent {
  final int trackId;
  final int rating;
  const UpdateTrackRating(this.trackId, this.rating);
  @override
  List<Object?> get props => [trackId, rating];
}

class SetMinimumRatingFilter extends TrackManagementEvent {
  final int? rating; // Nullable to represent "All"
  const SetMinimumRatingFilter(this.rating);
  @override
  List<Object?> get props => [rating];
}

class UpdateTrackComment extends TrackManagementEvent {
  final int trackId;
  final String comment;
  const UpdateTrackComment(this.trackId, this.comment);
  @override
  List<Object?> get props => [trackId, comment];
}

class AddTrackGeneralTag extends TrackManagementEvent {
  final int trackId;
  final String tag;
  const AddTrackGeneralTag(this.trackId, this.tag);
  @override
  List<Object?> get props => [trackId, tag];
}

class RemoveTrackGeneralTag extends TrackManagementEvent {
  final int trackId;
  final String tag;
  const RemoveTrackGeneralTag(this.trackId, this.tag);
  @override
  List<Object?> get props => [trackId, tag];
}

// Root Folder Events (for Local Collections)
class AddRootFolder extends TrackManagementEvent {
  final String folderPath;
  const AddRootFolder(this.folderPath);
  @override
  List<Object> get props => [folderPath];
}

class RemoveRootFolder extends TrackManagementEvent {
  final String folderPath;
  const RemoveRootFolder(this.folderPath);
  @override
  List<Object> get props => [folderPath];
}

// Global Tag Management Events
class LoadAllTags extends TrackManagementEvent {}

class CreateGeneralTag extends TrackManagementEvent {
  final String tagName;
  const CreateGeneralTag(this.tagName);
  @override
  List<Object> get props => [tagName];
}

class DeleteGeneralTag extends TrackManagementEvent {
  final String tagName;
  const DeleteGeneralTag(this.tagName);
  @override
  List<Object> get props => [tagName];
}

class SetGeneralTagColor extends TrackManagementEvent {
  final String tagName;
  final int? colorValue; // Store color as int
  const SetGeneralTagColor(this.tagName, this.colorValue);
  @override
  List<Object?> get props => [tagName, colorValue];
}

// Import / Export Events (for Active Collection)
class ImportCollectionFromFile extends TrackManagementEvent {
  final String path;
  const ImportCollectionFromFile(this.path);
  @override
  List<Object?> get props => [path];
}

class ExportCollectionToFile extends TrackManagementEvent {
  final String path;
  const ExportCollectionToFile(this.path);
  @override
  List<Object?> get props => [path];
}

class SyncActiveCollectionFolders extends TrackManagementEvent {}
