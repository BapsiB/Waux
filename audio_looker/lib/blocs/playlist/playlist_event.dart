// lib/blocs/playlist/playlist_event.dart

part of 'playlist_bloc.dart';

/// Base class for all playlist events.
abstract class PlaylistEvent extends Equatable {
  const PlaylistEvent();

  @override
  List<Object> get props => [];
}

/// Event to trigger loading playlists from the service.
class LoadPlaylists extends PlaylistEvent {}

/// Event to create a new playlist.
class CreatePlaylist extends PlaylistEvent {
  /// The name for the new playlist.
  final String name;

  const CreatePlaylist(this.name);

  @override
  List<Object> get props => [name];
}

/// Event to delete an existing playlist.
class DeletePlaylist extends PlaylistEvent {
  /// The ID of the playlist to delete.
  final String playlistId;

  const DeletePlaylist(this.playlistId);

  @override
  List<Object> get props => [playlistId];
}

/// Event to add a track to a specific playlist.
class AddTrackToPlaylist extends PlaylistEvent {
  /// The ID of the target playlist.
  final String playlistId;

  /// The file path of the track to add.
  final String trackPath;

  const AddTrackToPlaylist({required this.playlistId, required this.trackPath});

  @override
  List<Object> get props => [playlistId, trackPath];
}

/// Event to remove a track from a specific playlist.
class RemoveTrackFromPlaylist extends PlaylistEvent {
  /// The ID of the target playlist.
  final String playlistId;

  /// The file path of the track to remove.
  final String trackPath;

  const RemoveTrackFromPlaylist({
    required this.playlistId,
    required this.trackPath,
  });

  @override
  List<Object> get props => [playlistId, trackPath];
}

/// Event to rename a playlist.
class RenamePlaylist extends PlaylistEvent {
  final String playlistId;
  final String newName;

  const RenamePlaylist({required this.playlistId, required this.newName});

  @override
  List<Object> get props => [playlistId, newName];
}
