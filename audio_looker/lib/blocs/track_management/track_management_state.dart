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

  // --- NEW: Waveform Processing Progress ---
  final double?
  waveformProcessingProgress; // 0.0 to 1.0, null if not processing
  final String? waveformProcessingMessage;
  final int? currentMinimumRating;

  const TrackManagementLoading({
    this.currentTracks,
    this.currentAllTags,
    this.currentRootFolders,
    this.currentSearchQuery,
    this.currentMinimumRating,
    this.waveformProcessingProgress,
    this.waveformProcessingMessage,
  });

  TrackManagementLoading copyWith({
    List<Track>? currentTracks,
    List<Tag>? currentAllTags,
    List<String>? currentRootFolders,
    String? currentSearchQuery,
    int? currentMinimumRating,
    double? waveformProcessingProgress,
    bool clearWaveformProgress = false, // Flag to explicitly clear
    String? waveformProcessingMessage,
  }) {
    return TrackManagementLoading(
      currentTracks: currentTracks ?? this.currentTracks,
      currentAllTags: currentAllTags ?? this.currentAllTags,
      currentRootFolders: currentRootFolders ?? this.currentRootFolders,
      currentSearchQuery: currentSearchQuery ?? this.currentSearchQuery,
      // --- NEW ---
      waveformProcessingProgress:
          clearWaveformProgress
              ? null
              : waveformProcessingProgress ?? this.waveformProcessingProgress,
      waveformProcessingMessage:
          clearWaveformProgress
              ? null
              : waveformProcessingMessage ?? this.waveformProcessingMessage,
      // --- END NEW ---
    );
  }

  @override
  List<Object?> get props => [
    currentTracks,
    currentAllTags,
    currentRootFolders,
    currentSearchQuery,
    waveformProcessingProgress,
    waveformProcessingMessage,
    currentMinimumRating,
  ];
}

// State when tracks and related data for the active collection are loaded
class TrackManagementLoaded extends TrackManagementState {
  final List<Track> tracks;
  final List<String> rootFolders;
  final List<Tag> allTags;
  final String? searchQuery;
  final int? minimumRating; // <<< ADDED

  const TrackManagementLoaded({
    required this.tracks,
    required this.rootFolders,
    required this.allTags,
    this.searchQuery,
    this.minimumRating, // <<< ADDED
  });

  @override
  List<Object?> get props => [
    tracks,
    rootFolders,
    allTags,
    searchQuery,
    minimumRating,
  ]; // <<< ADDED

  TrackManagementLoaded copyWith({
    List<Track>? tracks,
    List<String>? rootFolders,
    List<Tag>? allTags,
    String? searchQuery,
    bool clearSearchQuery = false,
    int? minimumRating, // <<< ADDED
    bool clearMinimumRating = false, // <<< Optional: Flag to clear rating
  }) {
    return TrackManagementLoaded(
      tracks: tracks ?? this.tracks,
      rootFolders: rootFolders ?? this.rootFolders,
      allTags: allTags ?? this.allTags,
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      minimumRating:
          clearMinimumRating
              ? null
              : (minimumRating ?? this.minimumRating), // <<< ADDED
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

class TrackManagementProcessingWaveforms extends TrackManagementState {
  final List<Track> tracks; // Show current tracks while processing
  final List<Tag> allTags;
  final List<String> rootFolders;
  final String? searchQuery; // Preserve search query
  final int processedCount; // Number of waveforms processed
  final int totalCount; // Total waveforms to process
  final int? minimumRating;

  const TrackManagementProcessingWaveforms({
    required this.tracks,
    required this.allTags,
    required this.rootFolders,
    this.searchQuery,
    required this.processedCount,
    required this.totalCount,
    this.minimumRating,
  });

  @override
  List<Object?> get props => [
    tracks,
    allTags,
    rootFolders,
    searchQuery,
    processedCount,
    totalCount,
    minimumRating,
  ];

  // Optional: Add copyWith if needed for internal state updates
  TrackManagementProcessingWaveforms copyWith({
    List<Track>? tracks,
    List<Tag>? allTags,
    List<String>? rootFolders,
    String? searchQuery,
    int? processedCount,
    int? totalCount,
    bool clearSearchQuery = false,
    int? minimumRating,
  }) {
    return TrackManagementProcessingWaveforms(
      tracks: tracks ?? this.tracks,
      allTags: allTags ?? this.allTags,
      rootFolders: rootFolders ?? this.rootFolders,
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      processedCount: processedCount ?? this.processedCount,
      totalCount: totalCount ?? this.totalCount,
    );
  }
}
