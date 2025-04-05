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
  bool _isCurrentlyPlaying = false;
  double _currentProgress = 0.0;
  StreamSubscription<AudioPlayerState>? _playerStateSubscription;

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

    if (playerState is AudioPlayerLoaded &&
        playerState.currentSource == widget.track.path) {
      isPlaying = playerState.isPlaying;
      if (playerState.duration > Duration.zero) {
        progress = (playerState.position.inMilliseconds /
                playerState.duration.inMilliseconds)
            .clamp(0.0, 1.0);
      }
    }

    // Update local state only if changed
    if (isPlaying != _isCurrentlyPlaying || progress != _currentProgress) {
      setState(() {
        _isCurrentlyPlaying = isPlaying;
        _currentProgress = progress;
      });
    }
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel(); // Cancel subscription
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No need to watch here, state is managed locally via listener

    return Row(
      children: [
        // Play/Pause Button
        IconButton(
          icon: Icon(
            _isCurrentlyPlaying
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline, // Use local state
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
            // Use the passed bloc instance directly
            final bloc = widget.audioPlayerBloc;
            final currentState = bloc.state;

            if (currentState is AudioPlayerLoaded &&
                currentState.currentSource == widget.track.path) {
              // This track is loaded
              if (currentState.isPlaying) {
                bloc.add(PauseAudio());
              } else {
                // If completed, seek to start before playing
                if (currentState.position >= currentState.duration &&
                    currentState.duration > Duration.zero) {
                  bloc.add(const SeekAudio(position: Duration.zero));
                }
                bloc.add(PlayAudio());
              }
            } else {
              // Different track or no track loaded, load and play this one
              bloc.add(
                LoadAudio(source: widget.track.path, isUrl: widget.track.isUrl),
              );
              Future.delayed(const Duration(milliseconds: 150), () {
                // Slightly longer delay
                // Check state again after delay
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
            behavior:
                HitTestBehavior
                    .opaque, // Make sure GestureDetector receives taps
            onTapDown: (details) {
              final bloc = widget.audioPlayerBloc;
              final currentState = bloc.state;

              if (currentState is AudioPlayerLoaded &&
                  currentState.currentSource == widget.track.path &&
                  currentState.duration > Duration.zero) {
                // This track is loaded and has duration, so we can seek
                // Need RenderBox to calculate position, get it from context
                final RenderBox? box = context.findRenderObject() as RenderBox?;
                if (box != null && box.hasSize) {
                  // Ensure box has size
                  final localPosition = box.globalToLocal(
                    details.globalPosition,
                  );
                  final containerWidth = box.size.width;
                  if (containerWidth > 0) {
                    final seekRatio = ((localPosition.dx - 30) /
                            (containerWidth - 30))
                        .clamp(0.0, 1.0);
                    final seekPosition = currentState.duration * seekRatio;
                    print(
                      'Waveform seek request: ${seekPosition.inMilliseconds}ms (Ratio: $seekRatio)',
                    );
                    bloc.add(SeekAudio(position: seekPosition));
                  }
                } else {
                  print(
                    "Waveform seek failed: RenderBox not found or has no size.",
                  );
                }
              } else {
                // Track not loaded or no duration, treat as play request
                print(
                  'Waveform click on unloaded/invalid track. Treating as play request.',
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
            // *** Remove intermediate Container ***
            child: SizedBox(
              // Use SizedBox to constrain height if needed
              height: 24,
              child: CustomPaint(
                size: Size.infinite, // Allow painter to fill the SizedBox
                painter: WaveformPainter(
                  waveformData: widget.track.waveformData ?? [],
                  activeColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.7),
                  inactiveColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.25),
                  playbackProgress:
                      _currentProgress, // Use local state for progress
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
