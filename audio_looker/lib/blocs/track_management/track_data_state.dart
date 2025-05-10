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
  final List<Track>? previousTracks;
  final List<String>? previousRootFolders;
  final String? searchQuery;
  final int? minimumRating;
  final String? selectedPlaylistId; // <<< ADDED

  const TrackDataLoading({
    this.previousTracks,
    this.previousRootFolders,
    this.searchQuery,
    this.minimumRating,
    this.selectedPlaylistId, // <<< ADDED
  });

  @override
  List<Object?> get props => [
    previousTracks,
    previousRootFolders,
    searchQuery,
    minimumRating,
    selectedPlaylistId, // <<< ADDED
  ];
}

/// State when tracks and root folders for the active collection are loaded.
class TrackDataLoaded extends TrackDataState {
  final List<Track> tracks;
  final List<String> rootFolders;
  final String? searchQuery;
  final int? minimumRating;
  final String? selectedPlaylistId; // <<< ADDED

  const TrackDataLoaded({
    required this.tracks,
    required this.rootFolders,
    this.searchQuery,
    this.minimumRating,
    this.selectedPlaylistId, // <<< ADDED
  });

  /// Creates a new instance of TrackDataLoaded with updated fields.
  TrackDataLoaded copyWith({
    List<Track>? tracks,
    List<String>? rootFolders,
    String? searchQuery,
    int? minimumRating,
    String? selectedPlaylistId, // <<< ADDED
    bool? forceSearchQueryToNull,
    bool? forceMinimumRatingToNull,
    bool?
    forceSelectedPlaylistIdToNull, // <<< ADDED helper for nulling playlist
  }) {
    final effectiveSearchQuery =
        forceSearchQueryToNull ?? false
            ? null
            : (searchQuery ?? this.searchQuery);
    final effectiveMinimumRating =
        forceMinimumRatingToNull ?? false
            ? null
            : (minimumRating ?? this.minimumRating);
    // <<< ADDED logic for playlist ID >>>
    final effectiveSelectedPlaylistId =
        forceSelectedPlaylistIdToNull ?? false
            ? null
            : (selectedPlaylistId ?? this.selectedPlaylistId);

    return TrackDataLoaded(
      tracks: tracks ?? this.tracks,
      rootFolders: rootFolders ?? this.rootFolders,
      searchQuery: effectiveSearchQuery,
      minimumRating: effectiveMinimumRating,
      selectedPlaylistId: effectiveSelectedPlaylistId, // <<< Use effective ID
    );
  }

  @override
  List<Object?> get props => [
    tracks,
    rootFolders,
    searchQuery,
    minimumRating,
    selectedPlaylistId, // <<< ADDED
  ];
}

// In track_data_state.dart
class NewFilesDetected extends TrackDataState {
  final List<String> newFilePaths;
  final List<Track> currentTracks;
  final List<String> rootFolders;
  // Optionally add filters/playlist ID if needed to restore state after handling
  final String? searchQuery;
  final int? minimumRating;
  final String? selectedPlaylistId;

  const NewFilesDetected({
    required this.newFilePaths,
    required this.currentTracks,
    required this.rootFolders,
    this.searchQuery,
    this.minimumRating,
    this.selectedPlaylistId,
  });

  @override
  List<Object?> get props => [
    newFilePaths,
    currentTracks,
    rootFolders,
    searchQuery,
    minimumRating,
    selectedPlaylistId,
  ];
}

class TrackDataProcessingNeeded extends TrackDataState {
  final List<Track> addedTracks;
  final List<Track> tracks;
  final List<String> rootFolders;
  final String? searchQuery;
  final int? minimumRating;
  final String? selectedPlaylistId; // <<< ADDED

  const TrackDataProcessingNeeded({
    required this.addedTracks,
    required this.tracks,
    required this.rootFolders,
    this.searchQuery,
    this.minimumRating,
    this.selectedPlaylistId, // <<< ADDED
  });

  @override
  List<Object?> get props => [
    addedTracks,
    tracks,
    rootFolders,
    searchQuery,
    minimumRating,
    selectedPlaylistId, // <<< ADDED
  ];
}

