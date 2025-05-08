// lib/blocs/track_data/track_data_event.dart

part of 'track_data_bloc.dart';

abstract class TrackDataEvent extends Equatable {
  const TrackDataEvent();
  @override
  List<Object?> get props => [];
}

/// Event to load tracks and root folders for the active collection.
class LoadTracks extends TrackDataEvent {}

/// Event to reload track/folder data, preserving current filters.
class ReloadDataPreservingFilters extends TrackDataEvent {}

/// Event to search tracks within the active collection.
class SearchTracks extends TrackDataEvent {
  final String query;
  const SearchTracks(this.query);
  @override
  List<Object?> get props => [query];
}

class UpdateTrackWaveform extends TrackDataEvent {
  final String trackId;
  final List<double>? waveformData; // Use List<double>? or appropriate type

  const UpdateTrackWaveform({
    required this.trackId,
    required this.waveformData,
  });

  @override
  List<Object?> get props => [trackId, waveformData];
}

class CheckForNewFiles extends TrackDataEvent {}

class AddDetectedFiles extends TrackDataEvent {
  final List<String> filePathsToAdd;
  const AddDetectedFiles(this.filePathsToAdd);
  @override
  List<Object> get props => [filePathsToAdd];
}

class SkipDetectedFiles extends TrackDataEvent {}

/// Event to set the minimum rating filter.
class SetRatingFilter extends TrackDataEvent {
  final int? rating; // Nullable to represent "All"
  const SetRatingFilter(this.rating);
  @override
  List<Object?> get props => [rating];
}

/// Event to trigger synchronization of files within root folders.
class SyncFolders extends TrackDataEvent {}

/// Event to add tracks from a list of file paths.
class AddTracks extends TrackDataEvent {
  final List<String> filePaths;
  const AddTracks(this.filePaths);
  @override
  List<Object> get props => [filePaths];
}

class SetPlaylistFilter extends TrackDataEvent {
  final String? playlistId; // Nullable to clear the filter
  const SetPlaylistFilter(this.playlistId);
  @override
  List<Object?> get props => [playlistId];
}

/// Event to add a track from a URL.
class AddTrackUrl extends TrackDataEvent {
  final String url;
  const AddTrackUrl(this.url);
  @override
  List<Object?> get props => [url];
}

/// Event to remove a track by its ID.
class RemoveTrack extends TrackDataEvent {
  final int trackId;
  const RemoveTrack(this.trackId);
  @override
  List<Object?> get props => [trackId];
}

/// Event to add a root folder (for local collections).
class AddRootFolder extends TrackDataEvent {
  final String folderPath;
  const AddRootFolder(this.folderPath);
  @override
  List<Object> get props => [folderPath];
}

/// Event to remove a root folder (for local collections).
class RemoveRootFolder extends TrackDataEvent {
  final String folderPath;
  const RemoveRootFolder(this.folderPath);
  @override
  List<Object> get props => [folderPath];
}

class DeleteFolder extends TrackDataEvent {
  final String folderPath; // The actual path of the folder
  const DeleteFolder(this.folderPath);
  @override
  List<Object?> get props => [folderPath];
}

/// Event dispatched after user confirms whether to delete folder files from disk.
class ConfirmDeleteFolderFiles extends TrackDataEvent {
  final String folderPath;
  final bool deleteFilesFromDisk;
  const ConfirmDeleteFolderFiles(this.folderPath, this.deleteFilesFromDisk);
  @override
  List<Object?> get props => [folderPath, deleteFilesFromDisk];
}
