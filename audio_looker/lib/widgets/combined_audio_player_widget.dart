// lib/widgets/combined_audio_player_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async'; // For Timer
import 'dart:math' as math; // For finding next/prev tag

// Import BLoCs and Services/Models
import '../blocs/audio_player/audio_player_bloc.dart';
// import '../blocs/track_management/track_management_bloc.dart'; // <<< REMOVED Old BLoC
import '../blocs/track_management/track_metadata_bloc.dart'; // <<< ADDED Metadata BLoC
import '../services/collection_service.dart'; // Keep for Track and Tag models
import '../services/audio_service.dart'; // Needed for AudioTag definition

// Import UI components
import 'waveform_painter.dart';
// import 'tag_editor_popup.dart'; // <<< REMOVED temporarily

class CombinedAudioPlayerWidget extends StatefulWidget {
  final Track track;
  final bool isMinimized;
  final VoidCallback onToggle;
  final VoidCallback? onPreviousPressed; // Keep for track skipping
  final VoidCallback? onNextPressed; // Keep for track skipping

  const CombinedAudioPlayerWidget({
    Key? key,
    required this.track,
    required this.isMinimized,
    required this.onToggle,
    this.onPreviousPressed,
    this.onNextPressed,
  }) : super(key: key);

  @override
  State<CombinedAudioPlayerWidget> createState() =>
      _CombinedAudioPlayerWidgetState();
}

