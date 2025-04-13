// lib/blocs/track_data/track_data_state.dart

part of 'track_data_bloc.dart';

abstract class TrackDataState extends Equatable {
  const TrackDataState();
  @override
  List<Object?> get props => [];
}

/// Initial state before any collection data is requested.
class TrackDataInitial extends TrackDataState {}

/// State while loading tracks or root folders.
class TrackDataLoading extends TrackDataState {
  // Carry over previous state data for smoother transitions
  final List<Track>? previousTracks;
  final List<String>? previousRootFolders;
  final String? searchQuery; // Preserve search query during loading
  final int? minimumRating; // Preserve rating filter during loading

  const TrackDataLoading({
    this.previousTracks,
    this.previousRootFolders,
    this.searchQuery,
    this.minimumRating,
  });

  @override
  List<Object?> get props => [
    previousTracks,
    previousRootFolders,
    searchQuery,
    minimumRating,
  ];
}

/// State when tracks and root folders for the active collection are loaded.
class TrackDataLoaded extends TrackDataState {
  /// The list of tracks matching current filters (search, rating).
  final List<Track> tracks;

  /// The list of root folders for the active collection.
  final List<String> rootFolders;

  /// The current search query, if any.
  final String? searchQuery;

  /// The current minimum rating filter, if any.
  final int? minimumRating;

  const TrackDataLoaded({
    required this.tracks,
    required this.rootFolders,
    this.searchQuery,
    this.minimumRating,
  });

  @override
  List<Object?> get props => [tracks, rootFolders, searchQuery, minimumRating];
}

/// State representing an error during track/folder loading or operations.
class TrackDataError extends TrackDataState {
  final String message;

  const TrackDataError(this.message);

  @override
  List<Object?> get props => [message];
}

class FolderDeletionConfirmationNeeded extends TrackDataState {
  final String folderPath;
  final String folderName; // Display name for the dialog
  final int trackCount; // Number of tracks within

  const FolderDeletionConfirmationNeeded({
    required this.folderPath,
    required this.folderName,
    required this.trackCount,
  });

  @override
  List<Object?> get props => [folderPath, folderName, trackCount];
}

class TrackDataDeletingFolder extends TrackDataState {
  // Optionally carry over previous data like TrackDataLoading
  final List<Track>? previousTracks;
  final List<String>? previousRootFolders;
  final String? searchQuery;
  final int? minimumRating;

  const TrackDataDeletingFolder({
    this.previousTracks,
    this.previousRootFolders,
    this.searchQuery,
    this.minimumRating,
  });

  @override
  List<Object?> get props => [
    previousTracks,
    previousRootFolders,
    searchQuery,
    minimumRating,
  ];
}
