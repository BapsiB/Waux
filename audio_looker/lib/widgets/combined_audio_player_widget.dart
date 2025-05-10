// lib/widgets/combined_audio_player_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async'; // For Timer
import 'package:just_audio/just_audio.dart';
import '../blocs/audio_player/audio_player_bloc.dart';
import '../blocs/collection_management/collection_management_bloc.dart';
import '../screens/collection_manager_screen.dart';
import '../blocs/track_management/track_data_bloc.dart';
import '../blocs/track_management/global_tag_bloc.dart';
import '../blocs/track_management/track_metadata_bloc.dart';
import '../services/collection_service.dart';
import '../services/audio_service.dart';
import '../widgets/tag_editor_popup.dart';

// Import UI components
import 'waveform_painter.dart';

class CombinedAudioPlayerWidget extends StatefulWidget {
  // final Track? track;
  final bool isMinimized;
  final VoidCallback onToggle;
  final VoidCallback? onPreviousPressed;
  final VoidCallback? onNextPressed;
  // final double maxExpandedHeight;
  final String? activeCollectionName;

  const CombinedAudioPlayerWidget({
    Key? key,
    // required this.track,
    required this.isMinimized,
    required this.onToggle,
    this.onPreviousPressed,
    this.onNextPressed,
    // this.maxExpandedHeight = 100.0,
    this.activeCollectionName,
  }) : super(key: key);

  @override
  State<CombinedAudioPlayerWidget> createState() =>
      _CombinedAudioPlayerWidgetState();
}

