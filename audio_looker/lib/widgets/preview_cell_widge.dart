import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // Import Bloc
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:audio_looker/services/collection_service.dart'; // Your Track model
// import 'package:audio_looker/widgets/track_table_row.dart' show WaveformPreviewCell; // Remove if not used elsewhere
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart'; // Import AudioPlayerBloc
import 'package:audio_looker/widgets/waveform_painter.dart'; // Import WaveformPainter

class PreviewCellWidget extends StatefulWidget {
  final Track track;
  final AudioPlayerBloc audioPlayerBloc; // Accept bloc instance

  const PreviewCellWidget({
    Key? key,
    required this.track,
    required this.audioPlayerBloc, // Add to constructor
  }) : super(key: key);

  @override
  State<PreviewCellWidget> createState() => _PreviewCellWidgetState();
}

class _PreviewCellWidgetState extends State<PreviewCellWidget> {
  // State for playback status
  bool _isCurrentlyPlaying = false;
  double _currentProgress = 0.0;
  Duration _currentDuration = Duration.zero;
  StreamSubscription<AudioPlayerState>? _playerStateSubscription;
  final GlobalKey _waveformAreaKey = GlobalKey();

  // --- State for Dragging ---
  bool _isDragging = false;
  double? _dragProgress; // Visual drag position (0.0 to 1.0)
  bool _wasPlayingBeforeDrag = false;
  double _finalDragRatio = 0.0; // Store final ratio for drag end
  DateTime? _lastSeekDispatchTime; // For throttling
  final Duration _seekThrottleInterval = const Duration(
    milliseconds: 100,
  ); // Throttle interval (10 times/sec)

  @override
  void initState() {
    super.initState();
    // Initialize state from the bloc's current state
    _updateStateFromBloc(widget.audioPlayerBloc.state);

    // Listen to future state changes
    _playerStateSubscription = widget.audioPlayerBloc.stream.listen((state) {
      if (mounted) {
        // Check if widget is still mounted before calling setState
        _updateStateFromBloc(state);
      }
    });
  }

  void _updateStateFromBloc(AudioPlayerState playerState) {
    bool isPlaying = false;
    double progress = 0.0;
    Duration duration = Duration.zero;

    if (playerState is AudioPlayerLoaded &&
        playerState.currentSource == widget.track.path) {
      isPlaying = playerState.isPlaying;
      duration = playerState.duration; // Store duration
      if (playerState.duration > Duration.zero) {
        progress = (playerState.position.inMilliseconds /
                playerState.duration.inMilliseconds)
            .clamp(0.0, 1.0);
      }
    }

    // Update local state only if changed
    // Check duration as well
    if (isPlaying != _isCurrentlyPlaying ||
        progress != _currentProgress ||
        duration != _currentDuration) {
      setState(() {
        _isCurrentlyPlaying = isPlaying;
        _currentProgress = progress;
        _currentDuration = duration; // Update duration
      });
    }
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel(); // Cancel subscription
    super.dispose();
  }

