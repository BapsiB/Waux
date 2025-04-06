// lib/blocs/playlist/playlist_bloc.dart

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/playlist.dart'; // Adjust import path as needed
import '../../services/playlist_service.dart'; // Adjust import path as needed

part 'playlist_event.dart';
part 'playlist_state.dart';

/// BLoC responsible for managing the state of playlists.
class PlaylistBloc extends Bloc<PlaylistEvent, PlaylistState> {
  final PlaylistService _playlistService;

  PlaylistBloc({required PlaylistService playlistService})
    : _playlistService = playlistService,
      super(PlaylistInitial()) {
    // Register event handlers
    on<LoadPlaylists>(_onLoadPlaylists);
    on<CreatePlaylist>(_onCreatePlaylist);
    on<DeletePlaylist>(_onDeletePlaylist);
    on<AddTrackToPlaylist>(_onAddTrackToPlaylist);
    on<RemoveTrackFromPlaylist>(_onRemoveTrackFromPlaylist);
    on<RenamePlaylist>(_onRenamePlaylist);
  }

  /// Handles the LoadPlaylists event.
  Future<void> _onLoadPlaylists(
    LoadPlaylists event,
    Emitter<PlaylistState> emit,
  ) async {
    emit(PlaylistLoading());
    try {
      final playlists = await _playlistService.loadPlaylists();
      emit(PlaylistLoaded(playlists));
      print("PlaylistBloc: Playlists loaded successfully.");
    } catch (e) {
      print("PlaylistBloc: Error loading playlists: $e");
      emit(PlaylistError("Failed to load playlists: ${e.toString()}"));
    }
  }

  /// Handles the CreatePlaylist event.
  Future<void> _onCreatePlaylist(
    CreatePlaylist event,
    Emitter<PlaylistState> emit,
  ) async {
    if (state is PlaylistLoaded) {
      final currentState = state as PlaylistLoaded;
      emit(PlaylistLoading()); // Indicate loading while saving
      try {
        final newPlaylist = Playlist(name: event.name);
        await _playlistService.savePlaylist(newPlaylist);
        // Reload playlists to get the updated list including the new one
        final updatedPlaylists = await _playlistService.loadPlaylists();
        emit(PlaylistLoaded(updatedPlaylists));
        print("PlaylistBloc: Playlist '${event.name}' created.");
      } catch (e) {
        print("PlaylistBloc: Error creating playlist: $e");
        emit(PlaylistError("Failed to create playlist: ${e.toString()}"));
        // Optionally revert to previous loaded state
        emit(currentState);
      }
    } else {
      print(
        "PlaylistBloc: Cannot create playlist, state is not PlaylistLoaded.",
      );
      // Handle case where playlists haven't been loaded yet
      add(LoadPlaylists()); // Try loading first
    }
  }

  /// Handles the DeletePlaylist event.
  Future<void> _onDeletePlaylist(
    DeletePlaylist event,
    Emitter<PlaylistState> emit,
  ) async {
    if (state is PlaylistLoaded) {
      final currentState = state as PlaylistLoaded;
      // Optimistic UI update: Remove immediately from the current state
      final optimisticPlaylists =
          currentState.playlists
              .where((p) => p.id != event.playlistId)
              .toList();
      emit(PlaylistLoaded(optimisticPlaylists));
      print(
        "PlaylistBloc: Optimistically removed playlist ID ${event.playlistId}.",
      );

      try {
        await _playlistService.deletePlaylist(event.playlistId);
        // No need to reload, the optimistic update is now confirmed
        print(
          "PlaylistBloc: Playlist ID ${event.playlistId} deleted from service.",
        );
      } catch (e) {
        print(
          "PlaylistBloc: Error deleting playlist ID ${event.playlistId}: $e",
        );
        emit(PlaylistError("Failed to delete playlist: ${e.toString()}"));
        // Revert to the previous state if deletion failed
        emit(currentState);
      }
    } else {
      print(
        "PlaylistBloc: Cannot delete playlist, state is not PlaylistLoaded.",
      );
    }
  }

