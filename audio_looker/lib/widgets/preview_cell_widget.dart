// lib/widgets/preview_cell_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:waux/services/collection_service.dart';
import 'package:waux/blocs/audio_player/audio_player_bloc.dart';
import 'package:waux/widgets/waveform_painter.dart';

class PreviewCellWidget extends StatefulWidget {
  final Track track;
  final AudioPlayerBloc audioPlayerBloc;
  final VoidCallback onPlayAndMinimize; // Keep for the button's toggle action

  const PreviewCellWidget({
    Key? key,
    required this.track,
    required this.audioPlayerBloc,
    required this.onPlayAndMinimize, // This is for the PLAY BUTTON toggle
  }) : super(key: key);

  @override
  State<PreviewCellWidget> createState() => _PreviewCellWidgetState();
}

class _PreviewCellWidgetState extends State<PreviewCellWidget> {
  final GlobalKey _waveformAreaKey = GlobalKey();
  bool _isDragging = false;
  double? _dragProgress;
  bool _wasPlayingBeforeDrag = false;
  double _finalDragRatio = 0.0;
  DateTime? _lastSeekDispatchTime;
  final Duration _seekThrottleInterval = const Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Helper for drag/tap calculation
  double? _calculateSeekRatio(Offset globalPosition) {
    final RenderBox? box =
        _waveformAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final localPosition = box.globalToLocal(globalPosition);
      final containerWidth = box.size.width;
      if (containerWidth > 0) {
        return (localPosition.dx / containerWidth).clamp(0.0, 1.0);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
      bloc: widget.audioPlayerBloc,
      builder: (context, playerState) {
        bool isCurrentlyPlaying = false;
        double currentProgress = 0.0;
        Duration currentDuration = Duration.zero;
        bool isThisTrackLoaded = false;

        if (playerState is AudioPlayerLoaded &&
            playerState.currentSource == widget.track.path) {
          isThisTrackLoaded = true; // Track is loaded
          isCurrentlyPlaying = playerState.isPlaying;
          currentDuration = playerState.duration;
          if (currentDuration > Duration.zero) {
            currentProgress = (playerState.position.inMilliseconds /
                    currentDuration.inMilliseconds)
                .clamp(0.0, 1.0);
          }
        }

        return Row(
          children: [
            // Play/Pause Button - Uses the existing toggle callback
            IconButton(
              icon: Icon(
                isCurrentlyPlaying
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip:
                  isCurrentlyPlaying
                      ? 'Pause ${widget.track.title}'
                      : 'Play ${widget.track.title}',
              // *** IMPORTANT: This button still uses the original callback for TOGGLE ***
              onPressed: widget.onPlayAndMinimize,
            ),
            const SizedBox(width: 8),
            // Waveform Preview
            Expanded(
              child: GestureDetector(
                key: _waveformAreaKey, // Assign key here
                behavior: HitTestBehavior.opaque,
                // --- REMOVED onTapDown ---
                // onTapDown: (details) { /* REMOVED - Was causing the pause */ },

                // --- NEW: Handle tap on waveform for seeking/loading ---
                onTapUp: (details) {
                  final bloc = widget.audioPlayerBloc;
                  final currentState = bloc.state;
                  double? seekRatio = _calculateSeekRatio(
                    details.globalPosition,
                  );

                  if (seekRatio == null) return; // Couldn't calculate ratio

                  print("Waveform Tapped. Seek Ratio: $seekRatio");

                  if (isThisTrackLoaded && currentState is AudioPlayerLoaded) {
                    // Track is already loaded: Seek only, DO NOT toggle play/pause
                    if (currentState.duration > Duration.zero) {
                      final seekPosition = currentState.duration * seekRatio;
                      print(
                        "Waveform Tap: Seeking loaded track ${widget.track.id} to $seekPosition",
                      );
                      bloc.add(SeekAudio(position: seekPosition));
                      // If it was paused, tapping the waveform doesn't automatically resume it here.
                      // If it was playing, the seek doesn't stop it.
                    } else {
                      print(
                        "Waveform Tap: Cannot seek, duration is zero for loaded track ${widget.track.id}",
                      );
                    }
                  } else {
                    // Different track or not loaded: Load, seek, and ensure playback starts.
                    print(
                      "Waveform Tap: Loading track ${widget.track.id} with initial seek $seekRatio",
                    );
                    bloc.add(
                      LoadAudio(
                        track: widget.track,
                        playWhenReady: true, // Play when ready after load/seek
                        initialSeekRatio:
                            seekRatio, // Pass the calculated ratio
                      ),
                    );
                    // Also trigger the UI update (minimize/open player) via the button's callback
                    // This ensures the player UI updates correctly when loading a new track via waveform tap.
                    widget.onPlayAndMinimize();
                  }
                },
                // --- END NEW onTapUp ---

                // --- Drag Handlers (Remain largely the same, use state from builder) ---
                onHorizontalDragStart: (details) {
                  if (isThisTrackLoaded && currentDuration > Duration.zero) {
                    final bloc = widget.audioPlayerBloc;
                    setState(() {
                      _isDragging = true;
                      // Use isCurrentlyPlaying determined within the builder
                      _wasPlayingBeforeDrag = isCurrentlyPlaying;
                      _lastSeekDispatchTime = null;
                      final seekRatio = _calculateSeekRatio(
                        details.globalPosition,
                      );
                      if (seekRatio != null) {
                        _dragProgress = seekRatio;
                        _finalDragRatio = seekRatio;
                        // Optional: Seek immediately on drag start
                        final seekPosition = currentDuration * seekRatio;
                        bloc.add(SeekAudio(position: seekPosition));
                        _lastSeekDispatchTime = DateTime.now();
                      } else {
                        _dragProgress = currentProgress;
                        _finalDragRatio = currentProgress;
                      }
                    });
                    // Pause only if it was playing *before* drag started
                    if (_wasPlayingBeforeDrag) {
                      bloc.add(PauseAudio());
                    }
                  }
                },
                onHorizontalDragUpdate: (details) {
                  if (!_isDragging ||
                      !isThisTrackLoaded ||
                      currentDuration <= Duration.zero)
                    return;
                  final bloc = widget.audioPlayerBloc;
                  final seekRatio = _calculateSeekRatio(details.globalPosition);
                  if (seekRatio != null) {
                    _finalDragRatio =
                        seekRatio; // Store the final ratio continuously
                    final now = DateTime.now();
                    // Throttle the SeekAudio dispatch
                    bool shouldDispatch =
                        _lastSeekDispatchTime == null ||
                        now.difference(_lastSeekDispatchTime!) >
                            _seekThrottleInterval;

                    if (shouldDispatch) {
                      final seekPosition = currentDuration * seekRatio;
                      bloc.add(SeekAudio(position: seekPosition));
                      _lastSeekDispatchTime = now;
                    }
                    setState(() {
                      _dragProgress = seekRatio; // Update visual drag indicator
                    });
                  }
                },
                onHorizontalDragEnd: (details) {
                  if (!_isDragging) return;
                  final bloc = widget.audioPlayerBloc;

                  // Always dispatch final seek on drag end
                  if (isThisTrackLoaded && currentDuration > Duration.zero) {
                    final finalSeekPosition = currentDuration * _finalDragRatio;
                    print(
                      "Waveform DragEnd: Final Seek to $finalSeekPosition (Ratio: $_finalDragRatio)",
                    );
                    bloc.add(SeekAudio(position: finalSeekPosition));
                  }

                  // Reset dragging state
                  bool needsResume =
                      _wasPlayingBeforeDrag; // Store before resetting state
                  setState(() {
                    _isDragging = false;
                    _dragProgress = null;
                    _lastSeekDispatchTime = null;
                    _wasPlayingBeforeDrag = false; // Reset internal flag
                  });

                  // Resume playback AFTER resetting state and final seek
                  if (needsResume) {
                    // Use a short delay to allow the final seek to process
                    Future.delayed(const Duration(milliseconds: 50), () {
                      if (mounted) {
                        // Check if still mounted
                        print("Waveform DragEnd: Resuming playback");
                        bloc.add(PlayAudio());
                      }
                    });
                  }
                },
                // --- End Drag Handlers ---
                child: SizedBox(
                  height: 24,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: WaveformPainter(
                      waveformData: widget.track.waveformData ?? [],
                      activeColor: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.7),
                      inactiveColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.25),
                      playbackProgress:
                          currentProgress, // Use state from builder
                      dragProgress: _dragProgress,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
