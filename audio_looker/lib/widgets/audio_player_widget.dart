import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';
import 'package:audio_looker/services/audio_service.dart';
import 'package:audio_looker/widgets/waveform_painter.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String title;
  final String artist;
  final String audioSource;
  final bool isUrl;

  const AudioPlayerWidget({
    Key? key,
    required this.title,
    required this.artist,
    required this.audioSource,
    required this.isUrl,
  }) : super(key: key);

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  String? _currentTag;
  final TextEditingController _tagController = TextEditingController();
  bool _isTaggingMode = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Load the audio file
    context.read<AudioPlayerBloc>().add(
      LoadAudio(source: widget.audioSource, isUrl: widget.isUrl),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  void _addTagAtCurrentPosition() {
    if (_tagController.text.isNotEmpty) {
      final bloc = context.read<AudioPlayerBloc>();
      final state = bloc.state;

      if (state is AudioPlayerLoaded) {
        // Get current position
        final position =
            state.position.inMilliseconds / 1000.0; // Convert to seconds

        bloc.add(
          AddAudioTag(
            source: widget.audioSource,
            position: position,
            label: _tagController.text,
          ),
        );

        _tagController.clear();
        setState(() {
          _isTaggingMode = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
      builder: (context, state) {
        if (state is AudioPlayerInitial) {
          return const Center(child: CircularProgressIndicator());
        } else if (state is AudioPlayerLoading) {
          return const Center(child: CircularProgressIndicator());
        } else if (state is AudioPlayerError) {
          return Center(child: Text('Error: ${state.message}'));
        } else if (state is AudioPlayerLoaded) {
          final isPlaying = state.isPlaying;
          final duration = state.duration;
          final position = state.position;
          final waveformData = state.waveformData;
          final tags =
              state.tags
                  .where(
                    (tag) =>
                        tag.position >= 0 &&
                        tag.position <= duration.inMilliseconds / 1000.0,
                  )
                  .toList();

          // Play/pause animation
          if (isPlaying) {
            _animationController.forward();
          } else {
            _animationController.reverse();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.artist,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),

              // Waveform
              Container(
                height: 200,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      // Waveform visualization
                      if (waveformData != null && waveformData.isNotEmpty)
                        GestureDetector(
                          onTapDown: (details) {
                            final RenderBox box =
                                context.findRenderObject() as RenderBox;
                            final localPosition = box.globalToLocal(
                              details.globalPosition,
                            );
                            final containerWidth = box.size.width;

                            final seekPosition =
                                duration * (localPosition.dx / containerWidth);
                            context.read<AudioPlayerBloc>().add(
                              SeekAudio(position: seekPosition),
                            );
                          },
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: WaveformPainter(
                              waveformData: waveformData,
                              activeColor: Theme.of(context).primaryColor,
                              inactiveColor: Colors.grey[700]!,
                              playbackProgress:
                                  duration.inMilliseconds > 0
                                      ? position.inMilliseconds /
                                          duration.inMilliseconds
                                      : 0.0,
                            ),
                          ),
                        )
                      else
                        const Center(child: CircularProgressIndicator()),

                      // Tag markers
                      if (waveformData != null)
                        for (var tag in tags)
                          Positioned(
                            left:
                                tag.position /
                                (duration.inMilliseconds / 1000.0) *
                                MediaQuery.of(context).size.width,
                            top: 0,
                            bottom: 0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _currentTag = tag.label;
                                });
                              },
                              child: Container(
                                width: 2,
                                color: Colors.white70,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      color: Theme.of(context).primaryColor,
                                      child: Text(
                                        tag.label,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                      // Current tag info
                      if (_currentTag != null)
                        Positioned(
                          bottom: 10,
                          left: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Expanded(
                                  child: Text(
                                    _currentTag!,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    setState(() {
                                      _currentTag = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Time indicators
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(position)),
                    Text(_formatDuration(duration)),
                  ],
                ),
              ),

              // Playback controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    iconSize: 36,
                    onPressed: () {
                      context.read<AudioPlayerBloc>().add(
                        SeekAudio(position: Duration.zero),
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton(
                    onPressed: () {
                      if (isPlaying) {
                        context.read<AudioPlayerBloc>().add(PauseAudio());
                      } else {
                        context.read<AudioPlayerBloc>().add(PlayAudio());
                      }
                    },
                    child: AnimatedIcon(
                      icon: AnimatedIcons.play_pause,
                      progress: _animationController,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    iconSize: 36,
                    onPressed: () {
                      context.read<AudioPlayerBloc>().add(StopAudio());
                    },
                  ),
                ],
              ),

              // Tagging controls
              if (!_isTaggingMode)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.bookmark_add),
                    label: const Text('Add Tag at Current Position'),
                    onPressed: () {
                      setState(() {
                        _isTaggingMode = true;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagController,
                          decoration: const InputDecoration(
                            hintText: 'Enter tag name',
                            border: OutlineInputBorder(),
                          ),
                          autofocus: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: _addTagAtCurrentPosition,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _isTaggingMode = false;
                            _tagController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),
            ],
          );
        }

        return const Center(child: Text('Unknown state'));
      },
    );
  }
}