class _CombinedAudioPlayerWidgetState extends State<CombinedAudioPlayerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _playerHeightAnimation;
  double _currentVolume = 1.0;
  bool _isDraggingVolume = false;
  final double _minimizedPlayerHeight = 60.0;
  final double _maximalPlayerHeight = 170.0;

  final TextEditingController _notesController = TextEditingController();
  bool _isNoteExpanded = false;
  int _currentRating = 0;
  bool _isTimeMarkingMode = false;
  Timer? _hideOverlayTimer;
  Offset? _hoverPositionForPainter;
  bool _isDraggingWaveform = false;
  double? _dragProgress;
  bool _wasPlayingBeforeDrag = false;
  double _finalDragRatio = 0.0;
  DateTime? _lastSeekDispatchTime;
  final Duration _seekThrottleInterval = const Duration(milliseconds: 100);
  TimeMarker? _hoveredMarker;
  Offset? _hoverPosition;
  final GlobalKey _waveformContainerKey = GlobalKey();
  final GlobalKey _minimizedProgressBarKey = GlobalKey();
  bool _isDraggingMinimizedBar = false;
  double _minimizedDragRatio = 0.0;
  final TextEditingController _timeMarkerController = TextEditingController();

  Track? _currentTrackForDisplay;
  String? _currentSourcePathForDisplay;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _playerHeightAnimation = Tween<double>(
      begin: _maximalPlayerHeight,
      end: _minimizedPlayerHeight,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    )..addListener(() {
      if (mounted) setState(() {});
    });
    _animationController.value = widget.isMinimized ? 1.0 : 0.0;

    final initialPlayerState = context.read<AudioPlayerBloc>().state;
    if (initialPlayerState is AudioPlayerLoaded) {
      _currentVolume = initialPlayerState.volume;
      // Initial attempt to find track data on init
      _currentTrackForDisplay = _findTrackByPath(
        initialPlayerState.currentSource,
      );
      _currentSourcePathForDisplay = initialPlayerState.currentSource;
      _updateLocalStateFromTrack(_currentTrackForDisplay);
    }
  }

  @override
  void didUpdateWidget(CombinedAudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isMinimized != oldWidget.isMinimized) {
      if (widget.isMinimized) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
    // No longer need to check trackForDisplay changes
  }

  double? _calculateMinimizedSeekRatio(Offset globalPosition) {
    final RenderBox? box =
        _minimizedProgressBarKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (box != null && box.hasSize) {
      final localPosition = box.globalToLocal(globalPosition);
      final progressBarWidth = box.size.width;
      if (progressBarWidth > 0) {
        return (localPosition.dx / progressBarWidth).clamp(0.0, 1.0);
      }
    }
    return null;
  }

  void _updateLocalStateFromTrack(Track? track) {
    if (!mounted) return;
    if (track == null) {
      // Reset local state if no track is displayed
      _currentRating = 0;
      if (_notesController.text.isNotEmpty) _notesController.clear();
      _isTimeMarkingMode = false;
      if (_timeMarkerController.text.isNotEmpty) _timeMarkerController.clear();
    } else {
      // Update local state from the found track
      if (_currentRating != track.rating) _currentRating = track.rating;
      if (_notesController.text != track.comment)
        _notesController.text = track.comment;
      _isTimeMarkingMode = false; // Reset marker mode on track change
      if (_timeMarkerController.text.isNotEmpty) _timeMarkerController.clear();
    }
    // No setState needed here as this is usually called within the build or initState/didChangeDependencies context
  }

  @override
  void dispose() {
    _hideOverlayTimer?.cancel();
    _animationController.dispose();
    _notesController.dispose();
    _timeMarkerController.dispose();
    super.dispose();
  }

  Track? _findTrackByPath(String path) {
    final trackDataState = context.read<TrackDataBloc>().state;
    List<Track> sourceList = [];

    // Consolidate getting tracks from various states where they might exist
    if (trackDataState is TrackDataLoaded) {
      sourceList = trackDataState.tracks;
    } else if (trackDataState is TrackDataLoading &&
        trackDataState.previousTracks != null) {
      sourceList = trackDataState.previousTracks!;
    } else if (trackDataState is TrackDataProcessingNeeded) {
      // Added state
      sourceList = trackDataState.tracks;
    } else if (trackDataState is TrackDataDeletingFolder &&
        trackDataState.previousTracks != null) {
      // Added state
      sourceList = trackDataState.previousTracks!;
    }
    // Add other relevant states if they hold track data

    if (sourceList.isEmpty) {
      print(
        "CombinedAudioPlayerWidget: Track list is empty in TrackDataBloc state.",
      );
      return null;
    }

    try {
      // Find track by path matching the player's currentSource
      return sourceList.firstWhere((t) => t.path == path);
    } catch (e) {
      print(
        "CombinedAudioPlayerWidget: Could not find track with path '$path' in TrackDataBloc state.",
      );
      return null; // Not found
    }
  }

  Widget _buildMinimizedLoadingIndicator(Track? trackBeingLoaded) {
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      height: _minimizedPlayerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _buildHomeButton(context), // Keep home button consistent
          const SizedBox(width: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              trackBeingLoaded?.title ?? "Loading...",
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: inactiveColor),
            ),
          ),
          const Spacer(), // Push toggle button to the right
          _buildToggleButton(context), // Keep toggle button consistent
        ],
      ),
    );
  }

  Widget _buildMinimizedPlayerContent(
    AudioPlayerState playerState,
    Track? trackForDisplay,
  ) {
    if (playerState is AudioPlayerLoaded && trackForDisplay != null) {
      // Pass the loaded state AND the found track data
      return _buildMinimizedPlayerControls(playerState, trackForDisplay);
    } else if (playerState is AudioPlayerLoading) {
      // Pass the track being loaded (if found) to the loading indicator
      return _buildMinimizedLoadingIndicator(trackForDisplay);
    } else {
      // Handle Initial, Error, or Loaded state where track data wasn't found
      return _buildMinimizedPlayerContentEmpty();
    }
  }

  Widget _buildMinimizedPlayerControls(
    AudioPlayerLoaded playerState,
    Track trackForDisplay,
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

    final bool canInteract = duration > Duration.zero;
    final controlsEnabled = canInteract; // Use this for enabling controls
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;

    // --- Use LayoutBuilder to get width ---

    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalWidth = constraints.maxWidth;

        const double homeButtonWidth =
            50.0; // Adjusted width for icon button + padding
        const double playerControlsWidth = 150.0;
        final double timelineWidth = totalWidth * 0.25;
        final double timelineStart = (totalWidth - timelineWidth) / 2;
        final double spaceForPlayerControls = timelineStart - homeButtonWidth;

        // Ensure space is not negative if layout is too tight

        final double playerControlsStart =
            homeButtonWidth +
            (spaceForPlayerControls > playerControlsWidth
                ? (spaceForPlayerControls - playerControlsWidth) / 2
                : 0); // Center if space allows, else align left after home btn

        // Calculate width for the right-side buttons (approximate)

        const double rightButtonsWidth =
            120.0; // Sum of Vol + Tag + Toggle + padding

        return Container(
          height: _minimizedPlayerHeight,

          padding: const EdgeInsets.symmetric(
            horizontal: 8.0,
          ), // Overall horizontal padding

          decoration: BoxDecoration(
            /* ... border/color ... */
            color: Theme.of(context).colorScheme.surface.withOpacity(0.95),

            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor,

                width: 0.5,
              ),
            ),
          ),

          // --- Use Stack for positioned layout ---
          child: Stack(
            alignment: Alignment.center, // Base alignment

            children: [
              // --- Positioned Home Button ---
              Positioned(
                left: 0, // Align to far left of padding

                top: 0,

                bottom: 0,

                width: homeButtonWidth,

                child: Center(
                  child: _buildHomeButton(context),
                ), // Center within its space
              ),

              // --- Positioned Player Controls ---
              Positioned(
                left: playerControlsStart,

                top: 0,

                bottom: 0,

                width: playerControlsWidth,

                child: _buildPlayerControls(
                  context,

                  playerState,

                  controlsEnabled,
                ),
              ),

              // --- Positioned Timeline ---
              Positioned(
                left: timelineStart,

                width: timelineWidth,

                top: 0,

                bottom: 0,

                child: Column(
                  // Keep the column for progress + time
                  mainAxisAlignment: MainAxisAlignment.center,

                  children: [
                    GestureDetector(
                      // Keep GestureDetector and its contents
                      key: _minimizedProgressBarKey,

                      behavior: HitTestBehavior.opaque,

                      onTapDown: (details) {
                        /* ... seek logic ... */

                        if (!canInteract) return;

                        final seekRatio = _calculateMinimizedSeekRatio(
                          details.globalPosition,
                        );

                        if (seekRatio != null) {
                          final bloc = context.read<AudioPlayerBloc>();

                          final seekPosition = duration * seekRatio;

                          bloc.add(SeekAudio(position: seekPosition));

                          if (!isPlaying) {
                            bloc.add(PlayAudio());
                          }
                        }
                      },

                      onHorizontalDragStart: (details) {
                        /* ... drag start logic ... */

                        if (!canInteract) return;

                        final seekRatio = _calculateMinimizedSeekRatio(
                          details.globalPosition,
                        );

                        if (seekRatio != null) {
                          setState(() {
                            _isDraggingMinimizedBar = true;

                            _minimizedDragRatio = seekRatio;
                          });
                        }
                      },

                      onHorizontalDragUpdate: (details) {
                        /* ... drag update logic ... */

                        if (!_isDraggingMinimizedBar || !canInteract) return;

                        final seekRatio = _calculateMinimizedSeekRatio(
                          details.globalPosition,
                        );

                        if (seekRatio != null) {
                          setState(() {
                            _minimizedDragRatio = seekRatio;
                          });

                          context.read<AudioPlayerBloc>().add(
                            SeekAudio(position: duration * seekRatio),
                          );
                        }
                      },

                      onHorizontalDragEnd: (details) {
                        /* ... drag end logic ... */

                        if (!_isDraggingMinimizedBar || !canInteract) return;

                        setState(() {
                          _isDraggingMinimizedBar = false;
                        });

                        final bloc = context.read<AudioPlayerBloc>();

                        if (!isPlaying) {
                          bloc.add(PlayAudio());
                        }
                      },

                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),

                        child: Column(
                          mainAxisSize: MainAxisSize.min,

                          children: [
                            SizedBox(
                              height: 4,

                              child: LinearProgressIndicator(
                                value: displayProgress,

                                backgroundColor: inactiveColor.withOpacity(0.1),

                                valueColor: AlwaysStoppedAnimation<Color>(
                                  activeColor,
                                ),

                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),

                            const SizedBox(height: 4),

                            Row(
                              // Time indicators
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,

                              children: [
                                Text(
                                  _formatDuration(
                                    _isDraggingMinimizedBar
                                        ? (duration * _minimizedDragRatio)
                                        : position,
                                  ),

                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(
                                    fontSize: 10,

                                    color: inactiveColor,
                                  ),
                                ),

                                Text(
                                  _formatDuration(duration),

                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(
                                    fontSize: 10,

                                    color: inactiveColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // --- Positioned Right-Side Buttons ---
              Positioned(
                right: 0, // Align to far right of padding

                top: 0,

                bottom: 0,

                // width: rightButtonsWidth, // Optional: Set width
                child: Row(
                  // Keep these buttons together
                  mainAxisSize: MainAxisSize.min, // Take only needed space

                  children: [
                    _buildVolumeButton(context),

                    const SizedBox(width: 0), // Adjust spacing

                    _buildToggleButton(context),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMinimizedPlayerContentEmpty() {
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final collectionName = widget.activeCollectionName ?? "No Collection";

    return Container(
      height: _minimizedPlayerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // --- Home Button (Left) ---
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(child: _buildHomeButton(context)),
          ),

          // --- Collection Name (Center) ---
          // Listen to CollectionManagementBloc for the name
          BlocBuilder<CollectionManagementBloc, CollectionManagementState>(
            builder: (context, colState) {
              String nameToShow = "No Active Collection";
              if (colState is CollectionManagementLoaded) {
                nameToShow =
                    colState.activeCollectionDefinition?.name ?? nameToShow;
              } else if (colState is CollectionManagementLoading) {
                nameToShow =
                    colState.activeCollectionDefinition?.name ?? "Loading...";
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                  ), // Avoid overlap
                  child: Text(
                    nameToShow,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: inactiveColor,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),

          // --- Toggle Button (Right) ---
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(child: _buildToggleButton(context)),
          ),
        ],
      ),
    );
  }

  // Helper function for the Home Button
  Widget _buildHomeButton(BuildContext context) {
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      icon: const Icon(Icons.home),
      iconSize: 22,
      tooltip: 'Manage Collections',
      color: inactiveColor,
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CollectionManagerScreen(),
          ),
        );
      },
    );
  }

  Widget _buildPlayerControls(
    BuildContext context,
    AudioPlayerLoaded playerState,
    bool controlsEnabled,
  ) {
    final isPlaying = playerState.isPlaying;
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final disabledColor = Theme.of(context).disabledColor;

    return SizedBox(
      width: 150, // Fixed width
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous Button
          IconButton(
            icon: const Icon(Icons.skip_previous),
            iconSize: 28,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color:
                widget.onPreviousPressed != null
                    ? inactiveColor
                    : disabledColor,
            tooltip: 'Previous Track',
            onPressed: widget.onPreviousPressed,
          ),
          // Play/Pause Button
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              size: 32,
              color: controlsEnabled ? activeColor : disabledColor,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: isPlaying ? 'Pause' : 'Play',
            onPressed:
                controlsEnabled
                    ? () {
                      final bloc = context.read<AudioPlayerBloc>();
                      final position =
                          playerState.position; // Get position here
                      final duration =
                          playerState.duration; // Get duration here
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
          ),
          // Next Button
          IconButton(
            icon: const Icon(Icons.skip_next),
            iconSize: 28,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: widget.onNextPressed != null ? inactiveColor : disabledColor,
            tooltip: 'Next Track',
            onPressed: widget.onNextPressed,
          ),
          // Shuffle Button
          IconButton(
            icon: Icon(
              playerState.isShuffleActive
                  ? Icons.shuffle_on_outlined
                  : Icons.shuffle,
            ),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: playerState.isShuffleActive ? activeColor : inactiveColor,
            tooltip:
                playerState.isShuffleActive
                    ? 'Disable Shuffle'
                    : 'Enable Shuffle',
            onPressed:
                () => context.read<AudioPlayerBloc>().add(ToggleShuffle()),
          ),
        ],
      ),
    );
  }

  // Helper function for the Volume Button
  Widget _buildVolumeButton(BuildContext context) {
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final activeColor =
        Theme.of(context).colorScheme.primary; // For slider active color

    return Row(
      mainAxisSize: MainAxisSize.min, // Take only needed horizontal space
      children: [
        // Volume Off Icon
        Icon(
          Icons.volume_mute_outlined, // Or Icons.volume_off
          size: 16,
          color: inactiveColor,
        ),
        const SizedBox(width: 4), // Small space
        // Fixed Width Container for Slider
        SizedBox(
          width: 100, // Fixed width for the slider
          child: SliderTheme(
            // Customize slider appearance
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.0, // Make track thinner
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 6.0,
              ), // Smaller knob
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 12.0,
              ), // Smaller overlay
              activeTrackColor: activeColor.withOpacity(0.8),
              inactiveTrackColor: inactiveColor.withOpacity(0.2),
              thumbColor: activeColor,
            ),
            child: Slider(
              value: _currentVolume,
              min: 0.0,
              max: 1.0,
              onChangeStart: (value) {
                // Use mounted check only within setState
                _isDraggingVolume = true;
                if (mounted) setState(() {});
              },
              onChanged: (value) {
                _currentVolume =
                    value; // Update local state immediately for visuals
                context.read<AudioPlayerBloc>().add(
                  SetVolume(value),
                ); // Dispatch event
                if (mounted) setState(() {}); // Trigger rebuild
              },
              onChangeEnd: (value) {
                _isDraggingVolume = false;
                if (mounted) setState(() {});
                // Optional: Debounce saving the final value if needed elsewhere
              },
            ),
          ),
        ),
        const SizedBox(width: 4), // Small space
        // Volume On Icon
        Icon(
          Icons.volume_up_outlined, // Or Icons.volume_up
          size: 16,
          color: inactiveColor,
        ),
      ],
    );
  }

  Widget _buildAddTagButton(BuildContext context) {
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final disabledColor = Theme.of(context).disabledColor;
    return BlocBuilder<GlobalTagBloc, GlobalTagState>(
      builder: (context, globalTagState) {
        final bool tagsLoaded = globalTagState is GlobalTagLoaded;
        return IconButton(
          icon: const Icon(
            Icons.sell_outlined,
          ), // Alternative icon: local_offer
          iconSize: 18,
          tooltip: tagsLoaded ? 'Add/Edit Tags' : 'Loading tags...',
          color: tagsLoaded ? inactiveColor : disabledColor,
          onPressed: tagsLoaded ? () => _openTagEditor(context) : null,
        );
      },
    );
  }

  // Helper function for the Toggle Button
  Widget _buildToggleButton(BuildContext context) {
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      icon: Icon(
        widget.isMinimized
            ? Icons.keyboard_arrow_down
            : Icons.keyboard_arrow_up,
        size: 24,
      ),
      color: inactiveColor,
      tooltip: widget.isMinimized ? 'Expand Player' : 'Collapse Player',
      onPressed: widget.onToggle,
    );
  }

  void _openTagEditor(BuildContext buildContext) {
    final currentTrack = _currentTrackForDisplay; // Use the state variable
    if (currentTrack == null || currentTrack.id == null) {
      ScaffoldMessenger.of(buildContext).showSnackBar(
        const SnackBar(content: Text('No track loaded to edit tags for.')),
      );
      return;
    }

    final trackDataBloc = BlocProvider.of<TrackDataBloc>(buildContext);
    final globalTagBloc = BlocProvider.of<GlobalTagBloc>(buildContext);
    final trackMetadataBloc = BlocProvider.of<TrackMetadataBloc>(buildContext);
    final trackDataState = trackDataBloc.state;
    final globalTagState = globalTagBloc.state;

    if (trackDataState is TrackDataLoaded &&
        globalTagState is GlobalTagLoaded) {
      final currentTrackTags = currentTrack.generalTags;
      showDialog(
        context: buildContext,
        builder:
            (dialogContext) => MultiBlocProvider(
              providers: [
                BlocProvider.value(value: globalTagBloc),
                BlocProvider.value(value: trackMetadataBloc),
              ],
              child: TagEditorPopup(
                trackId: currentTrack.id!, // Use ID from the displayed track
                currentTrackTags: currentTrackTags,
              ),
            ),
      );
    } else {
      String message = 'Cannot edit tags: ';
      if (trackDataState is! TrackDataLoaded)
        message += 'Track data not loaded. ';
      if (globalTagState is! GlobalTagLoaded)
        message += 'Global tags not loaded.';
      ScaffoldMessenger.of(
        buildContext,
      ).showSnackBar(SnackBar(content: Text(message)));
      if (globalTagState is! GlobalTagLoaded)
        globalTagBloc.add(LoadGlobalTags());
    }
  }

  // Build method for the expanded player UI (Modified Layout)
  Widget _buildExpandedPlayerUI(
    AudioPlayerLoaded playerState,
    Track trackForDisplay,
  ) {
    final Track? track = trackForDisplay;

    if (track == null) {
      // Should ideally not be called if track is null, but handle defensively
      return const Center(child: Text("No track selected."));
    }

    // State variables remain the same
    final isPlaying = playerState.isPlaying;
    final duration = playerState.duration;
    final position = playerState.position;
    final waveformData = playerState.waveformData;
    final timeMarkers = playerState.markers;
    final bool canInteract = duration > Duration.zero;
    final controlsEnabled = canInteract; // Use this for enabling controls

    // Theme colors
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final disabledColor = Theme.of(context).disabledColor;

    return BlocBuilder<TrackDataBloc, TrackDataState>(
      builder: (context, trackDataState) {
        // ... Tag loading logic ...
        List<String> currentGeneralTags = [];
        if (trackDataState is TrackDataLoaded) {
          try {
            final currentTrackFromBloc = trackDataState.tracks.firstWhere(
              (t) => t.id == track.id,
              orElse: () => track,
            );
            currentGeneralTags = currentTrackFromBloc.generalTags;
          } catch (e) {
            currentGeneralTags = track.generalTags;
          }
        } else {
          currentGeneralTags = track.generalTags;
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.center, // Vertically align items
                  children: [
                    // Wrap Title and Rating in Expanded to push button to the right
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        // Prevent title pushing rating too far if very long
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Use Flexible for the Text to allow shrinking/ellipsis
                          Flexible(
                            child: Text(
                              '${track.title} - ${track.artist}',
                              style: Theme.of(
                                context,
                              ).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Rating bar - Removed Align wrapper as Row's crossAxisAlignment handles it
                          _buildRatingBar(track.id!),
                        ],
                      ),
                    ),
                    // const Spacer(), // Alternative: use Spacer instead of Expanded wrapper above

                    // --- MOVED TOGGLE BUTTON HERE ---
                    _buildToggleButton(context),
                  ],
                ),

                const SizedBox(height: 10),

                // --- Main Interactive Row ---
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 65,
                    maxHeight: 100,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // --- Call Helper Functions ---
                      // _buildHomeButton(context),
                      // const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center, // Adjust alignment
                        crossAxisAlignment:
                            CrossAxisAlignment.start, // Adjust alignment
                        children: [
                          _buildPlayerControls(
                            // Playback controls on top
                            context,
                            playerState,
                            controlsEnabled,
                          ),
                          const SizedBox(height: 8), // Add spacing
                          _buildVolumeButton(context), // Volume button below
                        ],
                      ),
                      const SizedBox(width: 12),

                      // --- Waveform (Specific to expanded view) ---
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              // Waveform container
                              key: _waveformContainerKey,
                              height: 80,
                              child: Stack(
                                // Keep Stack and its contents
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceVariant
                                            .withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: MouseRegion(
                                          onHover:
                                              (event) => setState(
                                                () =>
                                                    _hoverPositionForPainter =
                                                        event.localPosition,
                                              ),
                                          onExit:
                                              (event) => setState(
                                                () =>
                                                    _hoverPositionForPainter =
                                                        null,
                                              ),
                                          child: GestureDetector(
                                            onTapUp: (details) {
                                              /* ... seek/play logic ... */
                                              if (!canInteract) return;
                                              final RenderBox? box =
                                                  _waveformContainerKey
                                                          .currentContext
                                                          ?.findRenderObject()
                                                      as RenderBox?;
                                              if (box == null || !box.hasSize)
                                                return;
                                              final localPosition = box
                                                  .globalToLocal(
                                                    details.globalPosition,
                                                  );
                                              final size = box.size;
                                              final bloc =
                                                  context
                                                      .read<AudioPlayerBloc>();
                                              TimeMarker? tappedMarker;
                                              bool hitPlayIcon = false;
                                              for (final marker
                                                  in timeMarkers.reversed) {
                                                final hoverLayout =
                                                    WaveformPainter.calculateMarkerLayout(
                                                      marker,
                                                      size,
                                                      true,
                                                    );
                                                if (hoverLayout.fullHoverArea
                                                    .contains(localPosition)) {
                                                  tappedMarker = marker;
                                                  if (hoverLayout.playIconBounds
                                                      .contains(
                                                        localPosition,
                                                      )) {
                                                    hitPlayIcon = true;
                                                  }
                                                  break;
                                                }
                                              }
                                              if (tappedMarker != null) {
                                                final seekPosition =
                                                    playerState.duration *
                                                    tappedMarker.position;
                                                bloc.add(
                                                  SeekAudio(
                                                    position: seekPosition,
                                                  ),
                                                );
                                                if (hitPlayIcon ||
                                                    !playerState.isPlaying) {
                                                  bloc.add(PlayAudio());
                                                }
                                              } else {
                                                final tapRatio =
                                                    ((localPosition.dx - 0) /
                                                            (size.width - 0))
                                                        .clamp(0.0, 1.0);
                                                final seekPosition =
                                                    playerState.duration *
                                                    tapRatio;
                                                bloc.add(
                                                  SeekAudio(
                                                    position: seekPosition,
                                                  ),
                                                );
                                                if (!playerState.isPlaying) {
                                                  bloc.add(PlayAudio());
                                                }
                                              }
                                            },
                                            onHorizontalDragStart: (details) {
                                              /* ... drag start logic ... */
                                              if (canInteract) {
                                                final bloc =
                                                    context
                                                        .read<
                                                          AudioPlayerBloc
                                                        >();
                                                setState(() {
                                                  _hoverPositionForPainter =
                                                      null;
                                                  _isDraggingWaveform = true;
                                                  _wasPlayingBeforeDrag =
                                                      playerState.isPlaying;
                                                  _lastSeekDispatchTime = null;
                                                  final RenderBox box =
                                                      _waveformContainerKey
                                                              .currentContext
                                                              ?.findRenderObject()
                                                          as RenderBox;
                                                  final localPosition = box
                                                      .globalToLocal(
                                                        details.globalPosition,
                                                      );
                                                  final containerWidth =
                                                      box.size.width;
                                                  if (containerWidth > 0) {
                                                    _finalDragRatio =
                                                        (localPosition.dx /
                                                                containerWidth)
                                                            .clamp(0.0, 1.0);
                                                    _dragProgress =
                                                        _finalDragRatio;
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
                                                    _finalDragRatio =
                                                        _dragProgress ?? 0.0;
                                                  }
                                                });
                                                if (_wasPlayingBeforeDrag)
                                                  bloc.add(PauseAudio());
                                              }
                                            },
                                            onHorizontalDragUpdate: (details) {
                                              /* ... drag update logic ... */
                                              if (_isDraggingWaveform &&
                                                  canInteract) {
                                                final RenderBox box =
                                                    _waveformContainerKey
                                                            .currentContext
                                                            ?.findRenderObject()
                                                        as RenderBox;
                                                final localPosition = box
                                                    .globalToLocal(
                                                      details.globalPosition,
                                                    );
                                                final containerWidth =
                                                    box.size.width;
                                                if (containerWidth > 0) {
                                                  final seekRatio =
                                                      (localPosition.dx /
                                                              containerWidth)
                                                          .clamp(0.0, 1.0);
                                                  _finalDragRatio = seekRatio;
                                                  final now = DateTime.now();
                                                  bool shouldDispatch =
                                                      _lastSeekDispatchTime ==
                                                          null ||
                                                      now.difference(
                                                            _lastSeekDispatchTime!,
                                                          ) >
                                                          _seekThrottleInterval;
                                                  if (shouldDispatch) {
                                                    final seekPosition =
                                                        playerState.duration *
                                                        seekRatio;
                                                    context
                                                        .read<AudioPlayerBloc>()
                                                        .add(
                                                          SeekAudio(
                                                            position:
                                                                seekPosition,
                                                          ),
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
                                              /* ... drag end logic ... */
                                              if (_isDraggingWaveform) {
                                                if (canInteract) {
                                                  final finalSeekPosition =
                                                      playerState.duration *
                                                      _finalDragRatio;
                                                  context
                                                      .read<AudioPlayerBloc>()
                                                      .add(
                                                        SeekAudio(
                                                          position:
                                                              finalSeekPosition,
                                                        ),
                                                      );
                                                }
                                                setState(() {
                                                  _isDraggingWaveform = false;
                                                  _dragProgress = null;
                                                  _lastSeekDispatchTime = null;
                                                });
                                                if (_wasPlayingBeforeDrag) {
                                                  Future.delayed(
                                                    const Duration(
                                                      milliseconds: 50,
                                                    ),
                                                    () {
                                                      if (mounted)
                                                        context
                                                            .read<
                                                              AudioPlayerBloc
                                                            >()
                                                            .add(PlayAudio());
                                                    },
                                                  );
                                                }
                                              }
                                            },
                                            child: CustomPaint(
                                              size: Size.infinite,
                                              painter: WaveformPainter(
                                                waveformData:
                                                    waveformData ?? [],
                                                activeColor:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
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
                                                    _hoverPositionForPainter,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (waveformData == null ||
                                      waveformData.isEmpty)
                                    Center(
                                      child:
                                          (track.sourceType ==
                                                  TrackSource.youtube)
                                              ? Container(
                                                width: double.infinity,
                                                height: double.infinity,
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceVariant
                                                      .withOpacity(0.2),
                                                ),
                                                child: Icon(
                                                  Icons.music_off_outlined,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                      .withOpacity(0.5),
                                                  size: 25,
                                                ),
                                              )
                                              : SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.0,
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                    ),
                                              ),
                                    ),
                                ],
                              ),
                            ),
                            if (canInteract) // Time Indicators
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    Text(
                                      _formatDuration(
                                        Duration(
                                          milliseconds:
                                              trackForDisplay!.duration,
                                        ),
                                      ),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12), // Spacer
                      // --- Call Helper Functions ---
                      // _buildVolumeButton(context),
                      // const SizedBox(width: 4),
                      _buildAddTagButton(context),
                    ],
                  ),
                ), // End ConstrainedBox for Main Row

                const SizedBox(width: 4),

                // --- Marker Button (Specific to expanded) ---
                // Row(
                //   mainAxisAlignment: MainAxisAlignment.end,
                //   children: [
                //     IconButton(
                //       icon: const Icon(Icons.bookmark_add_outlined),
                //       tooltip: 'Add Time Marker',
                //       iconSize: 24,
                //       color:
                //           canInteract
                //               ? Theme.of(context).colorScheme.secondary
                //               : disabledColor,
                //       onPressed:
                //           canInteract
                //               ? () {
                //                 if (mounted) {
                //                   setState(() {
                //                     _isTimeMarkingMode = true;
                //                   });
                //                 }
                //               }
                //               : null,
                //     ),
                //   ],
                // ),

                // --- Time Tag Input Row ---
                Padding(
                  /* ... Time marker input section ... */
                  padding: const EdgeInsets.symmetric(horizontal: 0.0),
                  child:
                      _isTimeMarkingMode
                          ? Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _timeMarkerController,
                                  decoration: const InputDecoration(
                                    hintText: 'Enter marker name',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  autofocus: true,
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
                                    _isTimeMarkingMode = false;
                                    _timeMarkerController.clear();
                                  });
                                },
                              ),
                            ],
                          )
                          : const SizedBox.shrink(),
                ),

                // --- Notes Section ---
                // _buildNotesSection(), // Keep existing notes section
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Build Rating Bar (adjusted size) ---
  Widget _buildRatingBar(int trackId) {
    if (_currentTrackForDisplay == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (index) {
          final ratingValue = index + 1;
          return IconButton(
            iconSize: 15, // Smaller stars
            padding: const EdgeInsets.symmetric(
              horizontal: 1,
            ), // Tighter padding
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact, // Make it more compact
            tooltip: '$ratingValue star${ratingValue > 1 ? 's' : ''}',
            icon: Icon(
              index < _currentRating ? Icons.star : Icons.star_border,
              color:
                  index < _currentRating
                      ? Colors.amber
                      : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              setState(() {
                _currentRating = ratingValue;
              });
              context.read<TrackMetadataBloc>().add(
                UpdateTrackRating(trackId, ratingValue),
              );
            },
          );
        }),
      ],
    );
  }

  // --- Build Notes Section (remains the same) ---
  Widget _buildNotesSection() {
    if (_currentTrackForDisplay == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      child: ExpansionTile(
        key: ValueKey('notes_expansion_${_currentTrackForDisplay!.id}'),
        initiallyExpanded: _isNoteExpanded,
        onExpansionChanged: (expanded) {
          if (mounted) {
            setState(() {
              _isNoteExpanded = expanded;
            });
          }
        },
        title: const Text(
          'Notes / Comments',
          style: TextStyle(fontSize: 14),
        ), // Slightly smaller title
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 0,
        ), // Adjust padding
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: _notesController,
            maxLines: 3, // Limit lines
            decoration: const InputDecoration(
              hintText: 'Add notes...',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13), // Smaller text
            onEditingComplete: () {
              if (mounted) {
                context.read<TrackMetadataBloc>().add(
                  UpdateTrackComment(
                    _currentTrackForDisplay!.id!,
                    _notesController.text,
                  ),
                );
                FocusScope.of(context).unfocus();
              }
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  void _addMarkerAtCurrentTime(AudioPlayerLoaded playerState) {
    if (_currentTrackForDisplay == null) return;
    if (_timeMarkerController.text.isNotEmpty &&
        playerState.duration > Duration.zero) {
      final bloc = context.read<AudioPlayerBloc>();
      final position = playerState.position;
      bloc.add(
        AddTimeMarker(
          trackId: _currentTrackForDisplay!.id!,
          source: _currentTrackForDisplay!.path,
          position: (position.inMilliseconds /
                  playerState.duration.inMilliseconds)
              .clamp(0.0, 1.0),
          label: _timeMarkerController.text,
        ),
      );
      _timeMarkerController.clear();
      if (mounted) {
        setState(() {
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

  // Main build method
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AudioPlayerBloc, AudioPlayerState>(
      // Use BlocConsumer
      listener: (context, playerState) {
        // Listen for changes in the loaded source and update local state if necessary
        if (playerState is AudioPlayerLoaded) {
          if (playerState.currentSource != _currentSourcePathForDisplay) {
            print(
              "Player source changed to: ${playerState.currentSource}. Finding new track data.",
            );
            final newTrack = _findTrackByPath(playerState.currentSource);
            setState(() {
              // Update state variables based on the new track
              _currentTrackForDisplay = newTrack;
              _currentSourcePathForDisplay = playerState.currentSource;
              _updateLocalStateFromTrack(newTrack);
              // Reset drag states when track changes
              _isDraggingWaveform = false;
              _dragProgress = null;
              _isDraggingVolume = false;
              _isDraggingMinimizedBar = false;
            });
          } else if (_currentTrackForDisplay == null) {
            // Case: Player loaded but we previously couldn't find the track data. Try again.
            final track = _findTrackByPath(playerState.currentSource);
            if (track != null) {
              setState(() {
                _currentTrackForDisplay = track;
                _updateLocalStateFromTrack(track);
              });
            }
          }
          // Update volume if it changed in the state and we aren't dragging
          if (!_isDraggingVolume && _currentVolume != playerState.volume) {
            setState(() {
              _currentVolume = playerState.volume;
            });
          }
        } else if (playerState is! AudioPlayerLoading) {
          // If state is Initial or Error, clear the displayed track
          if (_currentSourcePathForDisplay != null) {
            setState(() {
              _currentTrackForDisplay = null;
              _currentSourcePathForDisplay = null;
              _updateLocalStateFromTrack(null);
              // Reset drag states
              _isDraggingWaveform = false;
              _dragProgress = null;
              _isDraggingVolume = false;
              _isDraggingMinimizedBar = false;
            });
          }
        }
        // Also listen for metadata updates affecting the *currently displayed* track
        // (This requires listening to TrackMetadataBloc as well, potentially outside this builder)
      },
      builder: (context, playerState) {
        // Use the state variable _currentTrackForDisplay which is updated by the listener
        final trackForDisplay = _currentTrackForDisplay;
        bool showPlayer =
            trackForDisplay != null && playerState is AudioPlayerLoaded;
        bool isLoading = playerState is AudioPlayerLoading;
        String? loadingTitle;
        if (isLoading && playerState.loadingSource != null) {
          // Attempt to show title while loading
          final loadingTrack = _findTrackByPath(playerState.loadingSource!);
          loadingTitle = loadingTrack?.title ?? "Loading...";
        }

        // Build the player UI structure (AnimatedBuilder, Stack, etc.)
        return AnimatedBuilder(
          animation: _playerHeightAnimation,
          builder: (context, child) {
            return Container(
              height: _playerHeightAnimation.value,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: const Offset(0, -2),
                  ),
                ],
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 0.5,
                  ),
                ),
              ),
              clipBehavior: Clip.hardEdge, // Use Clip.hardEdge
              child: child,
            );
          },
          child: Stack(
            children: [
              // --- Expanded View ---
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity:
                      (!widget.isMinimized && showPlayer && !isLoading)
                          ? 1.0
                          : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: IgnorePointer(
                    ignoring: widget.isMinimized || !showPlayer || isLoading,
                    child:
                        (showPlayer && playerState is AudioPlayerLoaded)
                            ? _buildExpandedPlayerUI(
                              playerState,
                              trackForDisplay,
                            ) // Pass non-null track
                            : const SizedBox.shrink(),
                  ),
                ),
              ),

              // --- Minimized View ---
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity:
                      _animationController
                          .value, // Controlled by minimize toggle
                  duration: const Duration(milliseconds: 150),
                  child: IgnorePointer(
                    ignoring: !widget.isMinimized,
                    // Pass the actual player state and track data found
                    child: _buildMinimizedPlayerContent(
                      playerState,
                      _currentTrackForDisplay,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
