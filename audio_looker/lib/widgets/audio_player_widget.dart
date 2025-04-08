import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';
import 'package:audio_looker/blocs/track_management/track_management_bloc.dart';
import 'package:audio_looker/widgets/waveform_painter.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/widgets/tag_editor_popup.dart';

class AudioPlayerWidget extends StatefulWidget {
  // Keep existing properties...
  final String title;
  final String artist;
  final String audioSource;
  final bool isUrl;
  final int rating;
  final String notes;
  final List<String> generalTags;
  final int trackId;

  // Keep existing callbacks...
  final Function(int)? onRatingChanged;
  final Function(String)? onNotesChanged;

  const AudioPlayerWidget({
    Key? key,
    required this.title,
    required this.artist,
    required this.audioSource,
    required this.isUrl,
    required this.trackId,
    this.rating = 0,
    this.notes = '',
    this.generalTags = const [],
    this.onRatingChanged,
    this.onNotesChanged,
  }) : super(key: key);

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  String? _currentTag;
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _isTaggingMode = false;
  bool _isNoteExpanded = false;

  // --- State for Dragging & Throttling ---
  bool _isDragging = false;
  double? _dragProgress;
  bool _wasPlayingBeforeDrag = false;
  double _finalDragRatio = 0.0;
  DateTime? _lastSeekDispatchTime; // Added: Track last seek dispatch time
  final Duration _seekThrottleInterval = const Duration(
    milliseconds: 200,
  ); // Added: ~5 times per second
  // --- End Dragging State ---

