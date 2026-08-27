// lib/handlers/player_control_handler.dart

import 'dart:math'; // Required for Random
import 'package:collection/collection.dart'; // Required for firstWhereOrNull
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Import BLoCs
import 'package:waux/blocs/audio_player/audio_player_bloc.dart';

// Import models
import 'package:waux/services/collection_service.dart';

/// Handles audio player controls and navigation
class PlayerControlHandler {
  final BuildContext context;
  final Track? selectedTrackForPlayer;
  final List<Track> Function() getCurrentDisplayedTracksFn;
  final bool isShuffleActive; // <<< ADDED: Shuffle state

  PlayerControlHandler({
    required this.context,
    required this.selectedTrackForPlayer,
    required this.getCurrentDisplayedTracksFn,
    required this.isShuffleActive, // <<< ADDED: Require shuffle state
  });

  /// Play the next track in the current view, considering shuffle state.
  void playNextTrack({required Function(Track, bool) onTrackSelected}) {
    if (selectedTrackForPlayer == null) {
      print("PlayerControlHandler: Cannot play next, no track selected.");
      return;
    }

    final List<Track> currentList = getCurrentDisplayedTracksFn();
    if (currentList.isEmpty) {
      print("PlayerControlHandler: Cannot play next, current list is empty.");
      return;
    }

    Track? nextTrack;

    if (isShuffleActive) {
      // --- Shuffle Logic ---
      print("PlayerControlHandler: Shuffle is active.");
      if (currentList.length > 1) {
        // Get tracks other than the current one
        var potentialNextTracks =
            currentList
                .where((t) => t.id != selectedTrackForPlayer!.id)
                .toList();
        if (potentialNextTracks.isNotEmpty) {
          // Pick a random track from the remaining ones
          final randomIndex = Random().nextInt(potentialNextTracks.length);
          nextTrack = potentialNextTracks[randomIndex];
          print(
            "PlayerControlHandler: Shuffling to track ID: ${nextTrack.id} ('${nextTrack.title}')",
          );
        } else {
          // This case should technically not happen if length > 1,
          // but as a fallback, play the first track if it's different.
          nextTrack = currentList.firstWhereOrNull(
            (t) => t.id != selectedTrackForPlayer!.id,
          );
          // If still null (meaning only one track in list), replay it.
          if (nextTrack == null) {
            nextTrack = currentList.first;
            print(
              "PlayerControlHandler: Shuffle fallback - only one other/same track, replaying ID: ${nextTrack.id}",
            );
          }
        }
      } else if (currentList.length == 1) {
        // Only one track in the list, just play it again (or seek to start)
        nextTrack = currentList.first;
        print(
          "PlayerControlHandler: Shuffle - Only one track in list, selecting ID: ${nextTrack.id}",
        );
        // Optionally seek to 0 instead of re-selecting if it's the same track
        // context.read<AudioPlayerBloc>().add(const SeekAudio(position: Duration.zero));
        // return; // Exit early if just seeking
      }
    } else {
      // --- Sequential Logic ---
      print("PlayerControlHandler: Shuffle is inactive (sequential).");
      final currentIndex = currentList.indexWhere(
        (t) => t.id == selectedTrackForPlayer!.id,
      );

      if (currentIndex != -1 && currentIndex < currentList.length - 1) {
        // Found current track and it's not the last one
        nextTrack = currentList[currentIndex + 1];
        print(
          "PlayerControlHandler: Sequential - Playing next track ID: ${nextTrack.id} ('${nextTrack.title}')",
        );
      } else {
        // Current track is last or not found in the current list
        print(
          "PlayerControlHandler: Sequential - End of list reached or current track not found.",
        );
        // Optional: Stop playback, loop to the first track, etc.
        // Example: Loop to first
        // if (currentList.isNotEmpty) {
        //   nextTrack = currentList.first;
        //   print("PlayerControlHandler: Sequential - Looping to first track ID: ${nextTrack.id}");
        // } else {
        //   context.read<AudioPlayerBloc>().add(StopAudio()); // Stop if list is empty
        // }
        // For now, let's just stop if we reach the end sequentially
        context.read<AudioPlayerBloc>().add(StopAudio());
        return; // Don't call onTrackSelected if stopping
      }
    }

    // --- Play the selected track ---
    if (nextTrack != null) {
      print(
        "PlayerControlHandler: Calling onTrackSelected for track ID: ${nextTrack.id}",
      );
      onTrackSelected(nextTrack, false); // Select and play the determined track
    } else {
      // This case might occur in shuffle if list length is 0 or 1 and logic fails
      print("PlayerControlHandler: No next track determined.");
      context.read<AudioPlayerBloc>().add(
        StopAudio(),
      ); // Stop if no track found
    }
  }

  /// Play the previous track or restart current track
  void playPreviousTrack({required Function(Track, bool) onTrackSelected}) {
    if (selectedTrackForPlayer == null) return;

    final audioPlayerBloc = context.read<AudioPlayerBloc>();
    final playerState = audioPlayerBloc.state;

    // Check if we need to restart the current track
    if (playerState is AudioPlayerLoaded &&
        playerState.currentSource == selectedTrackForPlayer!.path) {
      final currentPosition = playerState.position;

      // If played past a threshold (e.g., 3 seconds), seek to beginning of current track
      if (currentPosition.inSeconds >= 3) {
        print("Previous clicked (>3s): Seeking current track to 0");
        audioPlayerBloc.add(const SeekAudio(position: Duration.zero));

        // Ensure it plays if it was paused
        if (!playerState.isPlaying) audioPlayerBloc.add(PlayAudio());
        return; // Don't proceed to the actual previous track
      }
    }

    // Find and play the previous track
    final List<Track> currentList = getCurrentDisplayedTracksFn();
    if (currentList.isEmpty) return;

    final currentIndex = currentList.indexWhere(
      (t) => t.id == selectedTrackForPlayer!.id,
    );

    if (currentIndex > 0) {
      // Found current track and it's not the first one
      final previousTrack = currentList[currentIndex - 1];
      print(
        "Previous clicked (<=3s): Playing previous track: ${previousTrack.title}",
      );
      onTrackSelected(previousTrack, false);
    } else {
      // Current track is the first one or not found, seek to 0
      print(
        "No previous track available or current track not found. Seeking to 0.",
      );
      audioPlayerBloc.add(const SeekAudio(position: Duration.zero));

      // Ensure it plays if it was paused
      if (playerState is AudioPlayerLoaded && !playerState.isPlaying) {
        audioPlayerBloc.add(PlayAudio());
      }
    }
  }

  /// Toggle play/pause state
  void togglePlayPause() {
    final audioBloc = context.read<AudioPlayerBloc>();
    final currentState = audioBloc.state;

    if (currentState is AudioPlayerLoaded) {
      if (currentState.isPlaying) {
        print("Pausing audio");
        audioBloc.add(PauseAudio());
      } else {
        // Handle playing from the end by seeking to 0 first
        if (currentState.position >= currentState.duration &&
            currentState.duration > Duration.zero) {
          print("Seeking to 0 before playing");
          audioBloc.add(const SeekAudio(position: Duration.zero));

          // Add a small delay to ensure seek completes before play
          Future.delayed(const Duration(milliseconds: 50), () {
            print("Playing audio after seek");
            audioBloc.add(PlayAudio());
          });
        } else {
          print("Playing audio");
          audioBloc.add(PlayAudio());
        }
      }
    } else {
      print("Player not loaded, cannot toggle play");
    }
  }
}
