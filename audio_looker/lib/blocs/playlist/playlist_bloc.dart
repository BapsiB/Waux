import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

// Import models and the NEW PlaylistService and CollectionService
import '../../models/playlist.dart';
import '../../services/playlist_service.dart';
import '../../services/collection_service.dart'; // <<< Added dependency

part 'playlist_event.dart';
part 'playlist_state.dart'; // Keep existing states

/// BLoC responsible for managing the state of playlists for the *active* collection.
class PlaylistBloc extends Bloc<PlaylistEvent, PlaylistState> {
  final PlaylistService _playlistService;
  final CollectionService _collectionService; // <<< Added dependency

  // Constructor now requires CollectionService
  PlaylistBloc({
    required PlaylistService playlistService,
    required CollectionService collectionService, // <<< Added
  }) : _playlistService = playlistService,
       _collectionService = collectionService, // <<< Added
       super(PlaylistInitial()) {
    // Register event handlers (using new service methods)
    on<LoadPlaylists>(_onLoadPlaylists);
    on<CreatePlaylist>(_onCreatePlaylist);
    on<DeletePlaylist>(_onDeletePlaylist);
    on<AddTrackToPlaylist>(_onAddTrackToPlaylist);
    on<RemoveTrackFromPlaylist>(_onRemoveTrackFromPlaylist);
    on<RenamePlaylist>(_onRenamePlaylist);

    // TODO: Listen to CollectionBloc state changes to reload playlists
    // when the active collection changes. This is typically done
    // in the UI layer using BlocListener, which then dispatches
    // LoadPlaylists to this bloc.
  }

  /// Handles the LoadPlaylists event for the active collection.
  Future<void> _onLoadPlaylists(
    LoadPlaylists event,
    Emitter<PlaylistState> emit,
  ) async {
    // Check if a collection is active in CollectionService
    if (_collectionService.getActiveCollection() == null) {
      print("PlaylistBloc: Cannot load playlists, no active collection.");
      emit(const PlaylistLoaded([])); // Emit empty list if no collection active
      // Or emit PlaylistError("No active collection selected.")
      return;
    }

    emit(PlaylistLoading());
    try {
      // Call service method, passing the required CollectionService instance
      final playlists = await _playlistService.loadPlaylists(
        _collectionService,
      );
      emit(PlaylistLoaded(playlists));
      print(
        "PlaylistBloc: Playlists loaded successfully for active collection.",
      );
    } catch (e) {
      print("PlaylistBloc: Error loading playlists: $e");
      emit(PlaylistError("Failed to load playlists: ${e.toString()}"));
    }
  }

  /// Handles the CreatePlaylist event for the active collection.
  Future<void> _onCreatePlaylist(
    CreatePlaylist event,
    Emitter<PlaylistState> emit,
  ) async {
    // Check if a collection is active
    if (_collectionService.getActiveCollection() == null) {
      emit(
        const PlaylistError("Cannot create playlist: No active collection."),
      );
      return;
    }
    // Get current state to potentially revert on error
    final currentState = state;
    emit(PlaylistLoading()); // Indicate loading

    try {
      // Service handles DB interaction for the active collection
      final newPlaylist = await _playlistService.createPlaylist(
        _collectionService,
        event.name,
      );
      if (newPlaylist != null) {
        // Reload playlists to include the new one
        add(LoadPlaylists()); // Dispatch event to reload
      } else {
        // Handle creation failure (e.g., name empty, DB error)
        print("PlaylistBloc: Playlist creation failed (returned null).");
        emit(const PlaylistError("Failed to create playlist."));
        if (currentState is PlaylistLoaded) emit(currentState); // Revert state
      }
    } catch (e) {
      print("PlaylistBloc: Error creating playlist: $e");
      emit(PlaylistError("Failed to create playlist: ${e.toString()}"));
      if (currentState is PlaylistLoaded) emit(currentState); // Revert state
    }
  }

  /// Handles the DeletePlaylist event for the active collection.
  Future<void> _onDeletePlaylist(
    DeletePlaylist event,
    Emitter<PlaylistState> emit,
  ) async {
    if (_collectionService.getActiveCollection() == null) {
      emit(
        const PlaylistError("Cannot delete playlist: No active collection."),
      );
      return;
    }
    // Optimistic UI update (optional but good UX)
    List<Playlist> optimisticPlaylists = [];
    if (state is PlaylistLoaded) {
      final currentLoadedState = state as PlaylistLoaded;
      optimisticPlaylists =
          currentLoadedState.playlists
              .where((p) => p.id != event.playlistId)
              .toList();
      emit(PlaylistLoaded(optimisticPlaylists)); // Show immediate removal
      print(
        "PlaylistBloc: Optimistically removed playlist ID ${event.playlistId}.",
      );
    } else {
      emit(PlaylistLoading()); // Show loading if not already loaded
    }

    try {
      await _playlistService.deletePlaylist(
        _collectionService,
        event.playlistId,
      );
      // If successful, the optimistic update is correct. If not loaded, reload.
      if (state is! PlaylistLoaded) {
        add(LoadPlaylists());
      } else {
        // If already loaded, the optimistic state is now confirmed.
        // If the optimistic list is different from the actual state after deletion
        // (e.g., another change happened), dispatch LoadPlaylists.
        // For simplicity, we can just rely on the optimistic update for now.
        print(
          "PlaylistBloc: Playlist ID ${event.playlistId} deleted from service.",
        );
      }
    } catch (e) {
      print("PlaylistBloc: Error deleting playlist ID ${event.playlistId}: $e");
      // Check state before emitting error
      final wasLoaded = state is PlaylistLoaded;
      emit(PlaylistError("Failed to delete playlist: ${e.toString()}"));
      // Revert optimistic update on error
      if (wasLoaded) {
        // Re-fetch to be safe or revert to previous known good state
        add(LoadPlaylists());
      }
    }
  }

