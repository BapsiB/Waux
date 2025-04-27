// lib/widgets/combined_audio_player_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async'; // For Timer

// Import BLoCs and Services/Models
import '../blocs/audio_player/audio_player_bloc.dart';
import '../blocs/track_management/track_data_bloc.dart';
import '../blocs/track_management/global_tag_bloc.dart';
import '../blocs/track_management/track_metadata_bloc.dart';
import '../services/collection_service.dart';
import '../services/audio_service.dart';
import '../widgets/tag_editor_popup.dart';

// Import UI components
import 'waveform_painter.dart';

class CombinedAudioPlayerWidget extends StatefulWidget {
  final Track track;
  final bool isMinimized;
  final VoidCallback onToggle;
  final VoidCallback? onPreviousPressed;
  final VoidCallback? onNextPressed;
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
  late AnimationController _animationController;
  late Animation<double> _playerHeightAnimation;
  double _currentVolume = 1.0;
  bool _isDraggingVolume = false;
  final double _minimizedPlayerHeight = 60.0;

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

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _playerHeightAnimation = Tween<double>(
      // Use the maxExpandedHeight passed in, ensuring a minimum reasonable height
      begin: widget.maxExpandedHeight.clamp(
        _minimizedPlayerHeight + 200,
        500.0,
      ),
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
    }
    _updateStateFromWidget(widget.track);
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

    // Recalculate expanded height if maxExpandedHeight changes
    if (widget.maxExpandedHeight != oldWidget.maxExpandedHeight) {
      // Update animation tween based on the new max height
      _playerHeightAnimation = Tween<double>(
        begin: widget.maxExpandedHeight.clamp(
          _minimizedPlayerHeight + 200,
          500.0,
        ),
        end: _minimizedPlayerHeight,
      ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
      );
      // Consider if the animation value needs reset based on isMinimized
      // _animationController.value = widget.isMinimized ? 1.0 : 0.0;
    }

    if (oldWidget.track.id != widget.track.id) {
      _updateStateFromWidget(widget.track);
      _isDraggingWaveform = false;
      _dragProgress = null;
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
      final playerState = context.read<AudioPlayerBloc>().state;
      if (playerState is AudioPlayerLoaded && !_isDraggingVolume) {
        if (_currentVolume != playerState.volume) {
          if (mounted) {
            setState(() {
              _currentVolume = playerState.volume;
            });
          } else {
            _currentVolume = playerState.volume;
          }
        }
      }
    }
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

  void _updateStateFromWidget(Track track) {
    if (!mounted) return;
    _currentRating = track.rating;
    if (_notesController.text != track.comment) {
      _notesController.text = track.comment;
    }
    _isTimeMarkingMode = false;
    _timeMarkerController.clear();
  }

  @override
  void dispose() {
    _hideOverlayTimer?.cancel();
    _animationController.dispose();
    _notesController.dispose();
    _timeMarkerController.dispose();
    super.dispose();
  }

  // Minimized player controls build method (remains the same)
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
    final bool canInteract = duration > Duration.zero;

