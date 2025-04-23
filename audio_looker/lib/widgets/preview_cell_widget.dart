// lib/widgets/preview_cell_widget.dart

import 'dart:async'; // Keep for Timer if used elsewhere, but maybe not needed now
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:waux/services/collection_service.dart';
import 'package:waux/blocs/audio_player/audio_player_bloc.dart';
import 'package:waux/widgets/waveform_painter.dart';
// import 'package:waux/services/audio_service.dart'; // Likely not needed directly

class PreviewCellWidget extends StatefulWidget {
  final Track track;
  final AudioPlayerBloc
  audioPlayerBloc; // Keep this if needed for dispatching actions
  final VoidCallback onPlayAndMinimize;

  const PreviewCellWidget({
    Key? key,
    required this.track,
    required this.audioPlayerBloc,
    required this.onPlayAndMinimize,
  }) : super(key: key);

  @override
  State<PreviewCellWidget> createState() => _PreviewCellWidgetState();
}

class _PreviewCellWidgetState extends State<PreviewCellWidget> {
  // --- REMOVE internal state variables for playback ---
  // bool _isCurrentlyPlaying = false; // REMOVED
  // double _currentProgress = 0.0; // REMOVED
  // Duration _currentDuration = Duration.zero; // REMOVED
  // StreamSubscription<AudioPlayerState>? _playerStateSubscription; // REMOVED
  final GlobalKey _waveformAreaKey = GlobalKey();