  /// Handles the AddTrackToPlaylist event for the active collection.
  Future<void> _onAddTrackToPlaylist(
    AddTrackToPlaylist event,
    Emitter<PlaylistState> emit,
  ) async {
    if (_collectionService.getActiveCollection() == null) {
      emit(const PlaylistError("Cannot add track: No active collection."));
      return;
    }
    // Note: event.trackPath should be the ABSOLUTE path provided by UI/CollectionBloc
    // PlaylistService will handle making it relative if necessary.

    // Optimistic update (optional)
    // ... (find playlist, add path, emit updated PlaylistLoaded state) ...

    try {
      await _playlistService.addTrackToPlaylist(
        _collectionService,
        event.playlistId,
        event.trackPath,
      );
      // If optimistic update was done, it's confirmed.
      // If not, reload the specific playlist or all playlists.
      // For simplicity, let's reload all for now.
      if (state is PlaylistLoaded) {
        // Only reload if already loaded
        add(LoadPlaylists());
      }
      print(
        "PlaylistBloc: Track ${event.trackPath} added request sent for playlist ID ${event.playlistId}.",
      );
    } catch (e) {
      print(
        "PlaylistBloc: Error adding track to playlist ID ${event.playlistId}: $e",
      );
      // Check state before emitting error
      final wasLoaded = state is PlaylistLoaded;
      emit(PlaylistError("Failed to add track: ${e.toString()}"));
      // Revert optimistic update if implemented
      // Or reload playlists to show error state
      if (wasLoaded) add(LoadPlaylists());
    }
  }

  /// Handles the RemoveTrackFromPlaylist event for the active collection.
  Future<void> _onRemoveTrackFromPlaylist(
    RemoveTrackFromPlaylist event,
    Emitter<PlaylistState> emit,
  ) async {
    if (_collectionService.getActiveCollection() == null) {
      emit(const PlaylistError("Cannot remove track: No active collection."));
      return;
    }
    // Note: event.trackPath should be the ABSOLUTE path. Service handles relativity.

    // Optimistic update (optional)
    // ... (find playlist, remove path, emit updated PlaylistLoaded state) ...

    try {
      await _playlistService.removeTrackFromPlaylist(
        _collectionService,
        event.playlistId,
        event.trackPath,
      );
      // If optimistic update was done, it's confirmed. Otherwise, reload.
      if (state is PlaylistLoaded) {
        add(LoadPlaylists());
      }
      print(
        "PlaylistBloc: Track ${event.trackPath} removal request sent for playlist ID ${event.playlistId}.",
      );
    } catch (e) {
      print(
        "PlaylistBloc: Error removing track from playlist ID ${event.playlistId}: $e",
      );
      // Check state before emitting error
      final wasLoaded = state is PlaylistLoaded;
      emit(PlaylistError("Failed to remove track: ${e.toString()}"));
      // Revert optimistic update or reload
      if (wasLoaded) add(LoadPlaylists());
    }
  }

  /// Handles the RenamePlaylist event for the active collection.
  Future<void> _onRenamePlaylist(
    RenamePlaylist event,
    Emitter<PlaylistState> emit,
  ) async {
    if (_collectionService.getActiveCollection() == null) {
      emit(
        const PlaylistError("Cannot rename playlist: No active collection."),
      );
      return;
    }

    // Optimistic update (optional)
    // ... (find playlist, update name, emit updated PlaylistLoaded state) ...

    try {
      await _playlistService.renamePlaylist(
        _collectionService,
        event.playlistId,
        event.newName,
      );
      // If optimistic update was done, it's confirmed. Otherwise, reload.
      if (state is PlaylistLoaded) {
        add(LoadPlaylists());
      }
      print(
        "PlaylistBloc: Playlist ID ${event.playlistId} rename request sent.",
      );
    } catch (e) {
      print("PlaylistBloc: Error renaming playlist ID ${event.playlistId}: $e");
      emit(PlaylistError("Failed to rename playlist: ${e.toString()}"));
      // Revert optimistic update or reload
      if (state is PlaylistLoaded) add(LoadPlaylists());
    }
  }
}