  // --- Helper to calculate seek ratio ---
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
    return null; // Return null if calculation fails
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
          onPressed: () {
            final bloc = widget.audioPlayerBloc;
            final currentState = bloc.state;

            if (currentState is AudioPlayerLoaded &&
                currentState.currentSource == widget.track.path) {
              if (currentState.isPlaying) {
                bloc.add(PauseAudio());
              } else {
                if (currentState.position >= currentState.duration &&
                    currentState.duration > Duration.zero) {
                  bloc.add(const SeekAudio(position: Duration.zero));
                }
                bloc.add(PlayAudio());
              }
            } else {
              bloc.add(
                LoadAudio(source: widget.track.path, isUrl: widget.track.isUrl),
              );
              Future.delayed(const Duration(milliseconds: 150), () {
                final postDelayState = bloc.state;
                if (postDelayState is AudioPlayerLoaded &&
                    postDelayState.currentSource == widget.track.path) {
                  bloc.add(PlayAudio());
                }
              });
            }
          },
        ),
        const SizedBox(width: 8),
        // Waveform Preview
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // --- Tap Down (Direct Seek) ---
            onTapDown: (details) {
              final bloc = widget.audioPlayerBloc;
              final currentState = bloc.state;

              if (currentState is AudioPlayerLoaded &&
                  currentState.currentSource == widget.track.path &&
                  currentState.duration > Duration.zero) {
                final seekRatio = _calculateSeekRatio(details.globalPosition);
                if (seekRatio != null) {
                  final seekPosition = currentState.duration * seekRatio;
                  print(
                    'Waveform TAP seek request: ${seekPosition.inMilliseconds}ms (Ratio: $seekRatio)',
                  );
                  bloc.add(SeekAudio(position: seekPosition));
                } else {
                  print("Waveform TAP seek failed: Could not calculate ratio.");
                }
              } else {
                print(
                  'Waveform TAP on unloaded/invalid track. Treating as play request.',
                );
                bloc.add(
                  LoadAudio(
                    source: widget.track.path,
                    isUrl: widget.track.isUrl,
                  ),
                );
                Future.delayed(const Duration(milliseconds: 150), () {
                  final postDelayState = bloc.state;
                  if (postDelayState is AudioPlayerLoaded &&
                      postDelayState.currentSource == widget.track.path) {
                    bloc.add(PlayAudio());
                  }
                });
              }
            },
            // --- Drag Start ---
            onHorizontalDragStart: (details) {
              final bloc = widget.audioPlayerBloc;
              final currentState = bloc.state;
              // Only allow dragging if this track is loaded and has duration
              if (currentState is AudioPlayerLoaded &&
                  currentState.currentSource == widget.track.path &&
                  currentState.duration > Duration.zero) {
                setState(() {
                  _isDragging = true;
                  _wasPlayingBeforeDrag =
                      currentState.isPlaying; // Store original state
                  _lastSeekDispatchTime = null; // Reset throttle timer
                  // Calculate initial drag position
                  final seekRatio = _calculateSeekRatio(details.globalPosition);
                  if (seekRatio != null) {
                    _dragProgress = seekRatio;
                    _finalDragRatio = seekRatio;
                    // Dispatch initial seek immediately
                    final seekPosition = currentState.duration * seekRatio;
                    bloc.add(SeekAudio(position: seekPosition));
                    _lastSeekDispatchTime =
                        DateTime.now(); // Start throttling timer
                  } else {
                    _dragProgress = _currentProgress; // Fallback
                    _finalDragRatio = _currentProgress;
                  }
                });
                // Pause playback while dragging if it was playing
                if (_wasPlayingBeforeDrag) {
                  bloc.add(PauseAudio());
                }
              } else {
                print("Drag ignored: Track not loaded or duration is zero.");
              }
            },
            // --- Drag Update ---
            onHorizontalDragUpdate: (details) {
              if (!_isDragging) return; // Ignore if not dragging

              final bloc = widget.audioPlayerBloc;
              final currentState = bloc.state;
              if (currentState is AudioPlayerLoaded &&
                  currentState.currentSource == widget.track.path &&
                  currentState.duration > Duration.zero) {
                final seekRatio = _calculateSeekRatio(details.globalPosition);
                if (seekRatio != null) {
                  _finalDragRatio = seekRatio; // Always update final ratio

                  // Throttle SeekAudio dispatch
                  final now = DateTime.now();
                  bool shouldDispatch =
                      _lastSeekDispatchTime == null ||
                      now.difference(_lastSeekDispatchTime!) >
                          _seekThrottleInterval;

                  if (shouldDispatch) {
                    final seekPosition = currentState.duration * seekRatio;
                    bloc.add(SeekAudio(position: seekPosition));
                    _lastSeekDispatchTime = now;
                    print(
                      "Throttled Seek Dispatched: ${seekPosition.inMilliseconds}ms",
                    );
                  }

                  // Update visual progress smoothly
                  setState(() {
                    _dragProgress = seekRatio;
                  });
                }
              }
            },
            // --- Drag End ---
            onHorizontalDragEnd: (details) {
              if (!_isDragging) return;

              final bloc = widget.audioPlayerBloc;
              final currentState = bloc.state;
              if (currentState is AudioPlayerLoaded &&
                  currentState.currentSource == widget.track.path &&
                  currentState.duration > Duration.zero) {
                // Dispatch final seek event unconditionally using the last calculated ratio
                final finalSeekPosition =
                    currentState.duration * _finalDragRatio;
                bloc.add(SeekAudio(position: finalSeekPosition));
                print(
                  "Final Seek Dispatched on DragEnd: ${finalSeekPosition.inMilliseconds}ms (Ratio: $_finalDragRatio)",
                );

                // Resume playback if it was playing before drag
                if (_wasPlayingBeforeDrag) {
                  bloc.add(PlayAudio());
                }
              }

              // Reset dragging state
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
                  // Pass drag progress to the painter
                  dragProgress: _dragProgress,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
