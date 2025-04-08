// lib/blocs/track_management/track_management_state.dart

part of 'track_management_bloc.dart';

abstract class TrackManagementState extends Equatable {
  const TrackManagementState();
  @override
  List<Object?> get props => [];
}

// Initial state before any collection data is loaded
class TrackManagementInitial extends TrackManagementState {}

// State while loading tracks, tags, or root folders for the active collection
class TrackManagementLoading extends TrackManagementState {
  // Optionally carry over previous state data for smoother transitions
  final List<Track>? currentTracks;
  final List<Tag>? currentAllTags;
  final List<String>? currentRootFolders;
  final String? currentSearchQuery; // Preserve search query during loading

  const TrackManagementLoading({
    this.currentTracks,
    this.currentAllTags,
    this.currentRootFolders,
    this.currentSearchQuery,
  });

  TrackManagementLoading copyWith({
    List<Track>? currentTracks,
    List<Tag>? currentAllTags,
    List<String>? currentRootFolders,
    String? currentSearchQuery,
  }) {
    return TrackManagementLoading(
      currentTracks: currentTracks ?? this.currentTracks,
      currentAllTags: currentAllTags ?? this.currentAllTags,
      currentRootFolders: currentRootFolders ?? this.currentRootFolders,
      currentSearchQuery: currentSearchQuery ?? this.currentSearchQuery,
    );
  }

  @override
  List<Object?> get props => [
    currentTracks,
    currentAllTags,
    currentRootFolders,
    currentSearchQuery,
  ];
}

// State when tracks and related data for the active collection are loaded
class TrackManagementLoaded extends TrackManagementState {
  final List<Track> tracks;
  final List<String>
  rootFolders; // Specific to the active collection (if local)
  final List<Tag> allTags; // Global tag definitions
  final String? searchQuery; // Current search term, null if not searching

  const TrackManagementLoaded({
    required this.tracks,
    required this.rootFolders,
    required this.allTags,
    this.searchQuery,
  });

  @override
  List<Object?> get props => [tracks, rootFolders, allTags, searchQuery];

  // Helper for easy state updates (e.g., optimistic updates)
  TrackManagementLoaded copyWith({
    List<Track>? tracks,
    List<String>? rootFolders,
    List<Tag>? allTags,
    String? searchQuery,
    bool clearSearchQuery = false, // Flag to explicitly clear search
  }) {
    return TrackManagementLoaded(
      tracks: tracks ?? this.tracks,
      rootFolders: rootFolders ?? this.rootFolders,
      allTags: allTags ?? this.allTags,
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
    );
  }
}

// State representing an error during track/tag/folder operations
class TrackManagementError extends TrackManagementState {
  final String message;
  // Optionally include previous data if available, to allow UI to show something
  final List<Track>? tracks;
  final List<String>? rootFolders;
  // Global tags are less likely to be the source of error, but could be included
  // final List<Tag>? allTags;

  const TrackManagementError(this.message, {this.tracks, this.rootFolders});

  @override
  List<Object?> get props => [message, tracks, rootFolders];
}
