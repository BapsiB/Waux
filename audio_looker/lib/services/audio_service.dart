import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:just_audio/just_audio.dart' as just_audio show PlayerState;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For JSON encoding/decoding
import 'package:audio_looker/services/performance_profiler.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as pathLib;

class TimeMarker {
  final double position;
  final String label;

  TimeMarker({required this.position, required this.label});

  Map<String, dynamic> toJson() {
    return {'position': position, 'label': label};
  }

  factory TimeMarker.fromJson(Map<String, dynamic> json) {
    return TimeMarker(position: json['position'], label: json['label']);
  }
}

class AudioService {
  final _yt = YoutubeExplode();

  static const String _shufflePrefKey = 'shuffle_active';

  static final AudioService _instance =
      AudioService._internal(); // Private static instance

  factory AudioService() {
    // Public factory constructor
    return _instance;
  }

  AudioService._internal() {
    // Private named constructor
    // Initialization logic that should run only once can go here
    // Note: initialize() method still needs to be called externally if
    // it contains async operations or needs to be controlled timing-wise.
    print("AudioService Singleton instance created.");
  }

  final AudioPlayer _audioPlayer = AudioPlayer();

  // Playback properties
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  Stream<just_audio.PlayerState> get playerStateStream =>
      _audioPlayer.playerStateStream;

  // Waveform data
  List<double>? _waveformData;
  List<double>? get waveformData => _waveformData;

  // Cache for waveform data
  final Map<String, List<double>> _waveformCache = {};

  // Tags
  // *** Renamed _tagsBySource to _markersBySource and use TimeMarker ***
  final Map<String, List<TimeMarker>> _markersBySource = {};

  // Event controller for waveform data
  final _waveformController = StreamController<List<double>>.broadcast();
  Stream<List<double>> get waveformStream => _waveformController.stream;

  // Cache file operations
  Future<String> get _cacheDirectory async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/waveform_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  String _getCacheKey(String source) {
    // Create a unique key based on the file path or URL
    return source.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
  }

  Future<String> _getCacheFilePath(String source) async {
    final cacheDir = await _cacheDirectory;
    final cacheKey = _getCacheKey(source);
    return '$cacheDir/$cacheKey.json';
  }

  Future<bool> _saveWaveformToCache(
    String source,
    List<double> waveformData,
  ) async {
    PerformanceProfiler.start('saveWaveformCache:total');

    try {
      PerformanceProfiler.start('saveWaveformCache:getPath');
      final cacheFilePath = await _getCacheFilePath(source);
      PerformanceProfiler.end('saveWaveformCache:getPath');

      final file = File(cacheFilePath);

      // Encode waveform data as JSON
      PerformanceProfiler.start('saveWaveformCache:encode');
      final jsonData = jsonEncode(waveformData);
      PerformanceProfiler.end('saveWaveformCache:encode');

      PerformanceProfiler.start('saveWaveformCache:writeFile');
      await file.writeAsString(jsonData);
      PerformanceProfiler.end('saveWaveformCache:writeFile');

      // Also save in memory cache
      _waveformCache[source] = waveformData;

      print('✅ AudioService: Saved waveform to cache: $cacheFilePath');
      return true;
    } catch (e) {
      print('❌ AudioService: Error saving waveform to cache: $e');
      return false;
    } finally {
      final totalTime = PerformanceProfiler.end('saveWaveformCache:total');
      print(
        '⏱️ AudioService: Saving waveform to cache took ${totalTime.inMilliseconds}ms',
      );
    }
  }

