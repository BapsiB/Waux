// lib/widgets/combined_audio_player_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async'; // For Timer

// Import BLoCs and Services/Models
import '../blocs/audio_player/audio_player_bloc.dart';
import '../blocs/collection/collection_bloc.dart'; // Keep for collection state access
import '../services/collection_service.dart'; // Keep for Track and Tag models
// import '../services/audio_service.dart'; // AudioService likely not needed directly here

// Import UI components
import 'waveform_painter.dart';
import 'tag_editor_popup.dart';

class CombinedAudioPlayerWidget extends StatefulWidget {
  final Track track;
  final bool isMinimized;
  final VoidCallback onToggle;
  // *** ADDED CALLBACKS ***
  final VoidCallback? onPreviousPressed;
  final VoidCallback? onNextPressed;

  const CombinedAudioPlayerWidget({
    Key? key,
    required this.track,
    required this.isMinimized,
    required this.onToggle,
    // *** ADDED CALLBACKS TO CONSTRUCTOR ***
    this.onPreviousPressed,
    this.onNextPressed,
  }) : super(key: key);

  @override
  State<CombinedAudioPlayerWidget> createState() =>
      _CombinedAudioPlayerWidgetState();
}

// ADDED SingleTickerProviderStateMixin
class _CombinedAudioPlayerWidgetState extends State<CombinedAudioPlayerWidget>
    with SingleTickerProviderStateMixin {
  // --- Animation State (Managed Internally) ---
  late AnimationController _animationController;
  late Animation<double> _playerHeightAnimation;
  final double _fullPlayerHeight = 490; // Or determine dynamically
  final double _minimizedPlayerHeight =
      100; // Height for the minimized controls bar
  // --- End Animation State ---

  // State mirroring parts of the old AudioPlayerWidget state
  final TextEditingController _notesController = TextEditingController();
  bool _isNoteExpanded = false;
  int _currentRating = 0;

  // State for Waveform Dragging & Throttling
  bool _isDraggingWaveform = false;
  double? _dragProgress;
  bool _wasPlayingBeforeDrag = false;
  double _finalDragRatio = 0.0;
  DateTime? _lastSeekDispatchTime;
  final Duration _seekThrottleInterval = const Duration(milliseconds: 100);

  // State for Time Tagging
  final TextEditingController _timeTagController = TextEditingController();
  bool _isTimeTaggingMode = false;

  @override
  void initState() {
    super.initState();

    // --- Initialize Animation Controller (Internal) ---
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _playerHeightAnimation = Tween<double>(
      begin: _fullPlayerHeight,
      end: _minimizedPlayerHeight,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    )..addListener(() {
      // Optional: Add listener if needed, e.g., for state updates during animation
      if (mounted) setState(() {}); // Rebuild while animating
    });
    // Set initial animation value based on the INITIAL isMinimized prop
    _animationController.value = widget.isMinimized ? 1.0 : 0.0;
    // --- End Animation Controller Init ---

    _updateStateFromWidget(widget.track);
    // No need to load audio here, HomeScreen handles it
  }

  @override
  void didUpdateWidget(CombinedAudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // --- Animate when isMinimized prop changes ---
    if (widget.isMinimized != oldWidget.isMinimized) {
      print(
        "CombinedAudioPlayerWidget: isMinimized changed to ${widget.isMinimized}. Triggering animation.",
      );
      if (widget.isMinimized) {
        _animationController.forward(); // Animate to minimized
      } else {
        _animationController.reverse(); // Animate to expanded
      }
    }
    // --- End Animate ---

    // If the track itself changes, update internal state
    if (oldWidget.track.id != widget.track.id) {
      _updateStateFromWidget(widget.track);
      _isDraggingWaveform = false;
      _dragProgress = null;
    } else {
      // Update rating/notes if changed externally
      if (oldWidget.track.rating != widget.track.rating) {
        _currentRating = widget.track.rating;
      }
      if (oldWidget.track.comment != widget.track.comment &&
          _notesController.text != widget.track.comment) {
        _notesController.text = widget.track.comment;
      }
    }
  }

  void _updateStateFromWidget(Track track) {
    if (!mounted) return;
    _currentRating = track.rating;
    if (_notesController.text != track.comment) {
      _notesController.text = track.comment;
    }
    _isTimeTaggingMode = false;
    _timeTagController.clear();
  }

  // Helper to load audio if it's not already loaded/loading for the current track
  void _loadAudioIfNeeded(Track track) {
    final bloc = context.read<AudioPlayerBloc>();
    final currentState = bloc.state;
    bool needsLoad = true;
    if (currentState is AudioPlayerLoaded &&
        currentState.currentSource == track.path) {
      needsLoad = false;
    } else if (currentState is AudioPlayerLoading) {
      needsLoad = false; // Assume it's loading the right one or wait
    }
    if (needsLoad) {
      print("CombinedAudioPlayer: Dispatching LoadAudio for track ${track.id}");
      bloc.add(LoadAudio(source: track.path, isUrl: track.isUrl));
    }
  }

  @override
  void dispose() {
    _animationController.dispose(); // Dispose internal controller
    _notesController.dispose();
    _timeTagController.dispose();
    super.dispose();
  }

  // --- UI Building Methods ---

  // Build the common toggle bar
  Widget _buildToggleBar() {
    return Container(
      height: 36, // Standard height for the toggle bar
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              widget.isMinimized
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
            ),
            onPressed: widget.onToggle,
            tooltip: widget.isMinimized ? 'Expand player' : 'Minimize player',
          ),
        ],
      ),
    );
  }

  // Build the UI for the minimized player
  Widget _buildMinimizedPlayerControls(
    AudioPlayerLoaded playerState,
    Track track,
  ) {
    final isPlaying = playerState.isPlaying;
    final position = playerState.position;
    final duration = playerState.duration;
    final progress =
        duration > Duration.zero
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
              0.0,
              1.0,
            )
            : 0.0;
    final canPrevious = duration > Duration.zero; // Can seek if duration exists
    final canNext = duration > Duration.zero; // Can seek if duration exists

    return Container(
      height: _minimizedPlayerHeight, // Ensure container has the correct height
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.9),
        // Removed border, handled by the outer container's shadow
      ),
      child: Row(
        children: [
          // *** ADDED Previous Button ***
          IconButton(
            icon: const Icon(Icons.skip_previous),
            iconSize: 30, // Slightly smaller
            color:
                canPrevious
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).disabledColor,
            onPressed: canPrevious ? widget.onPreviousPressed : null,
            tooltip: 'Previous Track',
          ),
          const SizedBox(width: 4), // Spacing
          // Play/Pause Button
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              size: 36, // Slightly smaller for minimized view
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () {
              final bloc = context.read<AudioPlayerBloc>();
              if (isPlaying) {
                bloc.add(PauseAudio());
              } else {
                // Handle case where track ended and user hits play again
                if (position >= duration && duration > Duration.zero) {
                  bloc.add(const SeekAudio(position: Duration.zero));
                }
                bloc.add(PlayAudio());
              }
            },
            tooltip: isPlaying ? 'Pause' : 'Play',
          ),
          const SizedBox(width: 4), // Spacing
          // *** ADDED Next Button ***
          IconButton(
            icon: const Icon(Icons.skip_next),
            iconSize: 30, // Slightly smaller
            color:
                canNext
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).disabledColor,
            onPressed: canNext ? widget.onNextPressed : null,
            tooltip: 'Next Track',
          ),
          const SizedBox(width: 8),

          // Track Info (Expanded)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Time Display
          Text(
            _formatDuration(position),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 4),
          // Optional: Simple Progress Bar
          Expanded(
            flex: 2, // Give progress bar some space
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: Colors.grey[700],
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _formatDuration(duration),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          // Expand button is part of the toggle bar now
        ],
      ),
    );
  }

  // Build the UI for the expanded player (incorporating elements from AudioPlayerWidget)
  Widget _buildExpandedPlayerUI(
    AudioPlayerLoaded playerState,
    Track track,
    CollectionState collectionState,
  ) {
    final isPlaying = playerState.isPlaying;
    final duration = playerState.duration;
    final position = playerState.position;
    final waveformData = playerState.waveformData;
    final timeTags = playerState.tags;
    final canPrevious = duration > Duration.zero;
    final canNext = duration > Duration.zero;

    // Get general tags for the current track from collection state
    List<String> currentGeneralTags = [];
    final allTagsMap = <String, Tag>{}; // Map for tag colors
    if (collectionState is CollectionLoaded) {
      try {
        final currentTrackFromBloc = collectionState.tracks.firstWhere(
          (t) => t.id == track.id,
          // Use widget's track data as fallback if not found in bloc state yet
          orElse: () => track,
        );
        currentGeneralTags = currentTrackFromBloc.generalTags;
        // Build map for colors
        for (var tag in collectionState.allTags) {
          allTagsMap[tag.name] = tag;
        }
      } catch (e) {
        print(
          "Warning: Track ${track.id} not found in CollectionBloc state for expanded view, using widget.generalTags.",
        );
        currentGeneralTags = track.generalTags; // Fallback
      }
    } else {
      currentGeneralTags = track.generalTags; // Fallback
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Header Section (Reused from AudioPlayerWidget structure) ---
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
                        track.title,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.grey[400],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      _buildRatingBar(track.id!), // Pass track ID
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // --- General Tags Section ---
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentGeneralTags.isNotEmpty)
                      SizedBox(
                        // Limit width to prevent overflow
                        width: MediaQuery.of(context).size.width * 0.35,
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
                                        tagData?.color ?? Colors.grey[600],
                                  ),
                                  label: Text(tag),
                                  labelStyle: const TextStyle(fontSize: 12),
                                  tooltip: 'Edit tags',
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  onPressed: () {
                                    // Ensure collection state is loaded before opening editor
                                    if (collectionState is CollectionLoaded) {
                                      _openTagEditor(
                                        context,
                                        collectionState.allTags,
                                      );
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Tags are still loading...',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                );
                              }).toList(),
                        ),
                      ),
                    const SizedBox(height: 4),
                    // "Edit Tags" Button
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Edit Tags',
                      onPressed: () {
                        if (collectionState is CollectionLoaded) {
                          _openTagEditor(context, collectionState.allTags);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tags are still loading...'),
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
            height: 120, // Consistent height
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey[900], // Dark background for waveform
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // GestureDetector for Waveform Interaction
                  GestureDetector(
                    onTapDown: (details) {
                      if (duration > Duration.zero) {
                        final RenderBox box =
                            context.findRenderObject() as RenderBox;
                        final localPosition = box.globalToLocal(
                          details.globalPosition,
                        );
                        final containerWidth = box.size.width;
                        if (containerWidth > 0) {
                          final seekRatio = (localPosition.dx / containerWidth)
                              .clamp(0.0, 1.0);
                          final seekPosition = duration * seekRatio;
                          context.read<AudioPlayerBloc>().add(
                            SeekAudio(position: seekPosition),
                          );
                          // Optional: Play on tap if paused?
                          // if (!isPlaying) context.read<AudioPlayerBloc>().add(PlayAudio());
                        }
                      }
                    },
                    onHorizontalDragStart: (details) {
                      if (duration > Duration.zero) {
                        final bloc = context.read<AudioPlayerBloc>();
                        setState(() {
                          _isDraggingWaveform = true;
                          _wasPlayingBeforeDrag = isPlaying;
                          _lastSeekDispatchTime = null; // Reset timer
                          final RenderBox box =
                              context.findRenderObject() as RenderBox;
                          final localPosition = box.globalToLocal(
                            details.globalPosition,
                          );
                          final containerWidth = box.size.width;
                          if (containerWidth > 0) {
                            _finalDragRatio = (localPosition.dx /
                                    containerWidth)
                                .clamp(0.0, 1.0);
                            _dragProgress = _finalDragRatio;
                            // Optional: Seek immediately on drag start?
                            // bloc.add(SeekAudio(position: duration * _finalDragRatio));
                          } else {
                            _dragProgress =
                                playerState.position.inMilliseconds /
                                duration.inMilliseconds.toDouble();
                            _finalDragRatio = _dragProgress ?? 0.0;
                          }
                        });
                        // Pause playback while dragging
                        if (_wasPlayingBeforeDrag) {
                          bloc.add(PauseAudio());
                        }
                      }
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_isDraggingWaveform && duration > Duration.zero) {
                        final RenderBox box =
                            context.findRenderObject() as RenderBox;
                        final localPosition = box.globalToLocal(
                          details.globalPosition,
                        );
                        final containerWidth = box.size.width;
                        if (containerWidth > 0) {
                          final seekRatio = (localPosition.dx / containerWidth)
                              .clamp(0.0, 1.0);
                          _finalDragRatio =
                              seekRatio; // Always update final ratio

                          // Throttle seek dispatch
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
                            _lastSeekDispatchTime = now;
                          }
                          // Update visual progress smoothly
                          setState(() {
                            _dragProgress = seekRatio;
                          });
                        }
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      if (_isDraggingWaveform) {
                        // Dispatch final seek event unconditionally
                        if (duration > Duration.zero) {
                          final finalSeekPosition = duration * _finalDragRatio;
                          context.read<AudioPlayerBloc>().add(
                            SeekAudio(position: finalSeekPosition),
                          );
                        }
                        setState(() {
                          _isDraggingWaveform = false;
                          _dragProgress = null;
                          _lastSeekDispatchTime = null;
                        });
                        // Resume playback if it was playing before drag
                        if (_wasPlayingBeforeDrag) {
                          // Add a small delay to allow the final seek to process
                          Future.delayed(const Duration(milliseconds: 50), () {
                            if (mounted)
                              context.read<AudioPlayerBloc>().add(PlayAudio());
                          });
                        }
                      }
                    },
                    child: Container(
                      // Ensures the GestureDetector covers the area
                      width: double.infinity,
                      height: double.infinity,
                      color: Colors.transparent, // Makes it hittable
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: WaveformPainter(
                          waveformData: waveformData ?? [],
                          activeColor: Theme.of(context).colorScheme.primary,
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
                  // Loading indicator for waveform
                  if (waveformData == null || waveformData.isEmpty)
                    const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        color: Colors.white54,
                      ),
                    ),
                  // TODO: Add Time Tag display overlay if needed
                ],
              ),
            ),
          ),

          // --- Time Indicators ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position)),
                Text(_formatDuration(duration)),
              ],
            ),
          ),

          // --- Playback Controls (Expanded View) ---
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10),
                iconSize: 32,
                tooltip: 'Rewind 10 seconds',
                onPressed:
                    duration == Duration.zero
                        ? null
                        : () {
                          final bloc = context.read<AudioPlayerBloc>();
                          final newPos = position - const Duration(seconds: 10);
                          bloc.add(
                            SeekAudio(
                              position:
                                  newPos < Duration.zero
                                      ? Duration.zero
                                      : newPos,
                            ),
                          );
                        },
              ),
              const SizedBox(width: 10), // Spacing
              // *** ADDED Previous Button ***
              IconButton(
                icon: const Icon(Icons.skip_previous),
                iconSize: 40,
                color:
                    canPrevious
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).disabledColor,
                onPressed: canPrevious ? widget.onPreviousPressed : null,
                tooltip: 'Previous Track',
              ),
              const SizedBox(width: 10), // Spacing
              // Play/Pause Button
              FloatingActionButton(
                tooltip: isPlaying ? 'Pause' : 'Play',
                onPressed:
                    duration == Duration.zero
                        ? null
                        : () {
                          final bloc = context.read<AudioPlayerBloc>();
                          if (isPlaying) {
                            bloc.add(PauseAudio());
                          } else {
                            // Handle play from end
                            if (position >= duration &&
                                duration > Duration.zero) {
                              bloc.add(
                                const SeekAudio(position: Duration.zero),
                              );
                            }
                            bloc.add(PlayAudio());
                          }
                        },
                // Use standard Icons, AnimatedIcon can be complex with BLoC state
                child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              const SizedBox(width: 10), // Spacing
              // *** ADDED Next Button ***
              IconButton(
                icon: const Icon(Icons.skip_next),
                iconSize: 40,
                color:
                    canNext
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).disabledColor,
                onPressed: canNext ? widget.onNextPressed : null,
                tooltip: 'Next Track',
              ),
              const SizedBox(width: 10), // Spacing

              IconButton(
                icon: const Icon(Icons.forward_10),
                iconSize: 32,
                tooltip: 'Forward 10 seconds',
                onPressed:
                    duration == Duration.zero
                        ? null
                        : () {
                          final bloc = context.read<AudioPlayerBloc>();
                          final newPos = position + const Duration(seconds: 10);
                          bloc.add(
                            SeekAudio(
                              position: newPos > duration ? duration : newPos,
                            ),
                          );
                        },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // --- Time-based Tagging Controls (Expanded View) ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child:
                _isTimeTaggingMode
                    ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _timeTagController,
                            decoration: const InputDecoration(
                              hintText: 'Enter time tag name',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            autofocus: true,
                            onSubmitted:
                                (_) => _addTagAtCurrentPosition(playerState),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                          tooltip: 'Save Tag',
                          onPressed:
                              () => _addTagAtCurrentPosition(playerState),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          tooltip: 'Cancel Tag',
                          onPressed: () {
                            setState(() {
                              _isTimeTaggingMode = false;
                              _timeTagController.clear();
                            });
                          },
                        ),
                      ],
                    )
                    : ElevatedButton.icon(
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Add Time Tag at Current Position'),
                      onPressed:
                          duration == Duration.zero
                              ? null
                              : () {
                                setState(() {
                                  _isTimeTaggingMode = true;
                                });
                              },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(
                          double.infinity,
                          40,
                        ), // Slightly smaller
                      ),
                    ),
          ),

          // --- Notes Section (Reused from AudioPlayerWidget structure) ---
          _buildNotesSection(), // Use helper method

          const SizedBox(height: 24), // Bottom padding
        ],
      ),
    );
  }

  // --- Helper Methods (Reused/Adapted from AudioPlayerWidget) ---

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  // Add time tag at the current playback position
  void _addTagAtCurrentPosition(AudioPlayerLoaded playerState) {
    if (_timeTagController.text.isNotEmpty) {
      final bloc = context.read<AudioPlayerBloc>();
      final positionFraction =
          playerState.duration > Duration.zero
              ? (playerState.position.inMilliseconds /
                      playerState.duration.inMilliseconds)
                  .clamp(0.0, 1.0)
              : 0.0;
      bloc.add(
        AddAudioTag(
          source: widget.track.path, // Use the current track's path
          position: positionFraction,
          label: _timeTagController.text,
        ),
      );
      _timeTagController.clear();
      // Use mounted check before calling setState
      if (mounted) {
        setState(() {
          _isTimeTaggingMode = false;
        });
      }
    }
  }

  // Build the rating bar UI
  Widget _buildRatingBar(int trackId) {
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
            onPressed: () {
              final newRating = index + 1;
              // Use mounted check before calling setState or accessing context
              if (mounted) {
                setState(() {
                  _currentRating = newRating;
                });
                context.read<CollectionBloc>().add(
                  UpdateTrackRating(trackId, newRating),
                );
              }
            },
          );
        }),
      ],
    );
  }

  // Build the expandable notes section UI
  Widget _buildNotesSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        // Key ensures state is kept if widget rebuilds for other reasons
        key: ValueKey('notes_expansion_${widget.track.id}'),
        initiallyExpanded: _isNoteExpanded,
        onExpansionChanged: (expanded) {
          // Use mounted check before calling setState
          if (mounted) {
            setState(() {
              _isNoteExpanded = expanded;
            });
          }
        },
        title: const Text('Notes / Comments'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Adjust padding
            child: TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Add notes...',
                border: OutlineInputBorder(),
              ),
              // Update BLoC on focus lost or explicitly via a save button
              onEditingComplete: () {
                // Use mounted check before accessing context
                if (mounted) {
                  context.read<CollectionBloc>().add(
                    UpdateTrackComment(widget.track.id!, _notesController.text),
                  );
                  FocusScope.of(context).unfocus(); // Hide keyboard
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // Open the general tag editor popup
  void _openTagEditor(BuildContext buildContext, List<Tag> allAvailableTags) {
    // Ensure we have the CollectionBloc available
    final collectionBloc = BlocProvider.of<CollectionBloc>(buildContext);
    final collectionState = collectionBloc.state;

    if (collectionState is CollectionLoaded) {
      List<String> currentTrackTags = [];
      try {
        // Find the current track's tags from the CollectionLoaded state
        final currentTrackFromBloc = collectionState.tracks.firstWhere(
          (t) => t.id == widget.track.id,
          orElse: () => widget.track, // Fallback to widget's track data
        );
        currentTrackTags = currentTrackFromBloc.generalTags;
      } catch (e) {
        print('Error finding track ${widget.track.id} for tag editor: $e');
        // Use widget's tags as fallback
        currentTrackTags = widget.track.generalTags;
        // Optionally show a less severe warning
        ScaffoldMessenger.of(buildContext).showSnackBar(
          const SnackBar(
            content: Text('Using cached tags. Refresh collection for latest.'),
          ),
        );
      }

      showDialog(
        context: buildContext,
        // Use BlocProvider.value to pass the existing CollectionBloc instance
        builder:
            (dialogContext) => BlocProvider.value(
              value: collectionBloc,
              child: TagEditorPopup(
                trackId: widget.track.id!, // Ensure track ID is not null
                currentTrackTags: currentTrackTags,
              ),
            ),
      );
    } else {
      // Handle cases where tags aren't loaded yet
      ScaffoldMessenger.of(buildContext).showSnackBar(
        const SnackBar(content: Text('Tags are still loading... Please wait.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use BlocBuilder to react to AudioPlayerBloc state changes
    return BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
      builder: (context, playerState) {
        // Use another BlocBuilder for CollectionState to get general tags
        return BlocBuilder<CollectionBloc, CollectionState>(
          builder: (context, collectionState) {
            bool isCorrectTrackLoaded =
                playerState is AudioPlayerLoaded &&
                playerState.currentSource == widget.track.path;
            bool isErrorForThisTrack =
                playerState is AudioPlayerError &&
                playerState.source == widget.track.path;
            // Check if loading OR initial (and not the correct track already loaded)
            bool isLoadingThisTrack =
                (playerState is AudioPlayerInitial ||
                    playerState is AudioPlayerLoading) &&
                !isCorrectTrackLoaded;

            // Handle Loading state
            if (isLoadingThisTrack) {
              return Container(
                height:
                    _minimizedPlayerHeight, // Use minimized height for loading
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 16),
                    Text("Loading..."),
                  ],
                ),
              );
            }
            // Handle Error state specific to this track
            else if (isErrorForThisTrack) {
              return Container(
                height:
                    _minimizedPlayerHeight, // Use minimized height for error
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                color: Colors.red.withOpacity(0.1),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Error: ${playerState.message}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => _loadAudioIfNeeded(widget.track),
                    ),
                  ],
                ),
              );
            }
            // Show player UI if the correct track is loaded
            else if (isCorrectTrackLoaded) {
              return AnimatedBuilder(
                animation: _playerHeightAnimation,
                builder: (context, child) {
                  return Container(
                    height: _playerHeightAnimation.value,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: Column(
                  children: [
                    _buildToggleBar(),
                    Expanded(
                      child: Stack(
                        children: [
                          // Expanded View (Visible when animation value < 0.5)
                          Positioned.fill(
                            child: AnimatedOpacity(
                              opacity:
                                  _animationController.value < 0.5
                                      ? 1.0 - (_animationController.value * 2)
                                      : 0.0,
                              duration:
                                  Duration
                                      .zero, // Opacity handled by controller
                              child: IgnorePointer(
                                ignoring: widget.isMinimized,
                                child: _buildExpandedPlayerUI(
                                  playerState,
                                  widget.track,
                                  collectionState,
                                ),
                              ),
                            ),
                          ),
                          // Minimized View (Visible when animation value > 0.5)
                          Positioned.fill(
                            child: AnimatedOpacity(
                              opacity:
                                  _animationController.value > 0.5
                                      ? (_animationController.value - 0.5) * 2
                                      : 0.0,
                              duration:
                                  Duration
                                      .zero, // Opacity handled by controller
                              child: IgnorePointer(
                                ignoring: !widget.isMinimized,
                                child: _buildMinimizedPlayerControls(
                                  playerState,
                                  widget.track,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            // Fallback: Track doesn't match or player is in an unexpected state
            else {
              return const SizedBox.shrink();
            }
          },
        );
      },
    );
  }
}