  /// Handles the AddTrackToPlaylist event.
  Future<void> _onAddTrackToPlaylist(
    AddTrackToPlaylist event,
    Emitter<PlaylistState> emit,
  ) async {
    if (state is PlaylistLoaded) {
      final currentState = state as PlaylistLoaded;
      // Find the playlist to update
      final playlistIndex = currentState.playlists.indexWhere(
        (p) => p.id == event.playlistId,
      );

      if (playlistIndex != -1) {
        final playlist = currentState.playlists[playlistIndex];
        // Avoid adding duplicates
        if (!playlist.trackPaths.contains(event.trackPath)) {
          // Optimistic UI update
          final updatedPaths = List<String>.from(playlist.trackPaths)
            ..add(event.trackPath);
          final updatedPlaylist = playlist.copyWith(trackPaths: updatedPaths);
          final optimisticPlaylists = List<Playlist>.from(
            currentState.playlists,
          );
          optimisticPlaylists[playlistIndex] = updatedPlaylist;
          emit(PlaylistLoaded(optimisticPlaylists));
          print(
            "PlaylistBloc: Optimistically added track ${event.trackPath} to playlist ID ${event.playlistId}.",
          );

          try {
            await _playlistService.addTrackToPlaylist(
              event.playlistId,
              event.trackPath,
            );
            print(
              "PlaylistBloc: Track ${event.trackPath} added to playlist ID ${event.playlistId} in service.",
            );
            // No need to reload, optimistic update confirmed
          } catch (e) {
            print(
              "PlaylistBloc: Error adding track to playlist ID ${event.playlistId}: $e",
            );
            emit(PlaylistError("Failed to add track: ${e.toString()}"));
            // Revert if error
            emit(currentState);
          }
        } else {
          print(
            "PlaylistBloc: Track ${event.trackPath} already in playlist ID ${event.playlistId}.",
          );
        }
      } else {
        print(
          "PlaylistBloc: Playlist ID ${event.playlistId} not found for adding track.",
        );
      }
    } else {
      print("PlaylistBloc: Cannot add track, state is not PlaylistLoaded.");
    }
  }

  /// Handles the RemoveTrackFromPlaylist event.
  Future<void> _onRemoveTrackFromPlaylist(
    RemoveTrackFromPlaylist event,
    Emitter<PlaylistState> emit,
  ) async {
    if (state is PlaylistLoaded) {
      final currentState = state as PlaylistLoaded;
      final playlistIndex = currentState.playlists.indexWhere(
        (p) => p.id == event.playlistId,
      );

      if (playlistIndex != -1) {
        final playlist = currentState.playlists[playlistIndex];
        if (playlist.trackPaths.contains(event.trackPath)) {
          // Optimistic UI update
          final updatedPaths = List<String>.from(playlist.trackPaths)
            ..remove(event.trackPath);
          final updatedPlaylist = playlist.copyWith(trackPaths: updatedPaths);
          final optimisticPlaylists = List<Playlist>.from(
            currentState.playlists,
          );
          optimisticPlaylists[playlistIndex] = updatedPlaylist;
          emit(PlaylistLoaded(optimisticPlaylists));
          print(
            "PlaylistBloc: Optimistically removed track ${event.trackPath} from playlist ID ${event.playlistId}.",
          );

          try {
            await _playlistService.removeTrackFromPlaylist(
              event.playlistId,
              event.trackPath,
            );
            print(
              "PlaylistBloc: Track ${event.trackPath} removed from playlist ID ${event.playlistId} in service.",
            );
            // No need to reload, optimistic update confirmed
          } catch (e) {
            print(
              "PlaylistBloc: Error removing track from playlist ID ${event.playlistId}: $e",
            );
            emit(PlaylistError("Failed to remove track: ${e.toString()}"));
            // Revert if error
            emit(currentState);
          }
        } else {
          print(
            "PlaylistBloc: Track ${event.trackPath} not found in playlist ID ${event.playlistId} for removal.",
          );
        }
      } else {
        print(
          "PlaylistBloc: Playlist ID ${event.playlistId} not found for removing track.",
        );
      }
    } else {
      print("PlaylistBloc: Cannot remove track, state is not PlaylistLoaded.");
    }
  }

  /// Handles the RenamePlaylist event.
  Future<void> _onRenamePlaylist(
    RenamePlaylist event,
    Emitter<PlaylistState> emit,
  ) async {
    if (state is PlaylistLoaded) {
      final currentState = state as PlaylistLoaded;
      final playlistIndex = currentState.playlists.indexWhere(
        (p) => p.id == event.playlistId,
      );

      if (playlistIndex != -1) {
        // Optimistic UI update
        final updatedPlaylist = currentState.playlists[playlistIndex].copyWith(
          name: event.newName,
        );
        final optimisticPlaylists = List<Playlist>.from(currentState.playlists);
        optimisticPlaylists[playlistIndex] = updatedPlaylist;
        emit(PlaylistLoaded(optimisticPlaylists));
        print(
          "PlaylistBloc: Optimistically renamed playlist ID ${event.playlistId} to '${event.newName}'.",
        );

        try {
          await _playlistService.renamePlaylist(
            event.playlistId,
            event.newName,
          );
          print(
            "PlaylistBloc: Playlist ID ${event.playlistId} renamed in service.",
          );
          // No need to reload, optimistic update confirmed
        } catch (e) {
          print(
            "PlaylistBloc: Error renaming playlist ID ${event.playlistId}: $e",
          );
          emit(PlaylistError("Failed to rename playlist: ${e.toString()}"));
          // Revert if error
          emit(currentState);
        }
      } else {
        print(
          "PlaylistBloc: Playlist ID ${event.playlistId} not found for renaming.",
        );
      }
    } else {
      print(
        "PlaylistBloc: Cannot rename playlist, state is not PlaylistLoaded.",
      );
    }
  }
}