  // PUBLIC method to load waveform from cache
  Future<List<double>?> loadWaveformFromCache(String source) async {
    PerformanceProfiler.start('loadWaveformCache:total');

    try {
      // First check memory cache
      PerformanceProfiler.start('loadWaveformCache:memoryCheck');
      if (_waveformCache.containsKey(source)) {
        print('✅ AudioService: Loaded waveform from memory cache');
        PerformanceProfiler.end('loadWaveformCache:memoryCheck');
        return _waveformCache[source];
      }
      PerformanceProfiler.end('loadWaveformCache:memoryCheck');

      try {
        PerformanceProfiler.start('loadWaveformCache:getPath');
        final cacheFilePath = await _getCacheFilePath(source);
        PerformanceProfiler.end('loadWaveformCache:getPath');

        PerformanceProfiler.start('loadWaveformCache:checkExists');
        final file = File(cacheFilePath);
        final exists = await file.exists();
        PerformanceProfiler.end('loadWaveformCache:checkExists');

        if (exists) {
          PerformanceProfiler.start('loadWaveformCache:readFile');
          final jsonData = await file.readAsString();
          PerformanceProfiler.end('loadWaveformCache:readFile');

          PerformanceProfiler.start('loadWaveformCache:decode');
          final List<dynamic> decodedData = jsonDecode(jsonData);
          final waveformData =
              decodedData.map((item) => item as double).toList();
          PerformanceProfiler.end('loadWaveformCache:decode');

          // Save to memory cache for faster access next time
          _waveformCache[source] = waveformData;

          print(
            '✅ AudioService: Loaded waveform from file cache: $cacheFilePath',
          );
          return waveformData;
        }
      } catch (e) {
        print('❌ AudioService: Error loading waveform from cache: $e');
      }

      return null; // Cache miss
    } finally {
      final totalTime = PerformanceProfiler.end('loadWaveformCache:total');
      print(
        '⏱️ AudioService: Loading waveform from cache took ${totalTime.inMilliseconds}ms',
      );
    }
  }

  Future<void> initialize() async {
    try {
      // Initialize audio player with any default settings
      await _audioPlayer.setVolume(1.0);
    } catch (e) {
      print('Error initializing audio player: $e');
      // Continue even if there's an error, as some methods might still work
    }
  }

  // Update your AudioService.loadAudio method with timing measurements

