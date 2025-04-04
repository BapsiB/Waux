import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';
import 'package:audio_looker/blocs/collection/collection_bloc.dart';
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
  final int trackId; // *** Add trackId ***

  // Keep existing callbacks...
  final Function(int)? onRatingChanged;
  final Function(String)? onNotesChanged;
  // *** Remove these if tag editing is fully handled by popup via CollectionBloc ***
  // final Function(String)? onAddGeneralTag;
  // final Function(String)? onRemoveGeneralTag;

  const AudioPlayerWidget({
    Key? key,
    required this.title,
    required this.artist,
    required this.audioSource,
    required this.isUrl,
    required this.trackId, // *** Make trackId required ***
    this.rating = 0,
    this.notes = '',
    this.generalTags = const [],
    this.onRatingChanged,
    this.onNotesChanged,
    // this.onAddGeneralTag,   // Remove
    // this.onRemoveGeneralTag, // Remove
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
  final TextEditingController _generalTagController = TextEditingController();
  bool _isTaggingMode = false;
  bool _isNoteExpanded = false;
  // bool _isTagsExpanded = false;
  int _currentRating = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Initialize with existing values
    _currentRating = widget.rating;
    _notesController.text = widget.notes;

    // Load the audio file
    context.read<AudioPlayerBloc>().add(
      LoadAudio(source: widget.audioSource, isUrl: widget.isUrl),
    );
  }

  @override
  void didUpdateWidget(AudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update local state if props changed
    if (oldWidget.rating != widget.rating) {
      _currentRating = widget.rating;
    }

    if (oldWidget.notes != widget.notes &&
        _notesController.text != widget.notes) {
      _notesController.text = widget.notes;
    }

    // Check if the audio source has changed
    if (oldWidget.audioSource != widget.audioSource) {
      // Load the new audio file
      context.read<AudioPlayerBloc>().add(
        LoadAudio(source: widget.audioSource, isUrl: widget.isUrl),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _tagController.dispose();
    _notesController.dispose();
    // _generalTagController.dispose();
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

  void _handleRatingChanged(int newRating) {
    setState(() {
      _currentRating = newRating;
    });

    if (widget.onRatingChanged != null) {
      widget.onRatingChanged!(newRating);
    }
  }

  void _handleNotesChanged() {
    if (widget.onNotesChanged != null) {
      widget.onNotesChanged!(_notesController.text);
    }
  }

  // void _addGeneralTag() {
  //   if (_generalTagController.text.isNotEmpty) {
  //     if (widget.onAddGeneralTag != null) {
  //       widget.onAddGeneralTag!(_generalTagController.text);
  //     }
  //     _generalTagController.clear();
  //   }
  // }

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
        onExpansionChanged: (expanded) {
          setState(() {
            _isNoteExpanded = expanded;
          });
        },
        title: const Text('Notes'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Add notes about this track...',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _handleNotesChanged(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openTagEditor(BuildContext buildContext, List<Tag> allAvailableTags) {
    // Use buildContext to avoid shadowing
    print('Trying to open tag editor...'); // Keep this for debugging
    final collectionState = buildContext.read<CollectionBloc>().state;
    print(
      'Current Collection State: ${collectionState.runtimeType}',
    ); // Keep for debugging

    if (collectionState is CollectionLoaded) {
      List<String> currentTrackTags = [];
      Track? currentTrack; // Use nullable Track

      try {
        currentTrack = collectionState.tracks.firstWhere(
          (t) => t.id == widget.trackId,
        );
        currentTrackTags = currentTrack.generalTags;
      } catch (e) {
        // Handle case where the track might not be in the list (should ideally not happen if selected)
        print(
          'Error: Could not find track with ID ${widget.trackId} in CollectionLoaded state.',
        );
        ScaffoldMessenger.of(buildContext).showSnackBar(
          const SnackBar(content: Text('Error: Could not find track data.')),
        );
        return; // Don't proceed if track not found
      }

      // *** ADD THIS BACK ***
      showDialog(
        context: buildContext, // Use the context passed into the function
        builder: (BuildContext dialogContext) {
          // Provide the CollectionBloc to the popup if not already available via context
          return BlocProvider.value(
            value: BlocProvider.of<CollectionBloc>(
              buildContext,
            ), // Use the context from the widget tree
            child: TagEditorPopup(
              trackId: widget.trackId,
              currentTrackTags: currentTrackTags, // Pass the current tags
            ),
          );
        },
      );
      // *** END OF ADDED CODE ***
    } else {
      // Handle case where collection isn't loaded
      print('Collection state is NOT Loaded, cannot open editor.');
      ScaffoldMessenger.of(buildContext).showSnackBar(
        const SnackBar(
          content: Text('Tags are still loading or failed to load.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use BlocBuilder for CollectionBloc to get allTags for Chip colors
    // This assumes CollectionBloc is provided higher up in your widget tree
    return BlocBuilder<CollectionBloc, CollectionState>(
      builder: (context, collectionState) {
        // Get all defined tags for color lookup (if CollectionBloc is loaded)
        final allTagsMap =
            <String, Tag>{}; // Assuming Tag model exists from CollectionService
        if (collectionState is CollectionLoaded) {
          for (var tag in collectionState.allTags) {
            allTagsMap[tag.name] = tag;
          }
        }

        // Use BlocBuilder for AudioPlayerBloc to get player state
        return BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
          builder: (context, playerState) {
            // Handle Initial, Loading, and Error states first
            if (playerState is AudioPlayerInitial) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.teal),
              );
            } else if (playerState is AudioPlayerLoading) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.yellow),
              );
            } else if (playerState is AudioPlayerError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error loading audio: ${playerState.message}'),
                ),
              );
            }
            // Handle the Loaded state where we have player data
            else if (playerState is AudioPlayerLoaded) {
              final isPlaying = playerState.isPlaying;
              final duration = playerState.duration;
              final position = playerState.position;
              final waveformData = playerState.waveformData;
              // Filter time-based tags based on duration (example logic)
              final tags =
                  playerState.tags
                      .where(
                        (tag) =>
                            tag.position >= 0 &&
                            tag.position <= duration.inMilliseconds / 1000.0,
                      )
                      .toList();

              // Update animation controller based on play state
              if (isPlaying) {
                _animationController.forward();
              } else {
                _animationController.reverse();
              }

              // Get the current track's general tags from the widget property
              final currentGeneralTags = widget.generalTags;

              // Main widget layout
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Header Section ---
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        // Use Row for side-by-side layout
                        crossAxisAlignment:
                            CrossAxisAlignment.start, // Align items to the top
                        children: [
                          // Left side: Title, Artist, Rating
                          Expanded(
                            // Takes available horizontal space
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                  maxLines: 2, // Allow wrapping slightly
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
                                _buildRatingBar(), // Assumes this helper exists
                              ],
                            ),
                          ),
                          const SizedBox(
                            width: 8,
                          ), // Spacer between left and right
                          // Right side: Tags and Add Button
                          Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .end, // Align items to the right
                            mainAxisSize:
                                MainAxisSize.min, // Take minimum vertical space
                            children: [
                              if (currentGeneralTags.isNotEmpty)
                                SizedBox(
                                  // Constrain the width for tags
                                  width:
                                      MediaQuery.of(context).size.width *
                                      0.35, // Adjust width as needed
                                  child: Wrap(
                                    spacing: 4.0,
                                    runSpacing: 4.0,
                                    alignment:
                                        WrapAlignment
                                            .end, // Align chips to the end (right)
                                    children:
                                        currentGeneralTags.map((tag) {
                                          final tagData = allTagsMap[tag];
                                          return ActionChip(
                                            avatar: CircleAvatar(
                                              radius: 8,
                                              backgroundColor:
                                                  tagData?.color ??
                                                  Colors
                                                      .grey[600], // Use lookup color
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
                                              // Use the CollectionState available from the outer BlocBuilder
                                              if (collectionState
                                                  is CollectionLoaded) {
                                                _openTagEditor(
                                                  context,
                                                  collectionState.allTags,
                                                );
                                              }
                                            },
                                          );
                                        }).toList(),
                                  ),
                                ),
                              const SizedBox(
                                height: 4,
                              ), // Space between tags and button
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                tooltip: 'Edit Tags',
                                onPressed: () {
                                  // Use the CollectionState available from the outer BlocBuilder
                                  if (collectionState is CollectionLoaded) {
                                    _openTagEditor(
                                      context,
                                      collectionState.allTags,
                                    );
                                  } else {
                                    // Optional: Show a message if tags aren't loaded yet
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Tags are still loading...',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // --- Waveform Display Section ---
                    Container(
                      height: 200, // Example height
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            // Waveform visualization using CustomPaint and WaveformPainter
                            if (waveformData != null && waveformData.isNotEmpty)
                              GestureDetector(
                                // Seek on tap
                                onTapDown: (details) {
                                  // Calculation to seek based on tap position
                                  final RenderBox box =
                                      context.findRenderObject() as RenderBox;
                                  final localPosition = box.globalToLocal(
                                    details.globalPosition,
                                  );
                                  // Adjust for the container's horizontal margin if necessary
                                  final containerWidth = box.size.width;
                                  // Ensure seek position is within bounds
                                  final seekRatio = (localPosition.dx /
                                          containerWidth)
                                      .clamp(0.0, 1.0);
                                  final seekPosition = duration * seekRatio;
                                  context.read<AudioPlayerBloc>().add(
                                    SeekAudio(position: seekPosition),
                                  );
                                },
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: WaveformPainter(
                                    // Your custom painter
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
                            else // Show loading indicator if waveform data isn't ready
                              const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.pink,
                                ),
                              ),

                            // Overlay time-based tag markers on the waveform
                            if (waveformData != null)
                              for (var tag in tags)
                                // Position calculation needs accurate duration and container width
                                if (duration.inMilliseconds > 0)
                                  Positioned(
                                    left:
                                        (tag.position /
                                                (duration.inMilliseconds /
                                                    1000.0)) *
                                            MediaQuery.of(context).size.width -
                                        16, // Approximate calculation needs refinement
                                    top: 0,
                                    bottom: 0,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _currentTag = tag.label;
                                        });
                                      }, // Display tag label on tap
                                      child: Container(
                                        width: 2,
                                        color: Colors.redAccent,
                                      ), // Simple marker line
                                    ),
                                  ),

                            // Display current selected time-based tag info (optional)
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
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Colors.white,
                                        ),
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

                    // --- Time Indicators ---
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(position),
                          ), // Assumes helper exists
                          Text(
                            _formatDuration(duration),
                          ), // Assumes helper exists
                        ],
                      ),
                    ),

                    // --- Playback Controls ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.replay_10,
                          ), // Example: Rewind 10s
                          iconSize: 32,
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
                          onPressed: () {
                            if (isPlaying) {
                              context.read<AudioPlayerBloc>().add(PauseAudio());
                            } else {
                              context.read<AudioPlayerBloc>().add(PlayAudio());
                            }
                          },
                          child: AnimatedIcon(
                            // Animated play/pause icon
                            icon: AnimatedIcons.play_pause,
                            progress: _animationController,
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(
                            Icons.forward_10,
                          ), // Example: Forward 10s
                          iconSize: 32,
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
                    const SizedBox(height: 16), // Spacer
                    // --- Time-based Tagging Controls ---
                    if (!_isTaggingMode) // Show button if not in tagging mode
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Add Time Tag'),
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
                    else // Show text field and buttons if in tagging mode
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller:
                                    _tagController, // Assumes controller exists
                                decoration: const InputDecoration(
                                  hintText: 'Enter time tag name',
                                  border: OutlineInputBorder(),
                                ),
                                autofocus: true,
                                onSubmitted:
                                    (_) =>
                                        _addTagAtCurrentPosition(), // Assumes helper exists
                              ),
                            ),
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

                    // --- Notes Section ---
                    _buildNotesSection(), // Assumes this helper builds the notes ExpansionTile
                    // --- REMOVED General Tags Section ---
                    // The old _buildTagsSection() is intentionally removed here.

                    // Bottom padding for scroll leeway
                    const SizedBox(height: 24),
                  ],
                ),
              );
            }

            // Fallback for any unexpected state (should ideally not happen)
            return const Center(child: Text('Unknown player state'));
          },
        );
      },
    );
  }
}