  // State for Dragging (Keep this local UI state)
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
    // --- REMOVE Bloc subscription cancellation ---
    // _playerStateSubscription?.cancel(); // REMOVED
    super.dispose();
  }

  // Helper for drag/tap calculation (remains mostly the same)
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
    // --- ADD BlocBuilder ---
    return BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
      bloc: widget.audioPlayerBloc, // Explicitly provide the bloc
      builder: (context, playerState) {
        // --- Determine playback state *inside* the builder ---
        bool isCurrentlyPlaying = false;
        double currentProgress = 0.0;
        Duration currentDuration = Duration.zero;

        // Check if the player is loaded AND if it's the track for *this* cell
        if (playerState is AudioPlayerLoaded &&
            playerState.currentSource == widget.track.path) {
          isCurrentlyPlaying = playerState.isPlaying;
          currentDuration = playerState.duration;
          if (currentDuration > Duration.zero) {
            // Use the state's position directly
            currentProgress = (playerState.position.inMilliseconds /
                    currentDuration.inMilliseconds)
                .clamp(0.0, 1.0);
          }
        }
        // --- End state determination ---

        return Row(
          children: [
            // Play/Pause Button - Use 'isCurrentlyPlaying' from builder
            IconButton(
              icon: Icon(
                isCurrentlyPlaying // Use state derived in builder
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip:
                  isCurrentlyPlaying // Use state derived in builder
                      ? 'Pause ${widget.track.title}'
                      : 'Play ${widget.track.title}',
              // onPressed still calls the callback passed from parent
              onPressed: widget.onPlayAndMinimize,
            ),
            const SizedBox(width: 8),
            // Waveform Preview
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // onTapDown remains the same (calls parent callback)
                onTapDown: (details) {
                  // --- REVISED MODIFICATION ---
                  final bloc = widget.audioPlayerBloc;
                  final currentState = bloc.state;
                  double? seekRatio = _calculateSeekRatio(
                    details.globalPosition,
                  ); // Calculate ratio (0.0-1.0)

                  print("Waveform Tapped. Seek Ratio: $seekRatio");

                  // Call parent callback (for UI like minimizing/opening player)
                  widget.onPlayAndMinimize();

                  // Handle loading/playing
                  if (currentState is AudioPlayerLoaded &&
                      currentState.currentSource == widget.track.path) {
                    // Already loaded: Seek (if ratio exists & duration is valid) and Play
                    if (seekRatio != null &&
                        currentState.duration > Duration.zero) {
                      final seekPosition = currentState.duration * seekRatio;
                      bloc.add(SeekAudio(position: seekPosition));
                    }
                    // Ensure it plays if paused
                    if (!currentState.isPlaying) {
                      bloc.add(PlayAudio());
                    }
                  } else {
                    // Not loaded or different track: Load, pass seek RATIO, and request play
                    bloc.add(
                      LoadAudio(
                        track: widget.track,
                        playWhenReady: true, // <<< Play when ready after tap
                        initialSeekRatio:
                            seekRatio, // <<< Pass the calculated ratio
                      ),
                    );
                  }
                  // --- END REVISED MODIFICATION ---
                },
                // --- Drag Handlers (Update to use playerState from builder scope) ---
                onHorizontalDragStart: (details) {
                  // Use playerState directly instead of internal state
                  if (playerState is AudioPlayerLoaded &&
                      playerState.currentSource == widget.track.path &&
                      playerState.duration > Duration.zero) {
                    setState(() {
                      // Still use setState for local drag UI state
                      _isDragging = true;
                      _wasPlayingBeforeDrag =
                          playerState.isPlaying; // Use playerState
                      _lastSeekDispatchTime = null;
                      final seekRatio = _calculateSeekRatio(
                        details.globalPosition,
                      );
                      if (seekRatio != null) {
                        _dragProgress = seekRatio;
                        _finalDragRatio = seekRatio;
                        final seekPosition = playerState.duration * seekRatio;
                        widget.audioPlayerBloc.add(
                          SeekAudio(position: seekPosition),
                        );
                        _lastSeekDispatchTime = DateTime.now();
                      } else {
                        _dragProgress =
                            currentProgress; // Use progress from builder
                        _finalDragRatio =
                            currentProgress; // Use progress from builder
                      }
                    });
                    if (_wasPlayingBeforeDrag) {
                      widget.audioPlayerBloc.add(PauseAudio());
                    }
                  }
                },
                onHorizontalDragUpdate: (details) {
                  if (!_isDragging) return;
                  // Use playerState directly
                  if (playerState is AudioPlayerLoaded &&
                      playerState.currentSource == widget.track.path &&
                      playerState.duration > Duration.zero) {
                    final seekRatio = _calculateSeekRatio(
                      details.globalPosition,
                    );
                    if (seekRatio != null) {
                      _finalDragRatio = seekRatio;
                      final now = DateTime.now();
                      bool shouldDispatch =
                          _lastSeekDispatchTime == null ||
                          now.difference(_lastSeekDispatchTime!) >
                              _seekThrottleInterval;
                      if (shouldDispatch) {
                        final seekPosition = playerState.duration * seekRatio;
                        widget.audioPlayerBloc.add(
                          SeekAudio(position: seekPosition),
                        );
                        _lastSeekDispatchTime = now;
                      }
                      setState(() {
                        // Update local drag UI state
                        _dragProgress = seekRatio;
                      });
                    }
                  }
                },
                onHorizontalDragEnd: (details) {
                  if (!_isDragging) return;
                  // Use playerState directly
                  if (playerState is AudioPlayerLoaded &&
                      playerState.currentSource == widget.track.path &&
                      playerState.duration > Duration.zero) {
                    final finalSeekPosition =
                        playerState.duration * _finalDragRatio;
                    widget.audioPlayerBloc.add(
                      SeekAudio(position: finalSeekPosition),
                    );
                    if (_wasPlayingBeforeDrag) {
                      Future.delayed(const Duration(milliseconds: 50), () {
                        if (mounted) {
                          widget.audioPlayerBloc.add(PlayAudio());
                        }
                      });
                    }
                  }
                  setState(() {
                    // Update local drag UI state
                    _isDragging = false;
                    _dragProgress = null;
                    _lastSeekDispatchTime = null;
                  });
                },
                // --- End Drag Handlers ---
                child: SizedBox(
                  key: _waveformAreaKey,
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
                      // Pass progress directly from value derived in builder
                      playbackProgress: currentProgress,
                      dragProgress:
                          _dragProgress, // Pass local drag progress state
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }, // End builder function
    ); // End BlocBuilder
  }
}