  Future<void> loadAudio(Track track) async {
    // Start overall timing
    PerformanceProfiler.start('loadAudio:total');
    String? effectiveSource = track.path;
    bool isUrl = track.isUrl;
    bool isYouTube = false;

    try {
      print(
        '🔍 AudioService: Starting to load audio from: $effectiveSource, isUrl: $isUrl',
      );

      if (isUrl &&
          (effectiveSource.contains('youtube.com') ||
              effectiveSource.contains('youtu.be'))) {
        isYouTube = true;
        print('🔍 AudioService: Detected YouTube URL. Extracting stream...');
        PerformanceProfiler.start('loadAudio:youtubeExtract');
        try {
          var videoId = VideoId.parseVideoId(
            effectiveSource,
          ); // Extract video ID
          if (videoId == null) {
            throw Exception('Could not parse YouTube Video ID');
          }
          var manifest = await _yt.videos.streamsClient.getManifest(videoId);
          print(
            "Available audio streams: ${manifest.audioOnly}",
          ); // Log available streams

          // Try to find the MP4 stream (specifically tag 140 if possible, or best MP4)
          var streamInfo =
              manifest.audioOnly.where((s) => s.tag == 140).firstOrNull;

          if (streamInfo == null) {
            print("Stream 140 not found, searching for best audio/mp4...");
            var audioOnly = manifest.audioOnly;
            var mp4Streams = audioOnly.where(
              (s) => s.codec.mimeType == 'audio/mp4',
            );
            var sorted = mp4Streams.sortByBitrate();
            var count = sorted.length;
            if (count > 0) {
              streamInfo = sorted.last;
            }
          }

          // Fallback to the highest bitrate overall if no suitable MP4 found
          if (streamInfo == null) {
            print(
              "No suitable MP4 stream found, falling back to highest bitrate overall (might be WebM/Opus).",
            );
            streamInfo = manifest.audioOnly.withHighestBitrate();
          }

          effectiveSource = streamInfo.url.toString();
        } catch (ytError) {
          print('❌ AudioService: Error extracting YouTube stream: $ytError');
          // Rethrow the error to be caught by the outer catch block
          // This allows AudioPlayerBloc to receive a specific error
          throw Exception('Failed to get YouTube audio stream: $ytError');
        } finally {
          PerformanceProfiler.end('loadAudio:youtubeExtract');
        }
      }

      _markersBySource[effectiveSource] = List<TimeMarker>.from(
        track.timeMarkers,
      );
      print(
        "AudioService: Loaded ${track.timeMarkers.length} markers into memory for $effectiveSource",
      );

      // Step 1: Try to set up the audio player
      PerformanceProfiler.start('loadAudio:setPlayer');
      if (isUrl) {
        try {
          print('🔍 AudioService: Setting URL in player');
          await _audioPlayer.setUrl(effectiveSource);
        } catch (e) {
          print('❌ AudioService: Error setting URL: $e');
        }
      } else {
        try {
          print(
            '🔍 AudioService: Setting file path in player: $effectiveSource',
          );
          await _audioPlayer.setFilePath(effectiveSource);
          print('✅ AudioService: Successfully set file path in player');
        } catch (e) {
          print('❌ AudioService: Error setting file path: $e');
        }
      }
      PerformanceProfiler.end('loadAudio:setPlayer');
      if (!isYouTube) {
        print('🔍 AudioService: Checking for cached waveform data');
        PerformanceProfiler.start('loadAudio:checkCache');
        final cachedWaveform = await loadWaveformFromCache(effectiveSource);
        PerformanceProfiler.end('loadAudio:checkCache');

        if (cachedWaveform != null) {
          // Use cached waveform
          PerformanceProfiler.start('loadAudio:useCache');
          _waveformData = cachedWaveform;
          _waveformController.add(_waveformData!);
          print('✅ AudioService: Using cached waveform data');
          PerformanceProfiler.end('loadAudio:useCache');
        } else {
          // No cached data, need to extract
          print(
            '🔍 AudioService: No cached waveform found, extracting new waveform',
          );
          // PerformanceProfiler.start('loadAudio:extractWaveform');
          // Use original source type (isUrl) to decide extraction method
          // if (isUrl) {
          //   await _extractWaveformFromUrl(effectiveSource);
          // } else {
          //   await _extractWaveformFromFile(effectiveSource);
          // }
          // PerformanceProfiler.end('loadAudio:extractWaveform');

          // Save the newly extracted waveform to cache
          if (_waveformData != null && _waveformData!.isNotEmpty) {
            PerformanceProfiler.start('loadAudio:saveToCache');
            await _saveWaveformToCache(effectiveSource, _waveformData!);
            PerformanceProfiler.end('loadAudio:saveToCache');
          }
        }
      } else {
        // For YouTube, generate and use the random fallback waveform
        print(
          '🔍 AudioService: Generating random fallback waveform for YouTube URL.',
        );
        _generateRandomWaveform(); // Generate the random data
        if (_waveformData != null) {
          _waveformController.add(_waveformData!); // Emit the random data
          print('✅ AudioService: Emitted random waveform for YouTube URL.');
        } else {
          print(
            '⚠️ AudioService: Fallback waveform generation failed for YouTube URL.',
          );
          _waveformController.add([]); // Emit empty list as a last resort
        }
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
    } finally {
      // End overall timing
      final totalTime = PerformanceProfiler.end('loadAudio:total');
      print('⏱️ AudioService: Total load time: ${totalTime.inMilliseconds}ms');

      // Log detailed breakdown
      PerformanceProfiler.logAllMeasurements();
    }
  }

  // Add this instrumentation to your _extractWaveformFromFile method

  // static Future<List<double>?> extractWaveformFromFile(String filePath) async {
  //   PerformanceProfiler.start('extractWaveform:total');

  //   print('🔍 AudioService: Starting waveform extraction from file: $filePath');

  //   PerformanceProfiler.start('extractWaveform:getTemp');
  //   final tempDir = await getTemporaryDirectory();
  //   final outputFile = '${tempDir.path}/waveform_data.txt';
  //   PerformanceProfiler.end('extractWaveform:getTemp');

  //   print('🔍 AudioService: Output file path: $outputFile');

  //   // Use FFmpeg Kit to extract audio data for waveform
  //   print('🔍 AudioService: Running FFmpeg command');

  //   // Modify the FFmpeg command to add -y flag which forces overwrite
  //   PerformanceProfiler.start('extractWaveform:ffmpeg');
  //   final session = await FFmpegKit.execute(
  //     '-y -i "$filePath" -ac 1 -filter:a aresample=8000 -map 0:a -c:a pcm_s16le -f data "$outputFile"',
  //   );
  //   PerformanceProfiler.end('extractWaveform:ffmpeg');

  //   final returnCode = await session.getReturnCode();
  //   print(
  //     '🔍 AudioService: FFmpeg return code: ${returnCode?.getValue() ?? "unknown"}',
  //   );

  //   if (ReturnCode.isSuccess(returnCode)) {
  //     print('✅ AudioService: FFmpeg succeeded, processing waveform data');
  //     PerformanceProfiler.start('extractWaveform:process');
  //     await _processWaveformData(outputFile);
  //     PerformanceProfiler.end('extractWaveform:process');
  //     print('✅ AudioService: Completed processing waveform data');
  //   } else {
  //     print(
  //       '❌ AudioService: FFmpeg failed with return code: ${returnCode?.getValue() ?? "unknown"}',
  //     );

  //     // Get logs for debugging
  //     PerformanceProfiler.start('extractWaveform:getLogs');
  //     final logs = await session.getLogs();
  //     for (final log in logs) {
  //       print('❌ AudioService FFmpeg log: ${log.getMessage()}');
  //     }
  //     PerformanceProfiler.end('extractWaveform:getLogs');

  //     // Use fallback method
  //     print('🔍 AudioService: Using random waveform fallback');
  //     PerformanceProfiler.start('extractWaveform:fallback');
  //     _generateRandomWaveform();
  //     if (_waveformData != null) {
  //       print('🔍 AudioService: Adding random waveform data to stream');
  //       _waveformController.add(_waveformData!);
  //       print('✅ AudioService: Successfully added random waveform to stream');
  //     }
  //     PerformanceProfiler.end('extractWaveform:fallback');
  //   }

  //   final totalTime = PerformanceProfiler.end('extractWaveform:total');
  //   print(
  //     '⏱️ AudioService: Waveform extraction took ${totalTime.inMilliseconds}ms',
  //   );
  // }

  static Future<List<double>?> _processWaveformBytes(
    String dataFilePath,
  ) async {
    print('[Isolate] Processing waveform bytes from: $dataFilePath');
    try {
      final file = File(dataFilePath);
      if (!await file.exists()) {
        print(
          '[Isolate] Error: Waveform data file not found at: $dataFilePath',
        );
        return null;
      }

      final bytes = await file.readAsBytes();
      print('[Isolate] Read ${bytes.length} bytes.');

      if (bytes.isEmpty) {
        print('[Isolate] Warning: Waveform data file is empty.');
        return null;
      }

      // Convert bytes to audio samples (16-bit PCM, little-endian)
      List<double> samples = [];
      for (int i = 0; i < bytes.length; i += 2) {
        if (i + 1 < bytes.length) {
          // Combine bytes (assuming little-endian)
          int byte1 = bytes[i];
          int byte2 = bytes[i + 1];
          int sampleInt = (byte2 << 8) | byte1;
          // Convert to signed value if necessary (adjust based on PCM format)
          if (sampleInt > 32767) sampleInt -= 65536;
          // Normalize to -1.0 to 1.0
          samples.add(sampleInt / 32768.0);
        }
      }
      print('[Isolate] Converted to ${samples.length} samples.');

      if (samples.isEmpty) {
        print('[Isolate] Warning: No samples generated after byte conversion.');
        return null;
      }

      // Downsample for display (reduce to ~1000-1500 points)
      const int targetLength = 1500; // Or adjust as needed
      List<double> processedSamples;
      if (samples.length > targetLength) {
        final skipFactor =
            (samples.length / targetLength)
                .floor(); // Use floor for integer skip
        if (skipFactor <= 0) {
          print(
            '[Isolate] Warning: Calculated skipFactor <= 0. Using absolute values directly.',
          );
          processedSamples = samples.map((s) => s.abs()).toList();
        } else {
          List<double> downsampled = [];
          for (int i = 0; i < samples.length; i += skipFactor) {
            double maxAmp = 0;
            // Calculate end index, ensuring it doesn't exceed bounds
            int end =
                (i + skipFactor < samples.length)
                    ? i + skipFactor
                    : samples.length;
            for (int j = i; j < end; j++) {
              final amp = samples[j].abs();
              if (amp > maxAmp) maxAmp = amp;
            }
            downsampled.add(maxAmp);
          }
          processedSamples = downsampled;
        }
      } else {
        // If fewer samples than target, just use their absolute values
        processedSamples = samples.map((s) => s.abs()).toList();
      }
      print(
        '[Isolate] Final processed waveform has ${processedSamples.length} points.',
      );

      return processedSamples.isNotEmpty ? processedSamples : null;
    } catch (e, stackTrace) {
      print('[Isolate] Error processing waveform bytes: $e\n$stackTrace');
      return null;
    }
  }

  // static Future<List<double>?> extractAndProcessWaveform(
  //   String filePath,
  //   String tempDirectoryPath, // <<< ACCEPT temp path as argument
  // ) async {
  //   print('[Static] Starting waveform extraction for: $filePath');
  //   String? outputFile;

  //   try {
  //     // 1. Use the provided temporary directory path
  //     // <<< REMOVE call to getTemporaryDirectory >>>
  //     //
  //     outputFile =
  //         '$tempDirectoryPath/waveform_data_${DateTime.now().millisecondsSinceEpoch}.txt'; // Use provided path
  //     print('[Static] Temp output file: $outputFile');

  //     // 2. Run FFmpeg (same command)
  //     print('[Static] Running FFmpeg...');
  //     // Ensure the output directory exists (robustness)
  //     final outputDir = Directory(pathLib.dirname(outputFile));
  //     if (!await outputDir.exists()) {
  //       await outputDir.create(recursive: true);
  //     }

  //     final session = await FFmpegKit.execute(
  //       '-y -i "$filePath" -ac 1 -filter:a aresample=8000 -map 0:a -c:a pcm_s16le -f data "$outputFile"',
  //     );
  //     final returnCode = await session.getReturnCode();
  //     print(
  //       '[Static] FFmpeg completed. Return code: ${returnCode?.getValue()}',
  //     );

  //     // 3. Check FFmpeg Result and Process Data (same logic)
  //     List<double>? waveformData = null;
  //     if (ReturnCode.isSuccess(returnCode)) {
  //       print('[Static] FFmpeg success. Processing data from $outputFile...');
  //       waveformData = await _processWaveformBytesFromFile(outputFile);
  //     } else {
  //       print('[Static] FFmpeg failed.');
  //       // Handle failure
  //       final logs = await session.getLogsAsString();
  //       print("[Static] FFmpeg Logs:\n$logs"); // Log FFmpeg output on failure
  //     }

  //     // 4. Clean up temp file (always attempt)
  //     try {
  //       final file = File(outputFile);
  //       if (await file.exists()) {
  //         await file.delete();
  //         print('[Static] Deleted temp file: $outputFile');
  //       }
  //     } catch (e) {
  //       print('[Static] Warning: Failed to delete temp file $outputFile: $e');
  //     }

  //     // 5. Return result
  //     return waveformData;
  //   } catch (e, stackTrace) {
  //     print(
  //       '[Static] Unexpected error during waveform extraction: $e\n$stackTrace',
  //     );
  //     // Ensure cleanup on unexpected error
  //     if (outputFile != null) {
  //       try {
  //         final file = File(outputFile);
  //         if (await file.exists()) await file.delete();
  //       } catch (_) {} // Ignore cleanup error
  //     }
  //     return null;
  //   }
  // }

  static Future<List<double>?> processWaveformBytesFromFile(
    String dataFilePath,
  ) async {
    print('[Static Helper] Processing waveform bytes from: $dataFilePath');
    try {
      final file = File(dataFilePath);
      if (!await file.exists()) {
        print(
          '[Static Helper] Error: Waveform data file not found at: $dataFilePath',
        );
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        print('[Static Helper] Warning: Waveform data file is empty.');
        return null; // Handle empty file
      }

      // Convert bytes to samples (16-bit PCM, little-endian assumed)
      List<double> samples = [];
      for (int i = 0; i < bytes.length; i += 2) {
        if (i + 1 < bytes.length) {
          int byte1 = bytes[i];
          int byte2 = bytes[i + 1];
          int sampleInt = (byte2 << 8) | byte1;
          // Convert to signed value
          if (sampleInt > 32767) sampleInt -= 65536;
          // Normalize to -1.0 to 1.0
          samples.add(sampleInt / 32768.0);
        }
      }
      if (samples.isEmpty) {
        print(
          '[Static Helper] Warning: No samples generated after byte conversion.',
        );
        return null; // Handle no samples
      }

      // Downsample for display (e.g., to ~1500 points)
      const int targetLength = 1500;
      List<double> processedSamples;
      if (samples.length > targetLength) {
        final skipFactor = (samples.length / targetLength).floor();
        if (skipFactor <= 0) {
          // Avoid division by zero or infinite loop
          print(
            '[Static Helper] Warning: Calculated skipFactor <= 0. Using absolute values directly.',
          );
          processedSamples = samples.map((s) => s.abs()).toList();
        } else {
          List<double> downsampled = [];
          for (int i = 0; i < samples.length; i += skipFactor) {
            double maxAmp = 0;
            int end =
                (i + skipFactor < samples.length)
                    ? i + skipFactor
                    : samples.length;
            for (int j = i; j < end; j++) {
              final amp = samples[j].abs();
              if (amp > maxAmp) maxAmp = amp;
            }
            downsampled.add(maxAmp);
          }
          processedSamples = downsampled;
        }
      } else {
        // If fewer samples than target, just use their absolute values
        processedSamples = samples.map((s) => s.abs()).toList();
      }
      print(
        '[Static Helper] Final processed waveform has ${processedSamples.length} points.',
      );

      return processedSamples.isNotEmpty ? processedSamples : null;
    } catch (e, stackTrace) {
      print('[Static Helper] Error processing waveform bytes: $e\n$stackTrace');
      return null;
    }
  }

  // Future<void> _extractWaveformFromFile(String filePath) async {
  //   PerformanceProfiler.start('extractWaveformInstance:total');
  //   print(
  //     '🔍 AudioService (Instance): Requesting waveform extraction for $filePath',
  //   );

  //   final tempDir = await getTemporaryDirectory();

  //   // Call the static method to do the actual work
  //   final List<double>? extractedData =
  //       await AudioService.extractAndProcessWaveform(filePath, tempDir.path);

  //   if (extractedData != null) {
  //     print(
  //       '✅ AudioService (Instance): Static extraction succeeded. Updating instance state.',
  //     );
  //     _waveformData = extractedData; // Update instance variable
  //     _waveformController.add(_waveformData!); // Notify listeners
  //   } else {
  //     print(
  //       '❌ AudioService (Instance): Static extraction failed. Using fallback.',
  //     );
  //     // Use fallback method (updates instance state)
  //     _generateRandomWaveform();
  //     if (_waveformData != null) {
  //       _waveformController.add(_waveformData!);
  //     }
  //   }
  //   PerformanceProfiler.end('extractWaveformInstance:total');
  // }

  // Future<void> _extractWaveformFromUrl(String url) async {
  //   // This method might not be needed if loadAudio handles URL setting directly.
  //   // If kept, it should likely also call the instance _extractWaveformFromFile
  //   // after downloading, similar to how loadAudio works.
  //   print(
  //     '🔍 AudioService (Instance): Requesting waveform extraction for URL $url',
  //   );
  //   File? tempFile;
  //   try {
  //     // Download the file
  //     final response = await http.get(Uri.parse(url));
  //     final tempDir = await getTemporaryDirectory();
  //     tempFile = File(
  //       '${tempDir.path}/temp_audio_url_${DateTime.now().millisecondsSinceEpoch}',
  //     );
  //     await tempFile.writeAsBytes(response.bodyBytes);

  //     // Now extract waveform from the downloaded file using the instance method
  //     // final tempDir = await getTemporaryDirectory();

  //     // Call the static method to do the actual work
  //     final List<double>? extractedData =
  //         await AudioService.extractAndProcessWaveform(
  //           tempFile.path,
  //           tempDir.path,
  //         );
  //   } catch (e) {
  //     print(
  //       '❌ AudioService (Instance): Error extracting waveform from URL: $e',
  //     );
  //     // Use fallback method
  //     _generateRandomWaveform();
  //     if (_waveformData != null) {
  //       _waveformController.add(_waveformData!);
  //     }
  //   } finally {
  //     // Clean up downloaded file
  //     try {
  //       if (tempFile != null && await tempFile.exists()) {
  //         await tempFile.delete();
  //         print(
  //           '🔍 AudioService (Instance): Deleted temp URL file: ${tempFile.path}',
  //         );
  //       }
  //     } catch (e) {
  //       print(
  //         '⚠️ AudioService (Instance): Failed to delete temp URL file: ${tempFile?.path} - $e',
  //       );
  //     }
  //   }
  // }

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

  Future<void> saveShufflePreference(bool isActive) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_shufflePrefKey, isActive);
    } catch (e) {
      print("Error saving shuffle preference: $e");
    }
  }

  Future<bool> loadShufflePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_shufflePrefKey) ?? false; // Default to false
    } catch (e) {
      print("Error loading shuffle preference: $e");
      return false;
    }
  }

  // Playback controls
  Future<void> play() async {
    final currentSource = _audioPlayer.audioSource;
    if (currentSource == null) {
      print(
        '▶️ AudioService: Attempting to play, but _audioPlayer.audioSource is null (nothing loaded?).',
      );
    } else if (currentSource is UriAudioSource) {
      // It's a URL source (like http or a file URI)
      print(
        '▶️ AudioService: Attempting to play UriAudioSource: ${currentSource.uri}',
      );
    } else {
      // Handle other potential AudioSource types if you use them
      print(
        '▶️ AudioService: Attempting to play unknown source type: ${currentSource.runtimeType}',
      );
    }
    // <-- END LOGGING -->

    try {
      await _audioPlayer.play();
    } catch (e) {
      print('❌ AudioService: Error during _audioPlayer.play(): $e');
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
  void addMarker(String audioSource, double position, String label) {
    if (!_markersBySource.containsKey(audioSource)) {
      _markersBySource[audioSource] = [];
    }

    final tag = TimeMarker(position: position, label: label);
    _markersBySource[audioSource]!.add(tag);

    // Sort tags by position
    _markersBySource[audioSource]!.sort(
      (a, b) => a.position.compareTo(b.position),
    );
  }

  List<TimeMarker> getTimeMarkersForAudio(String audioSource) {
    return _markersBySource[audioSource] ?? [];
  }

  // Clear specific cache entry
  Future<void> clearCacheForSource(String source) async {
    try {
      final cacheFilePath = await _getCacheFilePath(source);
      final file = File(cacheFilePath);
      if (await file.exists()) {
        await file.delete();
      }
      _waveformCache.remove(source);
      print('✅ AudioService: Cleared cache for: $source');
    } catch (e) {
      print('❌ AudioService: Error clearing cache: $e');
    }
  }

  // Clear all cache
  Future<void> clearAllCache() async {
    try {
      final cacheDir = await _cacheDirectory;
      final directory = Directory(cacheDir);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        await directory.create();
      }
      _waveformCache.clear();
      print('✅ AudioService: Cleared all waveform cache');
    } catch (e) {
      print('❌ AudioService: Error clearing all cache: $e');
    }
  }

  Future<void> dispose() async {
    await _audioPlayer.dispose();
    await _waveformController.close();
  }
}
