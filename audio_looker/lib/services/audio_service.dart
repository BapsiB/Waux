import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:just_audio/just_audio.dart' as just_audio show PlayerState;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class AudioTag {
  final double position;
  final String label;

  AudioTag({required this.position, required this.label});

  Map<String, dynamic> toJson() {
    return {'position': position, 'label': label};
  }

  factory AudioTag.fromJson(Map<String, dynamic> json) {
    return AudioTag(position: json['position'], label: json['label']);
  }
}

class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Playback properties
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  Stream<just_audio.PlayerState> get playerStateStream =>
      _audioPlayer.playerStateStream;

  // Waveform data
  List<double>? _waveformData;
  List<double>? get waveformData => _waveformData;

  // Tags
  final Map<String, List<AudioTag>> _audioTags = {};

  // Event controller for waveform data
  final _waveformController = StreamController<List<double>>.broadcast();
  Stream<List<double>> get waveformStream => _waveformController.stream;

  Future<void> initialize() async {
    try {
      // Initialize audio player with any default settings
      await _audioPlayer.setVolume(1.0);
    } catch (e) {
      print('Error initializing audio player: $e');
      // Continue even if there's an error, as some methods might still work
    }
  }

  Future<void> loadAudio(String source, {bool isUrl = false}) async {
    try {
      print(
        '🔍 AudioService: Starting to load audio from: $source, isUrl: $isUrl',
      );

      if (isUrl) {
        // For network URLs
        try {
          print('🔍 AudioService: Setting URL in player');
          await _audioPlayer.setUrl(source);
          print('✅ AudioService: Successfully set URL in player');
        } catch (e) {
          print('❌ AudioService: Error setting URL: $e');
          // Continue with waveform extraction even if playback fails
        }

        print('🔍 AudioService: Extracting waveform from URL');
        await _extractWaveformFromUrl(source);
        print('✅ AudioService: Completed URL waveform extraction');
      } else {
        // For local files
        try {
          print('🔍 AudioService: Setting file path in player: $source');
          await _audioPlayer.setFilePath(source);
          print('✅ AudioService: Successfully set file path in player');
        } catch (e) {
          print('❌ AudioService: Error setting file path: $e');
          // Continue with waveform extraction even if playback fails
        }

        print('🔍 AudioService: Extracting waveform from file');
        await _extractWaveformFromFile(source);
        print('✅ AudioService: Completed file waveform extraction');
      }

      print('✅ AudioService: Successfully completed loadAudio');
    } catch (e) {
      print('❌ AudioService: Error in loadAudio: $e');

      // Generate a random waveform as fallback
      print('🔍 AudioService: Generating random waveform as fallback');
      _generateRandomWaveform();
      if (_waveformData != null) {
        print('🔍 AudioService: Adding random waveform data to stream');
        _waveformController.add(_waveformData!);
        print('✅ AudioService: Successfully added random waveform to stream');
      }
    }
  }

  Future<void> _extractWaveformFromFile(String filePath) async {
    print('🔍 AudioService: Starting waveform extraction from file: $filePath');
    final tempDir = await getTemporaryDirectory();
    final outputFile = '${tempDir.path}/waveform_data.txt';
    print('🔍 AudioService: Output file path: $outputFile');

    // Use FFmpeg Kit to extract audio data for waveform
    print('🔍 AudioService: Running FFmpeg command');

    // Modify the FFmpeg command to add -y flag which forces overwrite
    final session = await FFmpegKit.execute(
      '-y -i "$filePath" -ac 1 -filter:a aresample=8000 -map 0:a -c:a pcm_s16le -f data "$outputFile"',
    );

    final returnCode = await session.getReturnCode();
    print(
      '🔍 AudioService: FFmpeg return code: ${returnCode?.getValue() ?? "unknown"}',
    );

    if (ReturnCode.isSuccess(returnCode)) {
      print('✅ AudioService: FFmpeg succeeded, processing waveform data');
      await _processWaveformData(outputFile);
      print('✅ AudioService: Completed processing waveform data');
    } else {
      print(
        '❌ AudioService: FFmpeg failed with return code: ${returnCode?.getValue() ?? "unknown"}',
      );

      // Get logs for debugging
      final logs = await session.getLogs();
      for (final log in logs) {
        print('❌ AudioService FFmpeg log: ${log.getMessage()}');
      }

      // Use fallback method
      print('🔍 AudioService: Using random waveform fallback');
      _generateRandomWaveform();
      if (_waveformData != null) {
        print('🔍 AudioService: Adding random waveform data to stream');
        _waveformController.add(_waveformData!);
        print('✅ AudioService: Successfully added random waveform to stream');
      }
    }
  }

  Future<void> _extractWaveformFromUrl(String url) async {
    try {
      // Download the file
      final response = await http.get(Uri.parse(url));
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_audio');
      await tempFile.writeAsBytes(response.bodyBytes);

      // Now extract waveform from the downloaded file
      await _extractWaveformFromFile(tempFile.path);
    } catch (e) {
      print('Error extracting waveform from URL: $e');

      // Use fallback method
      _generateRandomWaveform();
      if (_waveformData != null) {
        _waveformController.add(_waveformData!);
      }
    }
  }

  Future<void> _processWaveformData(String dataFilePath) async {
    try {
      print(
        '🔍 AudioService: Starting to process waveform data from: $dataFilePath',
      );
      final file = File(dataFilePath);
      if (!await file.exists()) {
        print('❌ AudioService: Waveform data file not found at: $dataFilePath');
        throw Exception('Waveform data file not found');
      }

      final bytes = await file.readAsBytes();
      print(
        '🔍 AudioService: Read ${bytes.length} bytes from waveform data file',
      );

      // Convert bytes to audio samples (16-bit PCM)
      List<double> samples = [];
      for (int i = 0; i < bytes.length; i += 2) {
        if (i + 1 < bytes.length) {
          // Combine bytes to form 16-bit sample
          int sample = bytes[i] + (bytes[i + 1] << 8);
          // Convert to signed value
          if (sample > 32767) sample -= 65536;
          // Normalize to -1.0 to 1.0
          samples.add(sample / 32768.0);
        }
      }

      print('Converted to ${samples.length} audio samples');

      // Downsample for display (reduce to ~1000-2000 points for efficiency)
      const int targetLength = 1500;
      if (samples.length > targetLength) {
        final skipFactor = samples.length ~/ targetLength;
        List<double> downsampled = [];

        for (int i = 0; i < samples.length; i += skipFactor) {
          // Find peak in this segment
          double maxAmp = 0;
          for (int j = i; j < i + skipFactor && j < samples.length; j++) {
            final amp = samples[j].abs();
            if (amp > maxAmp) maxAmp = amp;
          }
          downsampled.add(maxAmp);
        }

        _waveformData = downsampled;
      } else {
        // Convert to amplitude
        _waveformData = samples.map((s) => s.abs()).toList();
      }

      print('Final waveform has ${_waveformData?.length ?? 0} data points');

      // Generate random waveform if data is empty or invalid
      if (_waveformData == null || _waveformData!.isEmpty) {
        print('Generated data was empty, using random fallback');
        _generateRandomWaveform();
      }

      // Notify listeners
      _waveformController.add(_waveformData!);
      // Notify listeners
      print('🔍 AudioService: Adding processed waveform data to stream');
      _waveformController.add(_waveformData!);
      print('✅ AudioService: Successfully added waveform data to stream');
    } catch (e) {
      print('❌ AudioService: Error processing waveform data: $e');

      // Fallback to a random waveform on error
      print(
        '🔍 AudioService: Using random waveform fallback after processing error',
      );
      _generateRandomWaveform();

      // Notify listeners even on error
      if (_waveformData != null) {
        print('🔍 AudioService: Adding fallback waveform data to stream');
        _waveformController.add(_waveformData!);
        print('✅ AudioService: Successfully added fallback waveform to stream');
      }
    }
  }

  void _generateRandomWaveform() {
    print('🔍 AudioService: Generating random waveform data');
    _waveformData = List.generate(
      100,
      (index) => (0.3 + 0.7 * (index % 10) / 10),
    );
    print(
      '✅ AudioService: Generated ${_waveformData?.length ?? 0} random data points',
    );
  }

  // Playback controls
  Future<void> play() async {
    try {
      await _audioPlayer.play();
    } catch (e) {
      print('Error playing audio: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      print('Error pausing audio: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      print('Error stopping audio: $e');
    }
  }

  Future<void> seekTo(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      print('Error seeking audio: $e');
    }
  }

  // Tag management
  void addTag(String audioSource, double position, String label) {
    if (!_audioTags.containsKey(audioSource)) {
      _audioTags[audioSource] = [];
    }

    final tag = AudioTag(position: position, label: label);
    _audioTags[audioSource]!.add(tag);

    // Sort tags by position
    _audioTags[audioSource]!.sort((a, b) => a.position.compareTo(b.position));
  }

  List<AudioTag> getTagsForAudio(String audioSource) {
    return _audioTags[audioSource] ?? [];
  }

  Future<void> dispose() async {
    await _audioPlayer.dispose();
    await _waveformController.close();
  }
}
