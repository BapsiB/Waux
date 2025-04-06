// lib/blocs/playlist/playlist_state.dart

part of 'playlist_bloc.dart';

/// Base class for all playlist states.
abstract class PlaylistState extends Equatable {
  const PlaylistState();

  @override
  List<Object> get props => [];
}

/// Initial state before playlists are loaded.
class PlaylistInitial extends PlaylistState {}

/// State indicating playlists are being loaded.
class PlaylistLoading extends PlaylistState {}

/// State representing successfully loaded playlists.
class PlaylistLoaded extends PlaylistState {
  /// The list of loaded playlists.
  final List<Playlist> playlists;

  const PlaylistLoaded([this.playlists = const []]);

  @override
  List<Object> get props => [playlists];
}

/// State indicating an error occurred during playlist operations.
class PlaylistError extends PlaylistState {
  /// The error message.
  final String message;

  const PlaylistError(this.message);

  @override
  List<Object> get props => [message];
}
