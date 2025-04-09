// lib/handlers/player_control_handler.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Import BLoCs
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';

// Import models
import 'package:audio_looker/services/collection_service.dart';

/// Handles audio player controls and navigation
class PlayerControlHandler {
  final BuildContext context;
  final Track? selectedTrackForPlayer;
  final List<Track> Function() getCurrentDisplayedTracksFn;

  PlayerControlHandler({
    required this.context,
    required this.selectedTrackForPlayer,
    required this.getCurrentDisplayedTracksFn,
  });

  /// Play the next track in the current view
  void playNextTrack({required Function(Track, bool) onTrackSelected}) {
    if (selectedTrackForPlayer == null) return;

    final List<Track> currentList = getCurrentDisplayedTracksFn();
    if (currentList.isEmpty) return;

    final currentIndex = currentList.indexWhere(
      (t) => t.id == selectedTrackForPlayer!.id,
    );

    if (currentIndex != -1 && currentIndex < currentList.length - 1) {
      final nextTrack = currentList[currentIndex + 1];
      print("Selecting next track: ${nextTrack.title}");
      onTrackSelected(nextTrack, false);
    } else {
      print("No next track available or current track not found.");
      // Optional: Stop playback or loop?
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