  int _currentRating = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _currentRating = widget.rating;
    _notesController.text = widget.notes;
    _loadAudio();
  }

  @override
  void didUpdateWidget(AudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rating != widget.rating) {
      _currentRating = widget.rating;
    }
    if (oldWidget.notes != widget.notes &&
        _notesController.text != widget.notes) {
      _notesController.text = widget.notes;
    }
    if (oldWidget.audioSource != widget.audioSource) {
      _loadAudio();
    }
  }

  void _loadAudio() {
    context.read<AudioPlayerBloc>().add(
      LoadAudio(source: widget.audioSource, isUrl: widget.isUrl),
    );
    setState(() {
      _isDragging = false;
      _dragProgress = null;
      _wasPlayingBeforeDrag = false;
      _currentTag = null;
      _finalDragRatio = 0.0;
      _lastSeekDispatchTime = null; // Reset throttle timer on load
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _tagController.dispose();
    _notesController.dispose();
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
        final positionFraction =
            state.duration > Duration.zero
                ? (state.position.inMilliseconds /
                        state.duration.inMilliseconds)
                    .clamp(0.0, 1.0)
                : 0.0;
        bloc.add(
          AddAudioTag(
            source: widget.audioSource,
            position: positionFraction,
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

  void _handleRatingChanged(int newRating) {
    setState(() {
      _currentRating = newRating;
    });
    context.read<TrackManagementBloc>().add(
      UpdateTrackRating(widget.trackId, newRating),
    );
    widget.onRatingChanged?.call(newRating);
  }

  void _handleNotesChanged() {
    context.read<TrackManagementBloc>().add(
      UpdateTrackComment(widget.trackId, _notesController.text),
    );
    widget.onNotesChanged?.call(_notesController.text);
  }

  Widget _buildRatingBar() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Rating: ",
          style: TextStyle(
            color: Colors.grey[300],
            fontWeight: FontWeight.bold,
          ),
        ),
        ...List.generate(5, (index) {
          return IconButton(
            iconSize: 24,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(),
            icon: Icon(
              index < _currentRating ? Icons.star : Icons.star_border,
              color: index < _currentRating ? Colors.amber : Colors.grey[400],
            ),
            onPressed: () => _handleRatingChanged(index + 1),
          );
        }),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        initiallyExpanded: _isNoteExpanded,
        onExpansionChanged:
            (expanded) => setState(() {
              _isNoteExpanded = expanded;
            }),
        title: const Text('Notes'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Add notes...',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _handleNotesChanged(),
            ),
          ),
        ],
      ),
    );
  }

  void _openTagEditor(BuildContext buildContext, List<Tag> allAvailableTags) {
    final collectionState = buildContext.read<TrackManagementBloc>().state;
    if (collectionState is TrackManagementLoaded) {
      List<String> currentTrackTags = [];
      try {
        final currentTrack = collectionState.tracks.firstWhere(
          (t) => t.id == widget.trackId,
        );
        currentTrackTags = currentTrack.generalTags;
      } catch (e) {
        print('Error finding track ${widget.trackId} for tag editor: $e');
        ScaffoldMessenger.of(buildContext).showSnackBar(
          const SnackBar(content: Text('Could not load track tags.')),
        );
        return;
      }
      showDialog(
        context: buildContext,
        builder:
            (BuildContext dialogContext) => BlocProvider.value(
              value: BlocProvider.of<TrackManagementBloc>(buildContext),
              child: TagEditorPopup(
                trackId: widget.trackId,
                currentTrackTags: currentTrackTags,
              ),
            ),
      );
    } else {
      ScaffoldMessenger.of(buildContext).showSnackBar(
        const SnackBar(content: Text('Tags are still loading...')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TrackManagementBloc, TrackManagementState>(
      builder: (context, collectionState) {
        final allTagsMap = <String, Tag>{};
        if (collectionState is TrackManagementLoaded) {
          for (var tag in collectionState.allTags) {
            allTagsMap[tag.name] = tag;
          }
        }

        return BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
          builder: (context, playerState) {
            if (playerState is AudioPlayerInitial ||
                playerState is AudioPlayerLoading) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.red),
                      SizedBox(height: 16),
                      Text("Loading audio..."),
                    ],
                  ),
                ),
              );
            } else if (playerState is AudioPlayerError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 48),
                      SizedBox(height: 16),
                      Text('Error loading audio: ${playerState.message}'),
                      SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: Icon(Icons.refresh),
                        label: Text("Retry"),
                        onPressed: _loadAudio,
                      ),
                    ],
                  ),
                ),
              );
            } else if (playerState is AudioPlayerLoaded) {
              final isPlaying = playerState.isPlaying;
              final duration = playerState.duration;
              final position = playerState.position;
              final waveformData = playerState.waveformData;
              final timeTags = playerState.tags;

              if (isPlaying)
                _animationController.forward();
              else
                _animationController.reverse();

              List<String> currentGeneralTags = [];
              if (collectionState is TrackManagementLoaded) {
                try {
                  final currentTrack = collectionState.tracks.firstWhere(
                    (t) => t.id == widget.trackId,
                    orElse:
                        () =>
                            widget.generalTags.isNotEmpty
                                ? Track(
                                  id: widget.trackId,
                                  title: '',
                                  artist: '',
                                  album: '',
                                  path: '',
                                  isUrl: false,
                                  duration: 0,
                                  generalTags: widget.generalTags,
                                )
                                : throw Exception("Track not found"),
                  );
                  currentGeneralTags = currentTrack.generalTags;
                } catch (e) {
                  print(
                    "Warning: Track ${widget.trackId} not found in CollectionBloc state, using widget.generalTags as fallback.",
                  );
                  currentGeneralTags = widget.generalTags;
                }
              } else {
                currentGeneralTags = widget.generalTags;
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Header Section ---
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.artist,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(color: Colors.grey[400]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                _buildRatingBar(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (currentGeneralTags.isNotEmpty)
                                SizedBox(
                                  width:
                                      MediaQuery.of(context).size.width * 0.35,
                                  child: Wrap(
                                    spacing: 4.0,
                                    runSpacing: 4.0,
                                    alignment: WrapAlignment.end,
                                    children:
                                        currentGeneralTags.map((tag) {
                                          final tagData = allTagsMap[tag];
                                          return ActionChip(
                                            avatar: CircleAvatar(
                                              radius: 8,
                                              backgroundColor:
                                                  tagData?.color ??
                                                  Colors.grey[600],
                                            ),
                                            label: Text(tag),
                                            labelStyle: const TextStyle(
                                              fontSize: 12,
                                            ),
                                            tooltip: 'Edit tags',
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            onPressed: () {
                                              if (collectionState
                                                  is TrackManagementLoaded)
                                                _openTagEditor(
                                                  context,
                                                  collectionState.allTags,
                                                );
                                            },
                                          );
                                        }).toList(),
                                  ),
                                ),
                              const SizedBox(height: 4),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                tooltip: 'Edit Tags',
                                onPressed: () {
                                  if (collectionState is TrackManagementLoaded)
                                    _openTagEditor(
                                      context,
                                      collectionState.allTags,
                                    );
                                  else
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Tags are still loading...',
                                        ),
                                      ),
                                    );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // --- Waveform Display Section ---
                    Container(
                      height: 120,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // --- GestureDetector for Dragging and Tapping ---
                            GestureDetector(
                              onTapDown: (details) {
                                if (duration > Duration.zero) {
                                  final RenderBox box =
                                      context.findRenderObject() as RenderBox;
                                  final localPosition = box.globalToLocal(
                                    details.globalPosition,
                                  );
                                  final containerWidth = box.size.width;
                                  final seekRatio = (localPosition.dx /
                                          containerWidth)
                                      .clamp(0.0, 1.0);
                                  final seekPosition = duration * seekRatio;
                                  context.read<AudioPlayerBloc>().add(
                                    SeekAudio(position: seekPosition),
                                  );
                                }
                              },
                              onHorizontalDragStart: (details) {
                                if (duration > Duration.zero) {
                                  setState(() {
                                    _isDragging = true;
                                    _wasPlayingBeforeDrag = isPlaying;
                                    _lastSeekDispatchTime =
                                        null; // Reset timer on new drag
                                    final RenderBox box =
                                        context.findRenderObject() as RenderBox;
                                    final localPosition = box.globalToLocal(
                                      details.globalPosition,
                                    );
                                    final containerWidth = box.size.width;
                                    _finalDragRatio = (localPosition.dx /
                                            containerWidth)
                                        .clamp(0.0, 1.0);
                                    _dragProgress = _finalDragRatio;
                                  });
                                }
                              },
                              onHorizontalDragUpdate: (details) {
                                if (_isDragging && duration > Duration.zero) {
                                  final RenderBox box =
                                      context.findRenderObject() as RenderBox;
                                  final localPosition = box.globalToLocal(
                                    details.globalPosition,
                                  );
                                  final containerWidth = box.size.width;
                                  final seekRatio = (localPosition.dx /
                                          containerWidth)
                                      .clamp(0.0, 1.0);
                                  _finalDragRatio =
                                      seekRatio; // Always update final ratio

                                  // --- Throttle Seek Dispatch ---
                                  final now = DateTime.now();
                                  bool shouldDispatch =
                                      _lastSeekDispatchTime == null ||
                                      now.difference(_lastSeekDispatchTime!) >
                                          _seekThrottleInterval;

                                  if (shouldDispatch) {
                                    final seekPosition = duration * seekRatio;
                                    context.read<AudioPlayerBloc>().add(
                                      SeekAudio(position: seekPosition),
                                    );
                                    _lastSeekDispatchTime =
                                        now; // Update timestamp
                                    print(
                                      "Throttled Seek Dispatched: ${seekPosition.inMilliseconds}ms",
                                    );
                                  }
                                  // --- End Throttle ---

                                  // Always update visual progress smoothly
                                  setState(() {
                                    _dragProgress = seekRatio;
                                  });
                                }
                              },
                              onHorizontalDragEnd: (details) {
                                if (_isDragging) {
                                  // Dispatch final seek event unconditionally
                                  if (duration > Duration.zero) {
                                    final finalSeekPosition =
                                        duration * _finalDragRatio;
                                    context.read<AudioPlayerBloc>().add(
                                      SeekAudio(position: finalSeekPosition),
                                    );
                                    print(
                                      "Final Seek Dispatched on DragEnd: ${finalSeekPosition.inMilliseconds}ms (Ratio: $_finalDragRatio)",
                                    );
                                  }
                                  setState(() {
                                    _isDragging = false;
                                    _dragProgress = null;
                                    _lastSeekDispatchTime = null; // Reset timer
                                  });
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                height: double.infinity,
                                color: Colors.transparent,
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: WaveformPainter(
                                    waveformData: waveformData ?? [],
                                    activeColor: Theme.of(context).primaryColor,
                                    inactiveColor: Colors.grey[700]!,
                                    playbackProgress:
                                        duration > Duration.zero
                                            ? (position.inMilliseconds /
                                                    duration.inMilliseconds)
                                                .clamp(0.0, 1.0)
                                            : 0.0,
                                    dragProgress: _dragProgress,
                                    tags: timeTags,
                                  ),
                                ),
                              ),
                            ),
                            if (waveformData == null || waveformData.isEmpty)
                              const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  color: Colors.white54,
                                ),
                              ),
                            if (_currentTag != null)
                              Positioned(
                                bottom: 10,
                                left: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _currentTag!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _currentTag = null;
                                          });
                                        },
                                        child: const Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // --- Time Indicators ---
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

                    // --- Playback Controls ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.replay_10),
                          iconSize: 32,
                          tooltip: 'Rewind 10 seconds',
                          onPressed: () {
                            final newPos =
                                position - const Duration(seconds: 10);
                            context.read<AudioPlayerBloc>().add(
                              SeekAudio(
                                position:
                                    newPos < Duration.zero
                                        ? Duration.zero
                                        : newPos,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 16),
                        FloatingActionButton(
                          tooltip: isPlaying ? 'Pause' : 'Play',
                          onPressed: () {
                            if (isPlaying)
                              context.read<AudioPlayerBloc>().add(PauseAudio());
                            else
                              context.read<AudioPlayerBloc>().add(PlayAudio());
                          },
                          child: AnimatedIcon(
                            icon: AnimatedIcons.play_pause,
                            progress: _animationController,
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.forward_10),
                          iconSize: 32,
                          tooltip: 'Forward 10 seconds',
                          onPressed: () {
                            final newPos =
                                position + const Duration(seconds: 10);
                            context.read<AudioPlayerBloc>().add(
                              SeekAudio(
                                position: newPos > duration ? duration : newPos,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // --- Time-based Tagging Controls ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child:
                          _isTaggingMode
                              ? Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _tagController,
                                      decoration: const InputDecoration(
                                        hintText: 'Enter time tag name',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      autofocus: true,
                                      onSubmitted:
                                          (_) => _addTagAtCurrentPosition(),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    ),
                                    tooltip: 'Save Tag',
                                    onPressed: _addTagAtCurrentPosition,
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.cancel,
                                      color: Colors.red,
                                    ),
                                    tooltip: 'Cancel Tag',
                                    onPressed: () {
                                      setState(() {
                                        _isTaggingMode = false;
                                        _tagController.clear();
                                      });
                                    },
                                  ),
                                ],
                              )
                              : ElevatedButton.icon(
                                icon: const Icon(Icons.bookmark_add_outlined),
                                label: const Text(
                                  'Add Time Tag at Current Position',
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isTaggingMode = true;
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 48),
                                ),
                              ),
                    ),

                    // --- Notes Section ---
                    _buildNotesSection(),

                    const SizedBox(height: 24), // Bottom padding
                  ],
                ),
              );
            }
            return const Center(child: Text('Unknown player state'));
          },
        );
      },
    );
  }
}
