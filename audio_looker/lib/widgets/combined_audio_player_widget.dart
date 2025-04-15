// lib/widgets/combined_audio_player_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async'; // For Timer
import 'dart:math' as math; // For finding next/prev tag

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

  // Build the UI for the expanded player
  Widget _buildExpandedPlayerUI(AudioPlayerLoaded playerState, Track track) {
    final isPlaying = playerState.isPlaying;
    final duration = playerState.duration;
    final position = playerState.position;
    final waveformData = playerState.waveformData;
    final timeMarkers = playerState.markers;
    final bool canInteract = duration > Duration.zero;

    // **** WRAP the part needing TrackDataState with BlocBuilder ****
    return BlocBuilder<TrackDataBloc, TrackDataState>(
      builder: (context, trackDataState) {
        // --- Define currentGeneralTags INSIDE the builder scope ---
        List<String> currentGeneralTags = [];
        if (trackDataState is TrackDataLoaded) {
          try {
            // Find the most up-to-date track info from the state
            final currentTrackFromBloc = trackDataState.tracks.firstWhere(
              (t) => t.id == track.id,
              // Use the track passed to the widget as a fallback if not found (should be rare)
              orElse: () => track,
            );
            currentGeneralTags = currentTrackFromBloc.generalTags;
          } catch (e) {
            print("Error finding track in TrackDataBloc state: $e");
            currentGeneralTags =
                track.generalTags; // Fallback to widget's track data
          }
        } else {
          // If TrackDataBloc isn't loaded, use the tags from the track object passed to the widget
          currentGeneralTags = track.generalTags;
        }
        // --- End Define currentGeneralTags ---

        // Now return the UI that uses currentGeneralTags
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
                            _buildRatingBar(track.id!), // Pass track ID
                          ],
                        ),
                      ),
                      const SizedBox(width: 8), // Spacer
                      // Right Side: General Tags Section
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // **** Use the defined currentGeneralTags here ****
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
                                        // Simplified Chip for now
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
                          BlocBuilder<GlobalTagBloc, GlobalTagState>(
                            builder: (context, globalTagState) {
                              // Determine if the button should be enabled
                              final bool tagsLoaded =
                                  globalTagState is GlobalTagLoaded;

                              return IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                tooltip:
                                    tagsLoaded
                                        ? 'Edit General Tags'
                                        : 'Loading tags...', // Dynamic tooltip
                                // Disable onPressed if tags are not loaded
                                onPressed:
                                    tagsLoaded
                                        ? () => _openTagEditor(
                                          context,
                                        ) // Call helper method
                                        : null, // Button is disabled if null
                                // Optionally change icon color when disabled
                                color:
                                    tagsLoaded
                                        ? Theme.of(context).iconTheme.color
                                        : Colors.grey,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ), // End Header Padding
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
                                    final tapRatio = (localPosition.dx /
                                            size.width)
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
                      Text(_formatDuration(position)),
                      Text(_formatDuration(duration)),
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
                      // Add Time Tag IconButton
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

  void _handleHover(
    Offset localPosition,
    List<TimeMarker> markers,
    AudioPlayerLoaded playerState,
  ) {
    if (!mounted) return;

    // --- Find the hovered marker (existing logic) ---
    final RenderBox? box =
        _waveformContainerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final containerWidth = box.size.width;
    if (containerWidth <= 0) return;

    final double hoverX = localPosition.dx;
    const double hitTolerancePixels = 8.0; // Increased tolerance slightly

    TimeMarker? newlyHoveredMarker;
    for (final marker in markers) {
      final markerX = marker.position * containerWidth;
      if ((hoverX - markerX).abs() < hitTolerancePixels) {
        newlyHoveredMarker = marker;
        break;
      }
    }

    // --- MODIFIED LOGIC ---
    // Only update state IF a marker is actually hovered
    if (newlyHoveredMarker != null) {
      // _cancelHideOverlayTimer(); // Cancel timer if we hover over a marker
      // Update state only if the marker changed or position changed significantly
      if (_hoveredMarker != newlyHoveredMarker ||
          (_hoverPosition != null &&
              (localPosition - _hoverPosition!).distance > 2.0)) {
        setState(() {
          _hoveredMarker = newlyHoveredMarker;
          _hoverPosition = localPosition;
        });
      }
    }
    // *** DO NOT clear _hoveredMarker here if newlyHoveredMarker is null ***
    // The timer mechanism will handle clearing when the mouse leaves relevant areas.
    // --- END MODIFIED LOGIC ---
  }

  // void _handleHoverExit() {
  //   if (!mounted) return;
  //   _startHideOverlayTimer(); // Start timer when leaving waveform container
  // }

  // Widget _buildHoverOverlay(AudioPlayerLoaded playerState) {
  //   // if (_hoveredMarker == null || _hoverPosition == null) {
  //   return Positioned(
  //     left: 0,
  //     top: 0,
  //     child: Container(
  //       width: 0,
  //       height: 0,
  //       color: Colors.orange.withOpacity(0.5),
  //     ),
  //   );
  // }

  // final RenderBox? box =
  //     _waveformContainerKey.currentContext?.findRenderObject() as RenderBox?;
  // if (box == null || !box.hasSize) return const SizedBox.shrink();
  // final containerWidth = box.size.width;
  // final markerX = _hoveredMarker!.position * containerWidth;

  // // --- Configuration for the new overlay ---
  // final double overlayHeight = 30.0; // Adjust height as needed
  // final double playButtonWidth = 30.0;
  // final double barWidth = 3.0; // Width of the visual bar in the overlay
  // final double labelMinWidth = 60.0; // Minimum width for the label area
  // final double horizontalPadding = 6.0;
  // final double totalMinWidth =
  //     playButtonWidth +
  //     barWidth +
  //     labelMinWidth +
  //     (horizontalPadding * 2); // Rough estimate

  // // Positioning logic (center the overlay horizontally over the marker position)
  // double left = markerX - (totalMinWidth / 2);
  // // Clamp position to stay within visible waveform bounds
  // left = left.clamp(0, containerWidth - totalMinWidth);
  // // Position slightly above the waveform center or at the top
  // final double top = 5.0; // Position near the top, adjust as needed

  // return Positioned(
  //   left: left,
  //   top: top,
  //   // Width will adapt to content, but set minimum if needed
  //   // width: totalMinWidth, // Or let it size automatically
  //   height: overlayHeight,
  //   child: MouseRegion(
  //     // Keep mouse region to manage hover state via timer
  //     onEnter: (_) => _cancelHideOverlayTimer(),
  //     onExit: (_) => _startHideOverlayTimer(),
  //     cursor: SystemMouseCursors.click,
  //     child: Material(
  //       elevation: 4.0,
  //       borderRadius: BorderRadius.circular(6),
  //       color: Theme.of(
  //         context,
  //       ).colorScheme.secondaryContainer.withOpacity(0.95),
  //       child: GestureDetector(
  //         // Make the whole area clickable for seeking
  //         onTap: () {
  //           print("Tapped overlay for marker: ${_hoveredMarker!.label}");
  //           final seekPosition =
  //               playerState.duration * _hoveredMarker!.position;
  //           context.read<AudioPlayerBloc>().add(
  //             SeekAudio(position: seekPosition),
  //           );
  //           // Optionally play if paused or just seek
  //           if (!playerState.isPlaying) {
  //             context.read<AudioPlayerBloc>().add(PlayAudio());
  //           }
  //           // Hide overlay after interaction
  //           setState(() {
  //             _hoveredMarker = null;
  //             _hoverPosition = null;
  //           });
  //         },
  //         child: Container(
  //           // Container for padding
  //           padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
  //           height: overlayHeight,
  //           child: Row(
  //             mainAxisSize: MainAxisSize.min, // Keep row tight
  //             crossAxisAlignment: CrossAxisAlignment.center,
  //             children: [
  //               // 1. Play Button (Left)
  //               IconButton(
  //                 icon: Icon(
  //                   Icons.play_arrow, // Use play_arrow or play_circle_outline
  //                   color: Theme.of(context).colorScheme.onSecondaryContainer,
  //                 ),
  //                 iconSize: 18,
  //                 padding: EdgeInsets.zero,
  //                 constraints: const BoxConstraints(),
  //                 tooltip: 'Play from "${_hoveredMarker!.label}"',
  //                 onPressed: () {
  //                   // Play button specifically plays
  //                   print(
  //                     "Tapped play button for marker: ${_hoveredMarker!.label}",
  //                   );
  //                   final seekPosition =
  //                       playerState.duration * _hoveredMarker!.position;
  //                   context.read<AudioPlayerBloc>().add(
  //                     SeekAudio(position: seekPosition),
  //                   );
  //                   context.read<AudioPlayerBloc>().add(
  //                     PlayAudio(),
  //                   ); // Ensure it plays
  //                   // Hide overlay after interaction
  //                   setState(() {
  //                     _hoveredMarker = null;
  //                     _hoverPosition = null;
  //                   });
  //                 },
  //               ),
  //               const SizedBox(width: 4), // Spacer
  //               // 2. Visual Marker Bar (Middle)
  //               Container(
  //                 width: barWidth,
  //                 height:
  //                     overlayHeight *
  //                     0.6, // Make bar slightly shorter than overlay bg
  //                 decoration: BoxDecoration(
  //                   color:
  //                       Theme.of(
  //                         context,
  //                       ).colorScheme.primary, // Use a distinct color
  //                   borderRadius: BorderRadius.circular(barWidth / 2),
  //                 ),
  //               ),
  //               const SizedBox(width: 4), // Spacer
  //               // 3. Label (Right) - Expanded text
  //               Flexible(
  //                 // Use Flexible to allow text to take space
  //                 child: Container(
  //                   // Optional Container for label alignment/padding
  //                   constraints: BoxConstraints(
  //                     minWidth: labelMinWidth,
  //                   ), // Ensure minimum space for label
  //                   alignment: Alignment.centerLeft,
  //                   child: Text(
  //                     _hoveredMarker!.label, // Show full label on hover
  //                     style: TextStyle(
  //                       color:
  //                           Theme.of(
  //                             context,
  //                           ).colorScheme.onSecondaryContainer,
  //                       fontWeight: FontWeight.bold,
  //                       fontSize: 13,
  //                     ),
  //                     textAlign: TextAlign.left, // Align text to the left
  //                     overflow: TextOverflow.ellipsis,
  //                     maxLines: 1,
  //                   ),
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ),
  //     ),
  //   ),
  // );
  // }

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