/// State representing an error during track/folder loading or operations.
class TrackDataError extends TrackDataState {
  final String message;
  // Optionally preserve previous state info on error
  final List<Track>? previousTracks;
  final List<String>? previousRootFolders;
  final String? searchQuery;
  final int? minimumRating;
  final String? selectedPlaylistId;

  const TrackDataError(
    this.message, {
    this.previousTracks,
    this.previousRootFolders,
    this.searchQuery,
    this.minimumRating,
    this.selectedPlaylistId,
  });

  @override
  List<Object?> get props => [
    message,
    previousTracks,
    previousRootFolders,
    searchQuery,
    minimumRating,
    selectedPlaylistId,
  ];
}

class FolderDeletionConfirmationNeeded extends TrackDataState {
  final String folderPath;
  final String folderName;
  final int trackCount;
  // Optionally add filters/playlist ID if needed to restore state after handling
  final String? searchQuery;
  final int? minimumRating;
  final String? selectedPlaylistId;

  const FolderDeletionConfirmationNeeded({
    required this.folderPath,
    required this.folderName,
    required this.trackCount,
    this.searchQuery,
    this.minimumRating,
    this.selectedPlaylistId,
  });

  @override
  List<Object?> get props => [
    folderPath,
    folderName,
    trackCount,
    searchQuery,
    minimumRating,
    selectedPlaylistId,
  ];
}

// Helper class for moved file information
class MovedFileUpdate extends Equatable {
  final int trackId; // ID of the track in the database
  final String oldPath; // The old absolute path
  final String newPath; // The new absolute path
  final String trackTitle; // For display purposes in the dialog

  const MovedFileUpdate({
    required this.trackId,
    required this.oldPath,
    required this.newPath,
    required this.trackTitle,
  });

  @override
  List<Object?> get props => [trackId, oldPath, newPath, trackTitle];
}

class FilesystemChangesDetected extends TrackDataState {
  final List<String>
  newFilePaths; // Paths of files on disk, not in DB (candidates for adding)
  final List<Track>
  deletedTracks; // Track objects from DB that are no longer on disk (candidates for removal)
  final List<MovedFileUpdate>
  movedFileUpdates; // Files detected as moved (path will be updated in DB)

  // These fields help restore the UI's previous view state if the dialog is part of the main screen
  final List<Track> currentTracksInUI;
  final List<String> currentRootFoldersInUI;
  final String? currentSearchQuery;
  final int? currentMinimumRating;
  final String? currentSelectedPlaylistId;

  const FilesystemChangesDetected({
    required this.newFilePaths,
    required this.deletedTracks,
    required this.movedFileUpdates,
    required this.currentTracksInUI,
    required this.currentRootFoldersInUI,
    this.currentSearchQuery,
    this.currentMinimumRating,
    this.currentSelectedPlaylistId,
  });

  /// Utility getter to quickly check if there are any changes to report.
  bool get hasChanges =>
      newFilePaths.isNotEmpty ||
      deletedTracks.isNotEmpty ||
      movedFileUpdates.isNotEmpty;

  @override
  List<Object?> get props => [
    newFilePaths,
    deletedTracks,
    movedFileUpdates,
    currentTracksInUI,
    currentRootFoldersInUI,
    currentSearchQuery,
    currentMinimumRating,
    currentSelectedPlaylistId,
  ];
}

class TrackDataDeletingFolder extends TrackDataState {
  final List<Track>? previousTracks;
  final List<String>? previousRootFolders;
  final String? searchQuery;
  final int? minimumRating;
  final String? selectedPlaylistId; // <<< ADDED

  const TrackDataDeletingFolder({
    this.previousTracks,
    this.previousRootFolders,
    this.searchQuery,
    this.minimumRating,
    this.selectedPlaylistId, // <<< ADDED
  });

  @override
  List<Object?> get props => [
    previousTracks,
    previousRootFolders,
    searchQuery,
    minimumRating,
    selectedPlaylistId, // <<< ADDED
  ];
}
