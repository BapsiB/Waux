// lib/widgets/preview_cell_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // Import Bloc
import 'package:audio_looker/services/collection_service.dart'; // Your Track model
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart'; // Import AudioPlayerBloc
import 'package:audio_looker/widgets/waveform_painter.dart'; // Import WaveformPainter
import 'package:audio_looker/services/audio_service.dart'; // Import AudioService for context reading if needed elsewhere

class PreviewCellWidget extends StatefulWidget {
  final Track track;
  final AudioPlayerBloc audioPlayerBloc;
  // Callback passed from HomeScreen via TrackDataSource
  final VoidCallback onPlayAndMinimize;

  const PreviewCellWidget({
    Key? key,
    required this.track,
    required this.audioPlayerBloc,
    required this.onPlayAndMinimize, // Ensure this is required
  }) : super(key: key);

  @override
  State<PreviewCellWidget> createState() => _PreviewCellWidgetState();
}

class _PreviewCellWidgetState extends State<PreviewCellWidget> {
  // Keep existing state variables (_isCurrentlyPlaying, _currentProgress, etc.)
  bool _isCurrentlyPlaying = false;
  double _currentProgress = 0.0;
  Duration _currentDuration = Duration.zero;
  StreamSubscription<AudioPlayerState>? _playerStateSubscription;
  final GlobalKey _waveformAreaKey = GlobalKey();

  // State for Dragging
  bool _isDragging = false;
  double? _dragProgress;
  bool _wasPlayingBeforeDrag = false;
  double _finalDragRatio = 0.0;
  DateTime? _lastSeekDispatchTime;
  final Duration _seekThrottleInterval = const Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    _updateStateFromBloc(widget.audioPlayerBloc.state);
    _playerStateSubscription = widget.audioPlayerBloc.stream.listen((state) {
      if (mounted) {
        _updateStateFromBloc(state);
      }
    });
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    super.dispose();
  }

  void _updateStateFromBloc(AudioPlayerState playerState) {
    bool isPlaying = false;
    double progress = 0.0;
    Duration duration = Duration.zero;

    if (playerState is AudioPlayerLoaded &&
        playerState.currentSource == widget.track.path) {
      isPlaying = playerState.isPlaying;
      duration = playerState.duration;
      if (playerState.duration > Duration.zero) {
        progress = (playerState.position.inMilliseconds /
                playerState.duration.inMilliseconds)
            .clamp(0.0, 1.0);
      }
    }

    if (isPlaying != _isCurrentlyPlaying ||
        progress != _currentProgress ||
        duration != _currentDuration) {
      setState(() {
        _isCurrentlyPlaying = isPlaying;
        _currentProgress = progress;
        _currentDuration = duration;
      });
    }
  }

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
    return Row(
      children: [
        // Play/Pause Button
        IconButton(
          icon: Icon(
            _isCurrentlyPlaying
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip:
              _isCurrentlyPlaying
                  ? 'Pause ${widget.track.title}'
                  : 'Play ${widget.track.title}',
          // Uses the callback passed from HomeScreen
          onPressed: widget.onPlayAndMinimize,
        ),
        const SizedBox(width: 8),
        // Waveform Preview
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // --- UPDATED onTapDown ---
            // Tapping the waveform now also triggers the minimize action
            onTapDown: (details) {
              print("Waveform Tapped - Calling onPlayAndMinimize");
              widget
                  .onPlayAndMinimize(); // Call the same callback as the button

              // --- REMOVE the old logic below ---
              // final bloc = widget.audioPlayerBloc;
              // final currentState = bloc.state;
              // if (currentState is AudioPlayerLoaded &&
              //     currentState.currentSource == widget.track.path &&
              //     currentState.duration > Duration.zero) {
              //   final seekRatio = _calculateSeekRatio(details.globalPosition);
              //   if (seekRatio != null) {
              //     final seekPosition = currentState.duration * seekRatio;
              //     bloc.add(SeekAudio(position: seekPosition));
              //     bloc.add(PlayAudio()); // Play after seeking on tap
              //   }
              // } else {
              //   bloc.add(LoadAudio(source: widget.track.path, isUrl: widget.track.isUrl));
              //   Future.delayed(const Duration(milliseconds: 150), () {
              //     if (!mounted) return;
              //     final postDelayState = bloc.state;
              //     if (postDelayState is AudioPlayerLoaded && postDelayState.currentSource == widget.track.path) {
              //       bloc.add(PlayAudio());
              //     }
              //   });
              // }
            },
            // --- Drag Handlers (Keep existing logic for seeking during drag) ---
            onHorizontalDragStart: (details) {
              final bloc = widget.audioPlayerBloc;
              final currentState = bloc.state;
              if (currentState is AudioPlayerLoaded &&
                  currentState.currentSource == widget.track.path &&
                  currentState.duration > Duration.zero) {
                setState(() {
                  _isDragging = true;
                  _wasPlayingBeforeDrag = currentState.isPlaying;
                  _lastSeekDispatchTime = null;
                  final seekRatio = _calculateSeekRatio(details.globalPosition);
                  if (seekRatio != null) {
                    _dragProgress = seekRatio;
                    _finalDragRatio = seekRatio;
                    final seekPosition = currentState.duration * seekRatio;
                    // Seek directly on drag start for immediate feedback
                    bloc.add(SeekAudio(position: seekPosition));
                    _lastSeekDispatchTime = DateTime.now();
                  } else {
                    _dragProgress = _currentProgress;
                    _finalDragRatio = _currentProgress;
                  }
                });
                if (_wasPlayingBeforeDrag) {
                  bloc.add(PauseAudio());
                }
              }
            },
            onHorizontalDragUpdate: (details) {
              if (!_isDragging) return;
              final bloc = widget.audioPlayerBloc;
              final currentState = bloc.state;
              if (currentState is AudioPlayerLoaded &&
                  currentState.currentSource == widget.track.path &&
                  currentState.duration > Duration.zero) {
                final seekRatio = _calculateSeekRatio(details.globalPosition);
                if (seekRatio != null) {
                  _finalDragRatio = seekRatio;
                  final now = DateTime.now();
                  bool shouldDispatch =
                      _lastSeekDispatchTime == null ||
                      now.difference(_lastSeekDispatchTime!) >
                          _seekThrottleInterval;
                  if (shouldDispatch) {
                    final seekPosition = currentState.duration * seekRatio;
                    bloc.add(SeekAudio(position: seekPosition));
                    _lastSeekDispatchTime = now;
                  }
                  setState(() {
                    _dragProgress = seekRatio;
                  });
                }
              }
            },
            onHorizontalDragEnd: (details) {
              if (!_isDragging) return;
              final bloc = widget.audioPlayerBloc;
              final currentState = bloc.state;
              if (currentState is AudioPlayerLoaded &&
                  currentState.currentSource == widget.track.path &&
                  currentState.duration > Duration.zero) {
                final finalSeekPosition =
                    currentState.duration * _finalDragRatio;
                // Final seek on drag end
                bloc.add(SeekAudio(position: finalSeekPosition));
                if (_wasPlayingBeforeDrag) {
                  // Resume playing slightly after the final seek settles
                  Future.delayed(const Duration(milliseconds: 50), () {
                    if (mounted) {
                      bloc.add(PlayAudio());
                    }
                  });
                }
              }
              setState(() {
                _isDragging = false;
                _dragProgress = null;
                _lastSeekDispatchTime = null;
              });
            },
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
                  playbackProgress: _currentProgress,
                  dragProgress: _dragProgress, // Pass drag progress
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
