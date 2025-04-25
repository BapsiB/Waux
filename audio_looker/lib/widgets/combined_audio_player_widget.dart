// lib/widgets/combined_audio_player_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async'; // For Timer

// Import BLoCs and Services/Models
import '../blocs/audio_player/audio_player_bloc.dart';
import '../blocs/track_management/track_data_bloc.dart';
import '../blocs/track_management/global_tag_bloc.dart';
import '../blocs/track_management/track_metadata_bloc.dart'; // <<< ADDED Metadata BLoC
import '../services/collection_service.dart'; // Keep for Track and Tag models
import '../services/audio_service.dart'; // Needed for AudioTag definition
import '../widgets/tag_editor_popup.dart'; // Needed for AudioTag definition

// Import UI components
import 'waveform_painter.dart';

class CombinedAudioPlayerWidget extends StatefulWidget {
  final Track track;
  final bool isMinimized;
  final VoidCallback onToggle;
  final VoidCallback? onPreviousPressed; // Keep for track skipping
  final VoidCallback? onNextPressed; // Keep for track skipping
  final double maxExpandedHeight;

  const CombinedAudioPlayerWidget({
    Key? key,
    required this.track,
    required this.isMinimized,
    required this.onToggle,
    this.onPreviousPressed,
    this.onNextPressed,
    this.maxExpandedHeight = 0.0,
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
  // final double _fullPlayerHeight =
  double _currentVolume = 1.0;
  bool _isDraggingVolume = false;

  final double _minimizedPlayerHeight =
      100; // Adjusted height for minimized bar

  // State mirroring parts of the old AudioPlayerWidget state
  final TextEditingController _notesController = TextEditingController();
  bool _isNoteExpanded = false;
  int _currentRating = 0; // Local state for optimistic UI update
  bool _isTimeMarkingMode = false;
  Timer? _hideOverlayTimer;
  Offset? _hoverPositionForPainter;

  // State for Waveform Dragging & Throttling (Unchanged)
  bool _isDraggingWaveform = false;
  double? _dragProgress;
  bool _wasPlayingBeforeDrag = false;
  double _finalDragRatio = 0.0;
  DateTime? _lastSeekDispatchTime;
  final Duration _seekThrottleInterval = const Duration(milliseconds: 100);

  TimeMarker? _hoveredMarker;
  Offset? _hoverPosition; // Store local
  final GlobalKey _waveformContainerKey = GlobalKey();

  final GlobalKey _minimizedProgressBarKey = GlobalKey();
  // +++ Add state for minimized bar dragging +++
  bool _isDraggingMinimizedBar = false;
  double _minimizedDragRatio = 0.0;

  // State for Time Tagging (Unchanged)
  final TextEditingController _timeMarkerController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // --- Initialize Animation Controller (Internal) ---
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _playerHeightAnimation = Tween<double>(
      begin: widget.maxExpandedHeight,
      end: _minimizedPlayerHeight,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    )..addListener(() {
      if (mounted) setState(() {}); // Rebuild while animating
    });
    // Set initial animation value based on the INITIAL isMinimized prop
    _animationController.value = widget.isMinimized ? 1.0 : 0.0;

    final initialPlayerState = context.read<AudioPlayerBloc>().state;
    if (initialPlayerState is AudioPlayerLoaded) {
      _currentVolume = initialPlayerState.volume;
    }

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

    if (oldWidget.track.id != widget.track.id) {
      _updateStateFromWidget(widget.track);
      _isDraggingWaveform = false;
      _dragProgress = null;
      // Reset volume drag state if track changes (might not be necessary)
      _isDraggingVolume = false;
    } else {
      if (widget.track.rating != _currentRating) {
        _currentRating = widget.track.rating;
      }
      if (widget.track.comment != _notesController.text) {
        if (!FocusScope.of(context).hasFocus ||
            FocusScope.of(context).focusedChild != _notesController.value) {
          _notesController.text = widget.track.comment;
        }
      }
      // --- Update local volume if not currently dragging ---
      final playerState = context.read<AudioPlayerBloc>().state;
      if (playerState is AudioPlayerLoaded && !_isDraggingVolume) {
        if (_currentVolume != playerState.volume) {
          if (mounted) {
            setState(() {
              _currentVolume = playerState.volume;
            });
          } else {
            _currentVolume =
                playerState.volume; // Update directly if not mounted
          }
        }
      }
    }
  }

  // Helper to calculate seek ratio for the minimized bar
  double? _calculateMinimizedSeekRatio(Offset globalPosition) {
    final RenderBox? box =
        _minimizedProgressBarKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (box != null && box.hasSize) {
      final localPosition = box.globalToLocal(globalPosition);
      // Important: Adjust calculation based on the actual tappable area width
      // If the GestureDetector wraps the Expanded widget containing the progress bar:
      final progressBarWidth = box.size.width;
      if (progressBarWidth > 0) {
        // Clamp ensures the ratio stays between 0.0 and 1.0
        return (localPosition.dx / progressBarWidth).clamp(0.0, 1.0);
      }
    }
    return null;
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
    _isTimeMarkingMode = false;
    _timeMarkerController.clear();
  }

  @override
  void dispose() {
    _hideOverlayTimer?.cancel(); // Cancel timer on dispose
    _animationController.dispose();
    _notesController.dispose();
    _timeMarkerController.dispose();
    super.dispose();
  }

  // void _startHideOverlayTimer() {
  //   _hideOverlayTimer?.cancel(); // Cancel any existing timer
  //   _hideOverlayTimer = Timer(const Duration(milliseconds: 100), () {
  //     // Adjust delay as needed
  //     if (mounted) {
  //       setState(() {
  //         _hoveredMarker = null;
  //         _hoverPosition = null;
  //       });
  //     }
  //   });
  // }

  // Function to cancel the hide timer
  // void _cancelHideOverlayTimer() {
  //   _hideOverlayTimer?.cancel();
  // }

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
  // Build the UI for the minimized player bar
  Widget _buildMinimizedPlayerControls(
    AudioPlayerLoaded playerState,
    Track track,
  ) {
    final isPlaying = playerState.isPlaying;
    final position = playerState.position;
    final duration = playerState.duration;
    final double displayProgress =
        _isDraggingMinimizedBar
            ? _minimizedDragRatio
            : (duration > Duration.zero
                ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                  0.0,
                  1.0,
                )
                : 0.0);

    final bool canInteract = true; // Enable buttons only if duration is known

    return Container(
      height: _minimizedPlayerHeight, // Ensure container has the correct height
      padding: const EdgeInsets.symmetric(
        horizontal: 8.0,
        vertical: 4.0,
      ), // Adjusted padding
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surface.withOpacity(0.95), // Slightly opaque surface
      ),
      child: Row(
        children: [
          // --- Controls (Left) ---
          Row(
            mainAxisSize: MainAxisSize.min,
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
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
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
              const SizedBox(width: 4),
              // Shuffle Button
              IconButton(
                icon: Icon(
                  playerState.isShuffleActive
                      ? Icons
                          .shuffle_on_outlined // Icon when shuffle is ON
                      : Icons.shuffle, // Icon when shuffle is OFF
                ),
                iconSize: 20, // Adjust size as needed
                color:
                    playerState.isShuffleActive
                        ? Theme.of(context)
                            .colorScheme
                            .primary // Highlight color when ON
                        : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant, // Default color
                tooltip:
                    playerState.isShuffleActive
                        ? 'Disable Shuffle'
                        : 'Enable Shuffle',
                onPressed: () {
                  // Dispatch the toggle event to the BLoC
                  context.read<AudioPlayerBloc>().add(ToggleShuffle());
                },
              ),
            ],
          ),
          const SizedBox(width: 16), // Spacing between controls and center
          // --- Track Info & Progress (Center) ---
          // --- Track Info & Progress (Center) ---
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Track Title & Artist
                Center(
                  child: Text(
                    '${track.title} - ${track.artist}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),
                // Play Position Row (Time + Progress Bar + Duration)
                Row(
                  children: [
                    Text(
                      // +++ Show position based on drag or player state +++
                      _formatDuration(
                        _isDraggingMinimizedBar
                            ? (duration * _minimizedDragRatio)
                            : position,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // +++ Wrap Expanded progress bar area with GestureDetector +++
                    Expanded(
                      child: GestureDetector(
                        key: _minimizedProgressBarKey, // Assign key
                        behavior:
                            HitTestBehavior
                                .opaque, // Capture taps within bounds
                        onTapDown: (details) {
                          if (!canInteract) return;
                          final seekRatio = _calculateMinimizedSeekRatio(
                            details.globalPosition,
                          );
                          if (seekRatio != null) {
                            final bloc = context.read<AudioPlayerBloc>();
                            final seekPosition = duration * seekRatio;
                            bloc.add(SeekAudio(position: seekPosition));
                          }
                        },
                        onHorizontalDragStart: (details) {
                          if (!canInteract) return;
                          final seekRatio = _calculateMinimizedSeekRatio(
                            details.globalPosition,
                          );
                          if (seekRatio != null) {
                            setState(() {
                              _isDraggingMinimizedBar = true;
                              _minimizedDragRatio = seekRatio;
                              // Don't pause playback during drag on the minimized bar
                            });
                            // Optional: Immediately seek on drag start
                            // context.read<AudioPlayerBloc>().add(SeekAudio(position: duration * seekRatio));
                          }
                        },
                        onHorizontalDragUpdate: (details) {
                          if (!_isDraggingMinimizedBar || !canInteract) return;
                          final seekRatio = _calculateMinimizedSeekRatio(
                            details.globalPosition,
                          );
                          if (seekRatio != null) {
                            setState(() {
                              _minimizedDragRatio = seekRatio;
                            });
                            // Throttle seek updates if needed, similar to waveform painter
                            // For simplicity here, we seek directly. Add throttling if performance is an issue.
                            context.read<AudioPlayerBloc>().add(
                              SeekAudio(position: duration * seekRatio),
                            );
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          if (!_isDraggingMinimizedBar || !canInteract) return;
                          // Final seek is already done in onHorizontalDragUpdate
                          // Just reset the dragging state
                          setState(() {
                            _isDraggingMinimizedBar = false;
                          });
                        },
                        child: Padding(
                          // Add some padding to make the tap area slightly larger than the indicator height
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: SizedBox(
                            height: 6, // Visual height of the indicator
                            child: LinearProgressIndicator(
                              // +++ Use displayProgress which reflects drag state +++
                              value: displayProgress,
                              minHeight: 3, // Make the line thin
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // +++ End GestureDetector +++
                    const SizedBox(width: 6),
                    Text(
                      _formatDuration(
                        duration,
                      ), // Total duration from playerState
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16), // Spacing between center and right
          // --- Volume Slider (Right) ---
          SizedBox(
            width: 120, // Give the slider a fixed width
            child: SliderTheme(
              // Customize slider appearance
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.0, // Make track thinner
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6.0,
                ), // Smaller thumb
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 12.0,
                ), // Smaller overlay
                activeTrackColor: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(0.8),
                inactiveTrackColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.2),
                thumbColor: Theme.of(context).colorScheme.primary,
              ),
              child: Slider(
                // --- Use local state _currentVolume ---
                value: _currentVolume,
                min: 0.0,
                max: 1.0,
                // --- Add onChangeStart and onChangeEnd ---
                onChangeStart: (value) {
                  if (mounted) {
                    // Check mount status
                    setState(() {
                      _isDraggingVolume = true; // User starts dragging
                    });
                  } else {
                    _isDraggingVolume = true; // Update directly if not mounted
                  }
                },
                onChanged: (value) {
                  if (mounted) {
                    // Check mount status
                    // Update local state immediately for smooth UI feedback
                    setState(() {
                      _currentVolume = value;
                    });
                    // Dispatch event to BLoC
                    context.read<AudioPlayerBloc>().add(SetVolume(value));
                  }
                },
                onChangeEnd: (value) {
                  if (mounted) {
                    // Check mount status
                    setState(() {
                      _isDraggingVolume = false; // User stops dragging
                    });
                  } else {
                    _isDraggingVolume = false; // Update directly if not mounted
                  }
                  // Optional: Dispatch one final SetVolume event here if needed,
                  // but onChanged usually covers it.
                  // context.read<AudioPlayerBloc>().add(SetVolume(value));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openTagEditor(BuildContext buildContext) {
    // Access the BLoCs needed by the popup or for prerequisite checks
    final trackDataBloc = BlocProvider.of<TrackDataBloc>(buildContext);
    final globalTagBloc = BlocProvider.of<GlobalTagBloc>(buildContext);
    final trackMetadataBloc = BlocProvider.of<TrackMetadataBloc>(buildContext);

    final trackDataState = trackDataBloc.state;
    final globalTagState = globalTagBloc.state;

    // Ensure track data and global tags are loaded before opening
    if (trackDataState is TrackDataLoaded &&
        globalTagState is GlobalTagLoaded) {
      List<String> currentTrackTags = [];
      try {
        // Find the current track's tags from the TrackDataLoaded state
        final currentTrackFromBloc = trackDataState.tracks.firstWhere(
          (t) => t.id == widget.track.id,
          orElse: () => widget.track, // Fallback to widget's track data
        );
        currentTrackTags = currentTrackFromBloc.generalTags;
      } catch (e) {
        print('Error finding track ${widget.track.id} for tag editor: $e');
        // Use widget's tags as fallback if not found in current state
        currentTrackTags = widget.track.generalTags;
        ScaffoldMessenger.of(buildContext).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not find exact track state, using cached tags.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Show the dialog, providing necessary BLoCs to the popup
      showDialog(
        context: buildContext, // Use the context passed to the method
        // Use MultiBlocProvider if TagEditorPopup needs multiple BLoCs
        builder:
            (dialogContext) => MultiBlocProvider(
              providers: [
                // Provide existing instances to the dialog's context
                BlocProvider.value(value: globalTagBloc),
                BlocProvider.value(value: trackMetadataBloc),
                // TrackDataBloc is not typically needed directly by the tag editor itself
              ],
              child: TagEditorPopup(
                trackId: widget.track.id!, // Ensure track ID is not null
                currentTrackTags: currentTrackTags,
              ),
            ),
      );
    } else {
      // Handle cases where data isn't loaded yet
      String message = 'Cannot edit tags: ';
      if (trackDataState is! TrackDataLoaded) {
        message += 'Track data not loaded. ';
      }
      if (globalTagState is! GlobalTagLoaded) {
        message += 'Global tags not loaded.';
      }
      ScaffoldMessenger.of(
        buildContext,
      ).showSnackBar(SnackBar(content: Text(message)));
      // Optionally dispatch load events if appropriate
      if (globalTagState is! GlobalTagLoaded) {
        globalTagBloc.add(LoadGlobalTags());
      }
    }
  }

  Widget _buildExpandedPlayerUI(AudioPlayerLoaded playerState, Track track) {
    final isPlaying = playerState.isPlaying;
    final duration = playerState.duration;
    final position = playerState.position;
    final waveformData = playerState.waveformData;
    final timeMarkers = playerState.markers;
    final bool canInteract = true;
    // duration > Duration.zero;

    return BlocBuilder<TrackDataBloc, TrackDataState>(
      builder: (context, trackDataState) {
        List<String> currentGeneralTags = [];
        if (trackDataState is TrackDataLoaded) {
          try {
            final currentTrackFromBloc = trackDataState.tracks.firstWhere(
              (t) => t.id == track.id,
              orElse: () => track,
            );
            currentGeneralTags = currentTrackFromBloc.generalTags;
          } catch (e) {
            print("Error finding track in TrackDataBloc state: $e");
            currentGeneralTags = track.generalTags;
          }
        } else {
          currentGeneralTags = track.generalTags;
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Header Section (Title, Artist, Rating, General Tags) ---
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Side: Title, Artist, Rating
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
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            _buildRatingBar(track.id!),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8), // Spacer
                      // Right Side: General Tags Section
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // --- Display Existing Tags ---
                          if (currentGeneralTags.isNotEmpty)
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.35,
                              child: Wrap(
                                spacing: 4.0,
                                runSpacing: 4.0,
                                alignment: WrapAlignment.end,
                                children:
                                    currentGeneralTags.map((tag) {
                                      return Chip(
                                        label: Text(tag),
                                        labelStyle: const TextStyle(
                                          fontSize: 12,
                                        ),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                      );
                                    }).toList(),
                              ),
                            ),
                          const SizedBox(height: 4),
                          // --- Add Tag Button (Conditional UI) ---
                          BlocBuilder<GlobalTagBloc, GlobalTagState>(
                            builder: (context, globalTagState) {
                              final bool tagsLoaded =
                                  globalTagState is GlobalTagLoaded;
                              final bool hasTags =
                                  currentGeneralTags.isNotEmpty;

                              // *** CONDITIONAL BUTTON RENDERING ***
                              if (hasTags) {
                                // If tags exist, show the '+' icon button
                                return IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  tooltip: // IconButton *does* have tooltip
                                      tagsLoaded
                                          ? 'Edit Tags'
                                          : 'Loading tags...',
                                  onPressed:
                                      tagsLoaded
                                          ? () => _openTagEditor(context)
                                          : null,
                                  color:
                                      tagsLoaded
                                          ? Theme.of(context).iconTheme.color
                                          : Colors.grey,
                                );
                              } else {
                                // If no tags exist, show the "Add Tag" button
                                // *** WRAP TextButton.icon with Tooltip ***
                                return Tooltip(
                                  message:
                                      tagsLoaded // Use 'message' parameter
                                          ? 'Add Tags'
                                          : 'Loading tags...',
                                  child: TextButton.icon(
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Add Tag'),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    // 'tooltip' parameter removed from TextButton.icon
                                    onPressed:
                                        tagsLoaded
                                            ? () => _openTagEditor(context)
                                            : null,
                                    // Style adjustments might be needed for disabled state
                                  ),
                                );
                                // *** END WRAP ***
                              }
                              // *** END CONDITIONAL BUTTON RENDERING ***
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // --- Waveform Display Section ---
                Container(
                  key: _waveformContainerKey, // Assign key
                  height: 120,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  // *** Wrap content in Stack for overlay ***
                  child: Stack(
                    clipBehavior:
                        Clip.none, // Allow overlay widgets to go outside bounds if needed
                    children: [
                      // Base Waveform Container (with GestureDetector)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceVariant.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: MouseRegion(
                              onHover:
                                  (event) => setState(
                                    () =>
                                        _hoverPositionForPainter =
                                            event.localPosition,
                                  ),
                              onExit:
                                  (event) => setState(
                                    () => _hoverPositionForPainter = null,
                                  ),
                              child: GestureDetector(
                                // This is the GestureDetector to modify
                                // --- onTapUp Handler ---
                                onTapUp: (details) {
                                  // Using onTapUp
                                  if (!canInteract)
                                    return; // Ensure player is ready

                                  final RenderBox? box =
                                      _waveformContainerKey.currentContext
                                              ?.findRenderObject()
                                          as RenderBox?;
                                  if (box == null || !box.hasSize) return;

                                  final localPosition = box.globalToLocal(
                                    details.globalPosition,
                                  );
                                  final size = box.size;
                                  final bloc =
                                      context
                                          .read<
                                            AudioPlayerBloc
                                          >(); // Get BLoC instance

                                  // --- Determine tapped marker and hit area ---
                                  TimeMarker? tappedMarker;
                                  bool hitPlayIcon = false;

                                  // Check markers in reverse draw order (top first)
                                  for (final marker in timeMarkers.reversed) {
                                    // Calculate the layout assuming the marker IS hovered to get hit areas
                                    // We need to call the static method from WaveformPainter
                                    final hoverLayout =
                                        WaveformPainter.calculateMarkerLayout(
                                          marker,
                                          size,
                                          true,
                                        );

                                    // Check if the tap position is within the combined hover area
                                    if (hoverLayout.fullHoverArea.contains(
                                      localPosition,
                                    )) {
                                      tappedMarker = marker;
                                      // If it's within the hover area, check if it specifically hit the play icon
                                      if (hoverLayout.playIconBounds.contains(
                                        localPosition,
                                      )) {
                                        hitPlayIcon = true;
                                      }
                                      // Found the marker being interacted with, no need to check others
                                      break;
                                    }
                                  }
                                  // --- End Determine tapped marker ---

                                  // --- Dispatch Action based on tap ---
                                  if (tappedMarker != null) {
                                    // A marker's interactive area was tapped
                                    final seekPosition =
                                        playerState.duration *
                                        tappedMarker.position;

                                    if (hitPlayIcon) {
                                      // Play Icon was clicked: Seek and Play
                                      print(
                                        "Tapped Play Icon for marker ${tappedMarker.label}",
                                      );
                                      bloc.add(
                                        SeekAudio(position: seekPosition),
                                      );
                                      // Ensure playback starts or resumes
                                      bloc.add(PlayAudio());
                                    } else {
                                      // Label/Bar area was clicked: Just Seek
                                      print(
                                        "Tapped Label/Bar for marker ${tappedMarker.label}",
                                      );
                                      bloc.add(
                                        SeekAudio(position: seekPosition),
                                      );
                                      // Optional: You could add PlayAudio() here too if you want clicking
                                      // the label to also resume playback if paused.
                                      // if (!playerState.isPlaying) {
                                      //   bloc.add(PlayAudio());
                                      // }
                                    }
                                  } else {
                                    // No marker area tapped - perform standard waveform seek
                                    final tapRatio = ((localPosition.dx - 16) /
                                            (size.width - 32))
                                        .clamp(0.0, 1.0);
                                    final seekPosition =
                                        playerState.duration * tapRatio;
                                    print(
                                      "Tapped waveform background, seeking to ratio $tapRatio",
                                    );
                                    bloc.add(SeekAudio(position: seekPosition));
                                  }

                                  // Optionally reset hover state visually after a click
                                  // if (mounted && _hoverPositionForPainter != null) {
                                  //   setState(() { _hoverPositionForPainter = null; });
                                  // }
                                }, // End onTapUp
                                // --- Drag Handling (remains the same) ---
                                onHorizontalDragStart: (details) {
                                  if (canInteract) {
                                    setState(
                                      () => _hoverPositionForPainter = null,
                                    ); // Hide hover on drag start
                                    // ... existing drag start logic ...
                                    final bloc =
                                        context.read<AudioPlayerBloc>();
                                    setState(() {
                                      _isDraggingWaveform = true;
                                      _wasPlayingBeforeDrag =
                                          playerState
                                              .isPlaying; // Use isPlaying from playerState
                                      _lastSeekDispatchTime = null;
                                      // ... calculation of _dragProgress, _finalDragRatio ...
                                      final RenderBox box =
                                          _waveformContainerKey.currentContext
                                                  ?.findRenderObject()
                                              as RenderBox;
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
                                            playerState
                                                        .duration
                                                        .inMilliseconds >
                                                    0
                                                ? (playerState
                                                            .position
                                                            .inMilliseconds /
                                                        playerState
                                                            .duration
                                                            .inMilliseconds)
                                                    .clamp(0.0, 1.0)
                                                : 0.0;
                                        _finalDragRatio = _dragProgress ?? 0.0;
                                      }
                                    });
                                    if (_wasPlayingBeforeDrag)
                                      bloc.add(PauseAudio());
                                  }
                                },
                                onHorizontalDragUpdate: (details) {
                                  if (_isDraggingWaveform && canInteract) {
                                    // ... existing drag update logic ...
                                    final RenderBox box =
                                        _waveformContainerKey.currentContext
                                                ?.findRenderObject()
                                            as RenderBox;
                                    final localPosition = box.globalToLocal(
                                      details.globalPosition,
                                    );
                                    final containerWidth = box.size.width;
                                    if (containerWidth > 0) {
                                      final seekRatio = (localPosition.dx /
                                              containerWidth)
                                          .clamp(0.0, 1.0);
                                      _finalDragRatio = seekRatio;
                                      // Optional: Throttle seek updates here if needed
                                      setState(() {
                                        _dragProgress = seekRatio;
                                      });
                                    }
                                  }
                                },
                                onHorizontalDragEnd: (details) {
                                  if (_isDraggingWaveform) {
                                    // ... existing drag end logic ...
                                    if (canInteract) {
                                      final finalSeekPosition =
                                          playerState.duration *
                                          _finalDragRatio;
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
                                // --- Child CustomPaint ---
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: WaveformPainter(
                                    waveformData: waveformData ?? [],
                                    activeColor:
                                        Theme.of(context).colorScheme.primary,
                                    inactiveColor: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withOpacity(0.5),
                                    playbackProgress:
                                        canInteract &&
                                                playerState
                                                        .duration
                                                        .inMilliseconds >
                                                    0
                                            ? (playerState
                                                        .position
                                                        .inMilliseconds /
                                                    playerState
                                                        .duration
                                                        .inMilliseconds)
                                                .clamp(0.0, 1.0)
                                            : 0.0,
                                    dragProgress: _dragProgress,
                                    markers: timeMarkers,
                                    hoverPosition:
                                        _hoverPositionForPainter, // Pass hover position
                                  ),
                                ),
                              ), // End GestureDetector
                            ), // End MouseRegion
                          ),
                        ),
                      ),
                      // Removed the explicit empty waveform check here as AudioService provides fallback
                      // (You might want to add back the loading indicator or placeholder if needed)
                      if (waveformData == null || waveformData.isEmpty)
                        Center(
                          child:
                              (track.sourceType ==
                                      TrackSource
                                          .youtube) // More robust check might be needed
                                  ? Container(
                                    // Your Placeholder Widget
                                    width: double.infinity,
                                    height: double.infinity, // Fill the area
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceVariant
                                          .withOpacity(0.2), // Example style
                                      // Or use an Icon, or a custom shape painter
                                    ),
                                    child: Icon(
                                      Icons
                                          .music_off_outlined, // Example placeholder icon
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withOpacity(0.5),
                                      size: 40,
                                    ),
                                  )
                                  : SizedBox(
                                    // Keep loading indicator for non-YouTube empty waveforms
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.0,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                        ),
                      // // Hover Overlay
                      // _buildHoverOverlay(playerState),
                    ],
                  ),
                ),
                // ),

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
                      ), // Current position from playerState
                      // >>> Use track.duration for total duration <<<
                      Text(
                        _formatDuration(
                          Duration(milliseconds: widget.track.duration),
                        ),
                      ),
                    ],
                  ),
                ),

                // --- Playback Controls (Use Centered Layout) ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    // Centered layout Row
                    children: [
                      const Spacer(flex: 1),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Previous IconButton
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
                          const SizedBox(width: 24),
                          // Play/Pause FloatingActionButton
                          FloatingActionButton(
                            tooltip: isPlaying ? 'Pause' : 'Play',
                            onPressed:
                                canInteract
                                    ? () {
                                      final bloc =
                                          context.read<AudioPlayerBloc>();
                                      if (isPlaying) {
                                        bloc.add(PauseAudio());
                                      } else {
                                        if (position >= duration &&
                                            duration > Duration.zero) {
                                          bloc.add(
                                            const SeekAudio(
                                              position: Duration.zero,
                                            ),
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
                          const SizedBox(width: 24),
                          // Next IconButton
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
                        ],
                      ),
                      const Spacer(flex: 1),
                      // Add Time Marker IconButton
                      IconButton(
                        icon: const Icon(Icons.bookmark_add_outlined),
                        tooltip: 'Add Time Marker at Current Position',
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
                                      // *** Set marking mode ***
                                      _isTimeMarkingMode = true;
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
                  // *** Use _isTimeMarkingMode ***
                  child:
                      _isTimeMarkingMode
                          ? Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  // *** Use _timeMarkerController ***
                                  controller: _timeMarkerController,
                                  decoration: const InputDecoration(
                                    // *** Updated hint text ***
                                    hintText: 'Enter marker name',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  autofocus: true,
                                  // *** Call _addMarkerAtCurrentTime ***
                                  onSubmitted:
                                      (_) =>
                                          _addMarkerAtCurrentTime(playerState),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                ),
                                tooltip: 'Save Marker',
                                // *** Call _addMarkerAtCurrentTime ***
                                onPressed:
                                    () => _addMarkerAtCurrentTime(playerState),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                ),
                                tooltip: 'Cancel Marker',
                                onPressed: () {
                                  setState(() {
                                    // *** Set marking mode ***
                                    _isTimeMarkingMode = false;
                                    _timeMarkerController.clear();
                                  });
                                },
                              ),
                            ],
                          )
                          : const SizedBox.shrink(), // Show nothing when not marking
                ),

                // --- Notes Section ---
                _buildNotesSection(),
              ], // End Column children
            ),
          ), // End Padding
        ); // End SingleChildScrollView
      }, // End BlocBuilder builder
    ); // End BlocBuilder
  } // End _buildExpandedPlayerUI

  // --- Helper Methods ---

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  // Add time tag at the current playback position
  void _addMarkerAtCurrentTime(AudioPlayerLoaded playerState) {
    // *** Use _timeMarkerController ***
    if (_timeMarkerController.text.isNotEmpty &&
        playerState.duration > Duration.zero) {
      final bloc = context.read<AudioPlayerBloc>();
      // Use the current position directly from the state
      final position = playerState.position;
      // Dispatch the renamed event
      bloc.add(
        AddTimeMarker(
          trackId: widget.track.id!,
          source: widget.track.path, // Use the current track's path/source ID
          // Calculate position fraction based on current position and duration
          position: (position.inMilliseconds /
                  playerState.duration.inMilliseconds)
              .clamp(0.0, 1.0),
          label: _timeMarkerController.text,
        ),
      );
      _timeMarkerController.clear();
      if (mounted) {
        setState(() {
          // *** Set marking mode ***
          _isTimeMarkingMode = false;
        });
      }
    } else if (_timeMarkerController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marker name cannot be empty.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot add marker: Audio duration not available.'),
          duration: Duration(seconds: 2),
        ),
      );
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
                        LoadAudio(track: widget.track),
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