class _CombinedAudioPlayerWidgetState extends State<CombinedAudioPlayerWidget>
    with SingleTickerProviderStateMixin {
  // --- Animation State (Managed Internally) ---
  late AnimationController _animationController;
  late Animation<double> _playerHeightAnimation;
  // Adjust heights as needed, potentially calculate dynamically
  final double _fullPlayerHeight =
      420; // Reduced height due to removed tag section
  final double _minimizedPlayerHeight =
      100; // Adjusted height for minimized bar

  // State mirroring parts of the old AudioPlayerWidget state
  final TextEditingController _notesController = TextEditingController();
  bool _isNoteExpanded = false;
  int _currentRating = 0; // Local state for optimistic UI update

  // State for Waveform Dragging & Throttling (Unchanged)
  bool _isDraggingWaveform = false;
  double? _dragProgress;
  bool _wasPlayingBeforeDrag = false;
  double _finalDragRatio = 0.0;
  DateTime? _lastSeekDispatchTime;
  final Duration _seekThrottleInterval = const Duration(milliseconds: 100);

  // State for Time Tagging (Unchanged)
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
      if (mounted) setState(() {}); // Rebuild while animating
    });
    // Set initial animation value based on the INITIAL isMinimized prop
    _animationController.value = widget.isMinimized ? 1.0 : 0.0;
    // --- End Animation Controller Init ---

    // Update local state from the initial track prop
    _updateStateFromWidget(widget.track);
  }

  @override
  void didUpdateWidget(CombinedAudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Animate when isMinimized prop changes
    if (widget.isMinimized != oldWidget.isMinimized) {
      if (widget.isMinimized) {
        _animationController.forward(); // Animate to minimized
      } else {
        _animationController.reverse(); // Animate to expanded
      }
    }

    // If the track prop itself changes, update internal state
    if (oldWidget.track.id != widget.track.id) {
      _updateStateFromWidget(widget.track);
      // Reset waveform drag state if track changes
      _isDraggingWaveform = false;
      _dragProgress = null;
    } else {
      // If only metadata changed in the prop (e.g., due to external update)
      // update local state if it differs from the prop.
      if (widget.track.rating != _currentRating) {
        _currentRating = widget.track.rating;
      }
      if (widget.track.comment != _notesController.text) {
        // Avoid resetting cursor position if user is actively typing
        // This might need more sophisticated handling if simultaneous edits are common
        if (!FocusScope.of(context).hasFocus ||
            FocusScope.of(context).focusedChild != _notesController.value) {
          _notesController.text = widget.track.comment;
        }
      }
    }
  }

  // Helper to update local state based on the track prop
  void _updateStateFromWidget(Track track) {
    if (!mounted) return;
    _currentRating = track.rating;
    // Only update text controller if it differs to avoid losing cursor position
    if (_notesController.text != track.comment) {
      _notesController.text = track.comment;
    }
    // Reset time tagging mode when track changes
    _isTimeTaggingMode = false;
    _timeTagController.clear();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _notesController.dispose();
    _timeTagController.dispose();
    super.dispose();
  }

  // --- UI Building Methods ---

  // Build the common toggle bar (Top bar for minimizing/expanding)
  Widget _buildToggleBar() {
    return Container(
      height: 36, // Standard height
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
            onPressed: widget.onToggle, // Call the callback from HomeScreen
            tooltip: widget.isMinimized ? 'Expand player' : 'Minimize player',
          ),
        ],
      ),
    );
  }

  // Build the UI for the minimized player bar
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
    final bool canInteract =
        duration > Duration.zero; // Enable buttons only if duration is known

    return Container(
      height: _minimizedPlayerHeight, // Ensure container has the correct height
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surface.withOpacity(0.95), // Slightly opaque surface
      ),
      child: Row(
        children: [
          // Previous Button
          IconButton(
            icon: const Icon(Icons.skip_previous),
            iconSize: 30,
            color:
                widget.onPreviousPressed != null
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).disabledColor,
            onPressed: widget.onPreviousPressed, // Use callback from props
            tooltip: 'Previous Track',
          ),
          const SizedBox(width: 4),
          // Play/Pause Button
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              size: 36,
              color:
                  canInteract
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor,
            ),
            onPressed:
                canInteract
                    ? () {
                      final bloc = context.read<AudioPlayerBloc>();
                      if (isPlaying) {
                        bloc.add(PauseAudio());
                      } else {
                        if (position >= duration && duration > Duration.zero) {
                          bloc.add(const SeekAudio(position: Duration.zero));
                          Future.delayed(
                            const Duration(milliseconds: 50),
                            () => bloc.add(PlayAudio()),
                          );
                        } else {
                          bloc.add(PlayAudio());
                        }
                      }
                    }
                    : null,
            tooltip: isPlaying ? 'Pause' : 'Play',
          ),
          const SizedBox(width: 4),
          // Next Button
          IconButton(
            icon: const Icon(Icons.skip_next),
            iconSize: 30,
            color:
                widget.onNextPressed != null
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).disabledColor,
            onPressed: widget.onNextPressed, // Use callback from props
            tooltip: 'Next Track',
          ),
          const SizedBox(width: 12),
          // Track Info
          Expanded(
            flex: 3, // Give more space to title/artist
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
          const SizedBox(width: 12),
          // Time Display & Progress Bar
          Text(
            _formatDuration(position),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2, // Give progress bar reasonable space
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3, // Slightly thicker
              backgroundColor: Theme.of(
                context,
              ).colorScheme.onSurface.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(duration),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          // Expand button is part of the toggle bar now
        ],
      ),
    );
  }

  // Build the UI for the expanded player
  Widget _buildExpandedPlayerUI(AudioPlayerLoaded playerState, Track track) {
    final isPlaying = playerState.isPlaying;
    final duration = playerState.duration;
    final position = playerState.position;
    final waveformData = playerState.waveformData;
    final timeTags = playerState.tags; // Time tags from AudioPlayerBloc state
    final bool canInteract = duration > Duration.zero;

    return SingleChildScrollView(
      // Allow content to scroll if needed
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16.0), // Padding at the bottom
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Header Section (Title, Artist, Rating) ---
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
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        _buildRatingBar(track.id!), // Pass track ID
                      ],
                    ),
                  ),
                  // --- REMOVED General Tags Section ---
                ],
              ),
            ),

            // --- Waveform Display Section ---
            Container(
              height: 120,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // GestureDetector for Waveform Interaction (Unchanged)
                    GestureDetector(
                      onTapDown: (details) {
                        if (canInteract) {
                          final RenderBox box =
                              context.findRenderObject() as RenderBox;
                          final localPosition = box.globalToLocal(
                            details.globalPosition,
                          );
                          final containerWidth = box.size.width;
                          if (containerWidth > 0) {
                            final seekRatio = (localPosition.dx /
                                    containerWidth)
                                .clamp(0.0, 1.0);
                            final seekPosition = duration * seekRatio;
                            context.read<AudioPlayerBloc>().add(
                              SeekAudio(position: seekPosition),
                            );
                          }
                        }
                      },
                      onHorizontalDragStart: (details) {
                        if (canInteract) {
                          final bloc = context.read<AudioPlayerBloc>();
                          setState(() {
                            _isDraggingWaveform = true;
                            _wasPlayingBeforeDrag = isPlaying;
                            _lastSeekDispatchTime = null;
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
                            } else {
                              _dragProgress =
                                  playerState.position.inMilliseconds /
                                  duration.inMilliseconds.toDouble();
                              _finalDragRatio = _dragProgress ?? 0.0;
                            }
                          });
                          if (_wasPlayingBeforeDrag) bloc.add(PauseAudio());
                        }
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_isDraggingWaveform && canInteract) {
                          final RenderBox box =
                              context.findRenderObject() as RenderBox;
                          final localPosition = box.globalToLocal(
                            details.globalPosition,
                          );
                          final containerWidth = box.size.width;
                          if (containerWidth > 0) {
                            final seekRatio = (localPosition.dx /
                                    containerWidth)
                                .clamp(0.0, 1.0);
                            _finalDragRatio = seekRatio;
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
                            setState(() {
                              _dragProgress = seekRatio;
                            });
                          }
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        if (_isDraggingWaveform) {
                          if (canInteract) {
                            final finalSeekPosition =
                                duration * _finalDragRatio;
                            context.read<AudioPlayerBloc>().add(
                              SeekAudio(position: finalSeekPosition),
                            );
                          }
                          setState(() {
                            _isDraggingWaveform = false;
                            _dragProgress = null;
                            _lastSeekDispatchTime = null;
                          });
                          if (_wasPlayingBeforeDrag) {
                            Future.delayed(
                              const Duration(milliseconds: 50),
                              () {
                                if (mounted)
                                  context.read<AudioPlayerBloc>().add(
                                    PlayAudio(),
                                  );
                              },
                            );
                          }
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.transparent, // Makes it hittable
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: WaveformPainter(
                            waveformData: waveformData ?? [],
                            activeColor: Theme.of(context).colorScheme.primary,
                            inactiveColor: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                            playbackProgress:
                                canInteract
                                    ? (position.inMilliseconds /
                                            duration.inMilliseconds)
                                        .clamp(0.0, 1.0)
                                    : 0.0,
                            dragProgress: _dragProgress,
                            tags: timeTags, // Pass time tags from player state
                          ),
                        ),
                      ),
                    ),
                    // Loading indicator for waveform
                    if (waveformData == null || waveformData.isEmpty)
                      Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
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
                  Text(
                    _formatDuration(position),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    _formatDuration(duration),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),

            // --- Playback Controls (Expanded View) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceAround, // Distribute controls
                children: [
                  // Previous Track Button
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    iconSize: 36,
                    tooltip: 'Previous Track',
                    color:
                        widget.onPreviousPressed != null
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).disabledColor,
                    onPressed: widget.onPreviousPressed,
                  ),
                  // Play/Pause Button (Floating Action Button style)
                  FloatingActionButton(
                    tooltip: isPlaying ? 'Pause' : 'Play',
                    onPressed:
                        canInteract
                            ? () {
                              final bloc = context.read<AudioPlayerBloc>();
                              if (isPlaying) {
                                bloc.add(PauseAudio());
                              } else {
                                if (position >= duration &&
                                    duration > Duration.zero) {
                                  bloc.add(
                                    const SeekAudio(position: Duration.zero),
                                  );
                                  Future.delayed(
                                    const Duration(milliseconds: 50),
                                    () => bloc.add(PlayAudio()),
                                  );
                                } else {
                                  bloc.add(PlayAudio());
                                }
                              }
                            }
                            : null,
                    elevation: 2.0,
                    child: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 30,
                    ),
                  ),
                  // Next Track Button
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    iconSize: 36,
                    tooltip: 'Next Track',
                    color:
                        widget.onNextPressed != null
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).disabledColor,
                    onPressed: widget.onNextPressed,
                  ),
                  // Add Time Tag Button
                  IconButton(
                    icon: const Icon(Icons.bookmark_add_outlined),
                    tooltip: 'Add Time Tag at Current Position',
                    iconSize: 28,
                    color:
                        canInteract
                            ? Theme.of(context).colorScheme.secondary
                            : Theme.of(context).disabledColor,
                    onPressed:
                        canInteract
                            ? () {
                              if (mounted) {
                                setState(() {
                                  _isTimeTaggingMode = true;
                                });
                              }
                            }
                            : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- Time Tag Input Row ---
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
                      : const SizedBox.shrink(), // Show nothing when not tagging
            ),

            // --- Notes Section ---
            _buildNotesSection(), // Use helper method
          ],
        ),
      ),
    );
  }

  // --- Helper Methods ---

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  // Add time tag at the current playback position
  void _addTagAtCurrentPosition(AudioPlayerLoaded playerState) {
    if (_timeTagController.text.isNotEmpty &&
        playerState.duration > Duration.zero) {
      final bloc = context.read<AudioPlayerBloc>();
      final positionFraction = (playerState.position.inMilliseconds /
              playerState.duration.inMilliseconds)
          .clamp(0.0, 1.0);
      bloc.add(
        AddAudioTag(
          source: widget.track.path, // Use the current track's path
          position: positionFraction,
          label: _timeTagController.text,
        ),
      );
      _timeTagController.clear();
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
        // Text("Rating: ", style: TextStyle(color: Colors.grey[300], fontWeight: FontWeight.bold)),
        ...List.generate(5, (index) {
          final ratingValue = index + 1;
          return IconButton(
            iconSize: 24,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(),
            tooltip: '$ratingValue star${ratingValue > 1 ? 's' : ''}',
            icon: Icon(
              // Use local _currentRating for immediate feedback
              index < _currentRating ? Icons.star : Icons.star_border,
              color:
                  index < _currentRating
                      ? Colors.amber
                      : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              // Optimistically update local state
              setState(() {
                _currentRating = ratingValue;
              });
              // Dispatch event to TrackMetadataBloc to persist change
              // <<< CHANGED: Dispatch to TrackMetadataBloc >>>
              context.read<TrackMetadataBloc>().add(
                UpdateTrackRating(trackId, ratingValue),
              );
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
      elevation: 1, // Subtle elevation
      child: ExpansionTile(
        key: ValueKey('notes_expansion_${widget.track.id}'), // Keep key
        initiallyExpanded: _isNoteExpanded,
        onExpansionChanged: (expanded) {
          if (mounted) {
            setState(() {
              _isNoteExpanded = expanded;
            });
          }
        },
        title: const Text('Notes / Comments'),
        childrenPadding: const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16,
        ), // Adjust padding
        children: [
          TextField(
            controller: _notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Add notes...',
              border: OutlineInputBorder(),
            ),
            // Update BLoC on focus lost or explicitly via a save button
            onEditingComplete: () {
              if (mounted) {
                // <<< CHANGED: Dispatch to TrackMetadataBloc >>>
                context.read<TrackMetadataBloc>().add(
                  UpdateTrackComment(widget.track.id!, _notesController.text),
                );
                FocusScope.of(context).unfocus(); // Hide keyboard
              }
            },
            // Optional: Update on change (can be expensive)
            // onChanged: (text) {
            //   // Debounce this if using onChanged
            //   context.read<TrackMetadataBloc>().add(
            //     UpdateTrackComment(widget.track.id!, text),
            //   );
            // },
          ),
        ],
      ),
    );
  }

  // --- REMOVED _openTagEditor method ---
  // This needs access to GlobalTagBloc which is not created yet.

  // --- Main Build Method ---
  @override
  Widget build(BuildContext context) {
    // Use BlocBuilder to react to AudioPlayerBloc state changes
    return BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
      builder: (context, playerState) {
        // Determine if the correct track is loaded in the player
        bool isCorrectTrackLoaded =
            playerState is AudioPlayerLoaded &&
            playerState.currentSource == widget.track.path;
        bool isErrorForThisTrack =
            playerState is AudioPlayerError &&
            playerState.source == widget.track.path;
        bool isLoadingThisTrack =
            (playerState is AudioPlayerInitial ||
                playerState is AudioPlayerLoading) &&
            !isCorrectTrackLoaded;

        // --- Build UI based on Player State ---

        // Show loading indicator if loading this specific track
        if (isLoadingThisTrack) {
          return Container(
            height: _minimizedPlayerHeight, // Use minimized height for loading
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
        // Show error if error occurred for this specific track
        else if (isErrorForThisTrack) {
          return Container(
            height: _minimizedPlayerHeight, // Use minimized height for error
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
                  onPressed:
                      () => context.read<AudioPlayerBloc>().add(
                        LoadAudio(
                          source: widget.track.path,
                          isUrl: widget.track.isUrl,
                        ),
                      ),
                ),
              ],
            ),
          );
        }
        // Show player UI if the correct track is loaded
        else if (isCorrectTrackLoaded) {
          // Use AnimatedBuilder for smooth height transition
          return AnimatedBuilder(
            animation: _playerHeightAnimation,
            builder: (context, child) {
              return Container(
                height: _playerHeightAnimation.value,
                decoration: BoxDecoration(
                  color:
                      Theme.of(
                        context,
                      ).colorScheme.surface, // Use surface color
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8, // Softer shadow
                      spreadRadius: 1,
                      offset: const Offset(0, -2),
                    ),
                  ],
                  // Optional: Add top border radius if desired
                  // borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: child, // The Column containing toggle bar and content
              );
            },
            child: Column(
              children: [
                _buildToggleBar(), // The bar to minimize/expand
                Expanded(
                  // Use Stack to fade between minimized and expanded views
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
                                  .zero, // Opacity controlled by animation value
                          child: IgnorePointer(
                            // Disable interaction when hidden
                            ignoring: widget.isMinimized,
                            child: _buildExpandedPlayerUI(
                              playerState,
                              widget.track,
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
                                  .zero, // Opacity controlled by animation value
                          child: IgnorePointer(
                            // Disable interaction when hidden
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
        // Fallback: Track doesn't match or player is in an unexpected state (e.g., initial after app start)
        else {
          // Don't show anything if the player isn't loaded with *this* track
          return const SizedBox.shrink();
        }
      },
    );
  }
}