    return Container(
      height: _minimizedPlayerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
      ),
      child: Row(
        children: [
          // Controls (Left)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                iconSize: 28,
                color:
                    widget.onPreviousPressed != null
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).disabledColor,
                onPressed: widget.onPreviousPressed,
                tooltip: 'Previous Track',
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  size: 32,
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
              IconButton(
                icon: const Icon(Icons.skip_next),
                iconSize: 28,
                color:
                    widget.onNextPressed != null
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).disabledColor,
                onPressed: widget.onNextPressed,
                tooltip: 'Next Track',
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  playerState.isShuffleActive
                      ? Icons.shuffle_on_outlined
                      : Icons.shuffle,
                ),
                iconSize: 18,
                color:
                    playerState.isShuffleActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                tooltip:
                    playerState.isShuffleActive
                        ? 'Disable Shuffle'
                        : 'Enable Shuffle',
                onPressed: () {
                  context.read<AudioPlayerBloc>().add(ToggleShuffle());
                },
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Track Info & Progress (Center)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${track.title} - ${track.artist}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 12, // Slightly smaller font
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2), // Reduced space
                Row(
                  children: [
                    Text(
                      _formatDuration(
                        _isDraggingMinimizedBar
                            ? (duration * _minimizedDragRatio)
                            : position,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10, // Smaller font
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: GestureDetector(
                        key: _minimizedProgressBarKey,
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          if (!canInteract) return;
                          final seekRatio = _calculateMinimizedSeekRatio(
                            details.globalPosition,
                          );
                          if (seekRatio != null) {
                            final bloc = context.read<AudioPlayerBloc>();
                            final seekPosition = duration * seekRatio;
                            bloc.add(SeekAudio(position: seekPosition));
                            // Ensure playback resumes or starts if paused
                            if (!isPlaying) {
                              bloc.add(PlayAudio());
                            }
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
                            });
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
                            context.read<AudioPlayerBloc>().add(
                              SeekAudio(position: duration * seekRatio),
                            );
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          if (!_isDraggingMinimizedBar || !canInteract) return;
                          setState(() {
                            _isDraggingMinimizedBar = false;
                          });
                          // Ensure playback resumes or starts if paused
                          final bloc = context.read<AudioPlayerBloc>();
                          if (!isPlaying) {
                            bloc.add(PlayAudio());
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: SizedBox(
                            height: 4, // Thinner progress bar
                            child: LinearProgressIndicator(
                              value: displayProgress,
                              minHeight: 4, // Match SizedBox height
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDuration(duration),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10, // Smaller font
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Volume Slider (Right)
          SizedBox(
            width: 90, // Slightly narrower slider
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.0,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 5.0,
                ), // Smaller thumb
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 10.0,
                ), // Smaller overlay
              ),
              child: Slider(
                value: _currentVolume,
                min: 0.0,
                max: 1.0,
                onChangeStart: (value) {
                  if (mounted)
                    setState(() => _isDraggingVolume = true);
                  else
                    _isDraggingVolume = true;
                },
                onChanged: (value) {
                  if (mounted) {
                    setState(() => _currentVolume = value);
                    context.read<AudioPlayerBloc>().add(SetVolume(value));
                  }
                },
                onChangeEnd: (value) {
                  if (mounted)
                    setState(() => _isDraggingVolume = false);
                  else
                    _isDraggingVolume = false;
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              widget.isMinimized
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_up,
              size: 20,
            ),
            tooltip: widget.isMinimized ? 'Expand Player' : 'Collapse Player',
            onPressed: widget.onToggle,
          ),
        ],
      ),
    );
  }

  void _openTagEditor(BuildContext buildContext) {
    final trackDataBloc = BlocProvider.of<TrackDataBloc>(buildContext);
    final globalTagBloc = BlocProvider.of<GlobalTagBloc>(buildContext);
    final trackMetadataBloc = BlocProvider.of<TrackMetadataBloc>(buildContext);
    final trackDataState = trackDataBloc.state;
    final globalTagState = globalTagBloc.state;

    if (trackDataState is TrackDataLoaded &&
        globalTagState is GlobalTagLoaded) {
      List<String> currentTrackTags = [];
      try {
        final currentTrackFromBloc = trackDataState.tracks.firstWhere(
          (t) => t.id == widget.track.id,
          orElse: () => widget.track,
        );
        currentTrackTags = currentTrackFromBloc.generalTags;
      } catch (e) {
        print('Error finding track ${widget.track.id} for tag editor: $e');
        currentTrackTags = widget.track.generalTags;
      }
      showDialog(
        context: buildContext,
        builder:
            (dialogContext) => MultiBlocProvider(
              providers: [
                BlocProvider.value(value: globalTagBloc),
                BlocProvider.value(value: trackMetadataBloc),
              ],
              child: TagEditorPopup(
                trackId: widget.track.id!,
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

  Widget _buildExpandedPlayerUI(AudioPlayerLoaded playerState, Track track) {
    final isPlaying = playerState.isPlaying;
    final duration = playerState.duration;
    final position = playerState.position;
    final waveformData = playerState.waveformData;
    final timeMarkers = playerState.markers;
    final bool canInteract = duration > Duration.zero;

    return BlocBuilder<TrackDataBloc, TrackDataState>(
      builder: (context, trackDataState) {
        // ... (tag loading logic remains the same) ...
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
                // --- Row 1: Title ---
                Text(
                  track.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: 18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6), // Space after title
                // --- Row 2: Artist, Waveform, Add Tag ---
                ConstrainedBox(
                  // Constrain the height of the waveform row
                  constraints: const BoxConstraints(
                    minHeight: 45,
                    maxHeight: 55,
                  ), // Adjust max height
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.center, // Center items vertically
                    children: [
                      // Artist (Left) - Give it some space but not expand fully
                      SizedBox(
                        width:
                            MediaQuery.of(context).size.width *
                            0.25, // Example width constraint
                        child: Text(
                          track.artist,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12), // Spacer
                      // Waveform + Time Indicators (Middle - Expands)
                      Expanded(
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center, // Center vertically
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Waveform Container
                            SizedBox(
                              key: _waveformContainerKey,
                              height: 35, // Reduced height for waveform in row
                              child: Stack(
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
                                            // Waveform interaction logic (Keep existing logic)
                                            onTapUp: (details) {
                                              /* ... existing seek/play logic ... */
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
                                              /* ... existing drag start logic ... */
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
                                              /* ... existing drag update logic ... */
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
                                              /* ... existing drag end logic ... */
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
                                  // Placeholder/Loading Indicator for Waveform (Keep existing logic)
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
                            // Time Indicators (conditionally shown below waveform)
                            if (canInteract) // Only show if duration is known
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 2.0,
                                ), // Space between waveform and time
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
                                          milliseconds: widget.track.duration,
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
                      // Add Tag Button (Right)
                      BlocBuilder<GlobalTagBloc, GlobalTagState>(
                        builder: (context, globalTagState) {
                          final bool tagsLoaded =
                              globalTagState is GlobalTagLoaded;
                          return Tooltip(
                            message:
                                tagsLoaded
                                    ? 'Add/Edit Tags'
                                    : 'Loading tags...',
                            child: IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              iconSize: 20,
                              onPressed:
                                  tagsLoaded
                                      ? () => _openTagEditor(context)
                                      : null,
                              color:
                                  tagsLoaded
                                      ? Theme.of(context).iconTheme.color
                                      : Colors.grey,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ), // End ConstrainedBox for Row 2
                // --- End Row 2 ---

                // --- Row 3: Rating (Aligned Left) ---
                Padding(
                  padding: const EdgeInsets.only(
                    top: 4.0,
                  ), // Space above rating
                  child: Align(
                    alignment: Alignment.centerLeft, // Align rating to the left
                    child: _buildRatingBar(
                      track.id!,
                    ), // Use the rating bar widget
                  ),
                ),
                const SizedBox(height: 10), // Space after rating
                // --- Playback Controls (Centered) ---
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Previous Button
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        iconSize: 30,
                        tooltip: 'Previous Track',
                        color:
                            widget.onPreviousPressed != null
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).disabledColor,
                        onPressed: widget.onPreviousPressed,
                      ),
                      const SizedBox(width: 16),
                      // Play/Pause Button
                      FloatingActionButton.small(
                        tooltip: isPlaying ? 'Pause' : 'Play',
                        onPressed:
                            canInteract
                                ? () {
                                  /* Play/Pause Logic */
                                  final bloc = context.read<AudioPlayerBloc>();
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
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Next Button
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        iconSize: 30,
                        tooltip: 'Next Track',
                        color:
                            widget.onNextPressed != null
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).disabledColor,
                        onPressed: widget.onNextPressed,
                      ),
                      // Spacer, Marker Button, Collapse Button (Keep existing logic)
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.bookmark_add_outlined),
                        tooltip: 'Add Time Marker',
                        iconSize: 24,
                        color:
                            canInteract
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).disabledColor,
                        onPressed:
                            canInteract
                                ? () {
                                  if (mounted) {
                                    setState(() {
                                      _isTimeMarkingMode = true;
                                    });
                                  }
                                }
                                : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up),
                        tooltip: 'Collapse Player',
                        iconSize: 24,
                        color: Theme.of(context).colorScheme.secondary,
                        onPressed: widget.onToggle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // --- Time Tag Input Row ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                _buildNotesSection(), // Keep existing notes section
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Build Rating Bar (adjusted size) ---
  Widget _buildRatingBar(int trackId) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (index) {
          final ratingValue = index + 1;
          return IconButton(
            iconSize: 20, // Smaller stars
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      child: ExpansionTile(
        key: ValueKey('notes_expansion_${widget.track.id}'),
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
                  UpdateTrackComment(widget.track.id!, _notesController.text),
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
    if (_timeMarkerController.text.isNotEmpty &&
        playerState.duration > Duration.zero) {
      final bloc = context.read<AudioPlayerBloc>();
      final position = playerState.position;
      bloc.add(
        AddTimeMarker(
          trackId: widget.track.id!,
          source: widget.track.path,
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
    return BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
      builder: (context, playerState) {
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

        if (isLoadingThisTrack) {
          return Container(
            height: _minimizedPlayerHeight,
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
        } else if (isErrorForThisTrack) {
          return Container(
            height: _minimizedPlayerHeight,
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
        } else if (isCorrectTrackLoaded) {
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
                clipBehavior: Clip.hardEdge,
                child: child,
              );
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: 1.0 - _animationController.value,
                    duration: const Duration(milliseconds: 150),
                    child: IgnorePointer(
                      ignoring: widget.isMinimized,
                      // Pass the player state down
                      child: _buildExpandedPlayerUI(playerState, widget.track),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _animationController.value,
                    duration: const Duration(milliseconds: 150),
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
          );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }
}
