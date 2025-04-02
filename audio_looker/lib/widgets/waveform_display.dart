import 'package:flutter/material.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/services/audio_service.dart';
import 'package:audio_looker/widgets/waveform_painter.dart';

class WaveformDisplay extends StatefulWidget {
  final Track track;
  final AudioService audioService;
  final Function(double, String)? onTagAdded;

  const WaveformDisplay({
    Key? key,
    required this.track,
    required this.audioService,
    this.onTagAdded,
  }) : super(key: key);

  @override
  _WaveformDisplayState createState() => _WaveformDisplayState();
}

class _WaveformDisplayState extends State<WaveformDisplay> {
  Duration? _currentPosition;
  Duration? _totalDuration;
  List<AudioTag> _timeTags = [];
  TextEditingController _tagController = TextEditingController();
  bool _isTagging = false;
  double? _tagPosition;

  @override
  void initState() {
    super.initState();
    _loadAudio();
    _setupListeners();
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _loadAudio() async {
    // Load audio with saved waveform data if available
    await widget.audioService.loadAudio(
      widget.track.path,
      isUrl: widget.track.isUrl,
      // savedWaveformData: widget.track.waveformData,
    );
  }

  void _setupListeners() {
    // Listen for position changes
    widget.audioService.positionStream.listen((position) {
      setState(() {
        _currentPosition = position;
      });
    });

    // Listen for duration changes
    widget.audioService.durationStream.listen((duration) {
      setState(() {
        _totalDuration = duration;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Waveform Display
        GestureDetector(
          onTapDown: (details) => _handleTapOnWaveform(details),
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildWaveform(),
          ),
        ),

        const SizedBox(height: 8),

        // Time display
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatDuration(_currentPosition ?? Duration.zero)),
            Text(_formatDuration(_totalDuration ?? Duration.zero)),
          ],
        ),

        const SizedBox(height: 16),

        // Playback controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.replay_10),
              onPressed: () {
                if (_currentPosition != null) {
                  final newPosition = Duration(
                    milliseconds: (_currentPosition!.inMilliseconds - 10000)
                        .clamp(0, _totalDuration?.inMilliseconds ?? 0),
                  );
                  widget.audioService.seekTo(newPosition);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 48),
              onPressed: () => widget.audioService.play(),
            ),
            IconButton(
              icon: const Icon(Icons.pause, size: 48),
              onPressed: () => widget.audioService.pause(),
            ),
            IconButton(
              icon: const Icon(Icons.stop, size: 48),
              onPressed: () => widget.audioService.stop(),
            ),
            IconButton(
              icon: const Icon(Icons.forward_10),
              onPressed: () {
                if (_currentPosition != null && _totalDuration != null) {
                  final newPosition = Duration(
                    milliseconds: (_currentPosition!.inMilliseconds + 10000)
                        .clamp(0, _totalDuration!.inMilliseconds),
                  );
                  widget.audioService.seekTo(newPosition);
                }
              },
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Display time tags
        if (_timeTags.isNotEmpty) ...[
          Text('Time Tags:', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Column(
            children:
                _timeTags.map((tag) {
                  return ListTile(
                    dense: true,
                    title: Text(tag.label),
                    subtitle: Text(
                      _formatDuration(
                        Duration(
                          milliseconds:
                              (tag.position *
                                      (_totalDuration?.inMilliseconds ?? 0))
                                  .toInt(),
                        ),
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_circle_outline),
                      onPressed: () {
                        // Jump to tag position
                        final position = Duration(
                          milliseconds:
                              (tag.position *
                                      (_totalDuration?.inMilliseconds ?? 0))
                                  .toInt(),
                        );
                        widget.audioService.seekTo(position);
                      },
                    ),
                  );
                }).toList(),
          ),
        ],

        // Tag input (shows when tagging)
        if (_isTagging) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Tag Label',
                    hintText: 'Enter tag description',
                  ),
                  autofocus: true,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _saveTag, child: const Text('Save')),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isTagging = false;
                    _tagPosition = null;
                  });
                  _tagController.clear();
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildWaveform() {
    final waveformData =
        widget.audioService.waveformData ?? widget.track.waveformData;

    if (waveformData == null || waveformData.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blueGrey),
      );
    }

    return CustomPaint(
      painter: WaveformPainter(
        waveformData: waveformData,
        playbackProgress: _calculatePlaybackProgress(),
        tagPosition: _tagPosition,
        tags: _timeTags,
      ),
      size: Size.infinite,
    );
  }

  double _calculatePlaybackProgress() {
    if (_currentPosition == null ||
        _totalDuration == null ||
        _totalDuration!.inMilliseconds == 0) {
      return 0.0;
    }
    return _currentPosition!.inMilliseconds / _totalDuration!.inMilliseconds;
  }

  void _handleTapOnWaveform(TapDownDetails details) {
    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(details.globalPosition);
    final relativeX = localPos.dx / renderBox.size.width;

    // Clamp value between 0.0 and 1.0
    final position = relativeX.clamp(0.0, 1.0);

    // If we're in tagging mode, set the tag position
    if (_isTagging) {
      setState(() {
        _tagPosition = position;
      });
    } else {
      // Otherwise, seek to the position
      if (_totalDuration != null) {
        final seekPosition = Duration(
          milliseconds: (position * _totalDuration!.inMilliseconds).toInt(),
        );
        widget.audioService.seekTo(seekPosition);
      }

      // Show tag input option
      _showTagOption(position);
    }
  }

  void _showTagOption(double position) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Play from here'),
                onTap: () {
                  Navigator.pop(context);
                  if (_totalDuration != null) {
                    final seekPosition = Duration(
                      milliseconds:
                          (position * _totalDuration!.inMilliseconds).toInt(),
                    );
                    widget.audioService.seekTo(seekPosition);
                    widget.audioService.play();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_add),
                title: const Text('Add time tag'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _isTagging = true;
                    _tagPosition = position;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _saveTag() {
    if (_tagPosition != null && _tagController.text.isNotEmpty) {
      final newTag = AudioTag(
        position: _tagPosition!,
        label: _tagController.text,
      );

      setState(() {
        _timeTags.add(newTag);
        _timeTags.sort((a, b) => a.position.compareTo(b.position));
        _isTagging = false;
        _tagPosition = null;
      });

      // Call onTagAdded callback
      if (widget.onTagAdded != null) {
        widget.onTagAdded!(_tagPosition!, _tagController.text);
      }

      // Add to audio service
      widget.audioService.addTag(
        widget.track.path,
        _tagPosition!,
        _tagController.text,
      );

      _tagController.clear();
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
