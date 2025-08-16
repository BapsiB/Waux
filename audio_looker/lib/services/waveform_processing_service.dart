// lib/services/waveform_processing_service.dart

import 'dart:async';
// import 'dart:isolate'; // REMOVED: No longer using isolates
import 'dart:collection'; // For Queue
import 'dart:io'; // Needed for Directory/File access
import 'dart:math'; // Required for pow, round, max, min
import 'package:path/path.dart' as pathLib;

// Import path_provider for getTemporaryDirectory
import 'package:path_provider/path_provider.dart';
// Import ffmpeg_kit_flutter and ffprobe_kit_flutter
// import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
// import 'package:ffmpeg_kit_flutter/ffprobe_kit.dart';
// import 'package:ffmpeg_kit_flutter/return_code.dart';
// import 'package:ffmpeg_kit_flutter/media_information.dart';
// import 'package:ffmpeg_kit_flutter/media_information_session.dart'; // Ensure this import is present

// Import the AudioService (keep for potential revert)
import 'audio_service.dart';

// Define a class to represent updates from the service
class WaveformProcessingUpdate {
  final String trackId;
  final List<double>? waveformData; // Null if error or just progress update
  final String? error; // Null if success or progress update
  final bool
  isCompletionUpdate; // True if this update signifies completion/failure for the track

  WaveformProcessingUpdate({
    required this.trackId,
    this.waveformData,
    this.error,
    this.isCompletionUpdate = false,
  });
}

class WaveformProcessingService {
  // Queue to hold track information for processing
  final Queue<Map<String, String>> _processingQueue = Queue();
  bool _isProcessing = false;

  // --- REMOVE Isolate variables ---
  // ReceivePort? _dataProcessingReceivePort;
  // Isolate? _dataProcessingIsolate;
  // --- END REMOVE ---

  // StreamController to broadcast updates
  final _updateStreamController =
      StreamController<WaveformProcessingUpdate>.broadcast();

  // Public stream for listeners
  Stream<WaveformProcessingUpdate> get updates =>
      _updateStreamController.stream;

  // --- Public Methods ---
  void addTracksToQueue(List<Map<String, String>> tracks) {
    _processingQueue.addAll(tracks);
    print(
      '[WaveformService] Added ${tracks.length} tracks. Queue size: ${_processingQueue.length}',
    );
    _startProcessingNext();
  }

  // --- REVISED _startProcessingNext (Original processing, NO ISOLATE) ---
  Future<void> _startProcessingNext() async {
    if (_isProcessing || _processingQueue.isEmpty) {
      // if (_processingQueue.isEmpty) { // Reduce noise
      //   print('[WaveformService] Queue empty, processing finished for now.');
      // }
      return;
    }
    _isProcessing = true;

    final trackInfo = _processingQueue.removeFirst();
    final trackId = trackInfo['id']!;
    final inputFilePath = trackInfo['path']!;
    String? ffmpegOutputFile; // For the astats output

    print(
      '[WaveformService REAL_PROCESS_NO_ISOLATE] Starting processing for $trackId ($inputFilePath)',
    );

    try {
      // --- TEMPORARY STUB: FFmpeg functionality disabled ---
      print(
        '[WaveformService REAL_PROCESS_NO_ISOLATE] FFmpeg functionality temporarily disabled for build.',
      );

      // Create a dummy waveform data for now
      final List<double> dummyWaveform = List.generate(
        1024,
        (index) => (0.5 + 0.3 * (index % 100) / 100.0).clamp(0.0, 1.0),
      );

      _updateStreamController.add(
        WaveformProcessingUpdate(
          trackId: trackId,
          waveformData: dummyWaveform,
          isCompletionUpdate: true,
        ),
      );

      _finalizeProcessingStep();
    } catch (error, stackTrace) {
      // Catch errors from ffprobe or ffmpeg setup/execution
      print(
        '[WaveformService REAL_PROCESS_NO_ISOLATE] Error during processing for $trackId: $error\n$stackTrace',
      );
      await _cleanupTempFile(
        ffmpegOutputFile,
      ); // Await cleanup before reporting
      _reportError(trackId, 'WaveformService error: ${error.toString()}');
      _finalizeProcessingStep(); // Ensure queue continues on other errors
    }
  }
  // --- END REVISED _startProcessingNext ---

  // --- NEW Synchronous Astats File Processing Method ---
  Future<void> _processAstatsFileSynchronously(
    String trackId,
    String dataFilePath,
  ) async {
    List<double> waveformData = [];
    final RegExp peakLevelRegex = RegExp(
      r"lavfi\.astats\.Overall\.Peak_level=([-\d\.]+|inf|-inf)",
    );
    File? file; // Declare file variable here

    try {
      // print( // Reduce noise
      //   '[WaveformService REAL_PROCESS_NO_ISOLATE] Reading sync: $dataFilePath',
      // );
      file = File(dataFilePath); // Assign file

      if (!await file.exists()) {
        throw Exception('FFmpeg output file not found at: $dataFilePath');
      }

      final List<String> lines = await file.readAsLines();
      for (String line in lines) {
        final match = peakLevelRegex.firstMatch(line);
        if (match != null) {
          final String dbValueString = match.group(1)!;
          double dbValue =
              (dbValueString == '-inf' || dbValueString == 'inf')
                  ? -120.0
                  : double.tryParse(dbValueString) ?? -120.0;
          double clampedDb = dbValue.clamp(-60.0, 0.0);
          waveformData.add(pow(10, clampedDb / 20).toDouble());
        }
      }
      print(
        '[WaveformService REAL_PROCESS_NO_ISOLATE] Sync parse complete: ${waveformData.length} points for $trackId.',
      );

      if (waveformData.isNotEmpty) {
        // Report success
        _updateStreamController.add(
          WaveformProcessingUpdate(
            trackId: trackId,
            waveformData: waveformData,
            isCompletionUpdate: true,
          ),
        );
        print(
          '[WaveformService REAL_PROCESS_NO_ISOLATE] Sync processing SUCCESS for $trackId.',
        );
      } else {
        throw Exception('No waveform data points parsed from FFmpeg output.');
      }
    } catch (e, stackTrace) {
      print(
        '[WaveformService REAL_PROCESS_NO_ISOLATE] Error during sync processing for $trackId: $e\n$stackTrace',
      );
      _reportError(trackId, 'Sync data processing error: ${e.toString()}');
    } finally {
      // Clean up the temporary file
      await _cleanupTempFile(dataFilePath); // Use the passed path
      // Always finalize the step
      _finalizeProcessingStep();
    }
  }
  // --- END NEW Synchronous Processing Method ---

  // --- REMOVE Isolate-related Methods ---
  // void _spawnDataProcessingIsolate(...) { ... }
  // void _handleDataProcessingIsolateResult(...) { ... }
  // void _cleanupDataProcessingResources() { ... }
  // --- END REMOVE ---

  /// Reports an error via the stream controller.
  void _reportError(String trackId, String errorMsg) {
    _updateStreamController.add(
      WaveformProcessingUpdate(
        trackId: trackId,
        error: errorMsg,
        isCompletionUpdate: true, // Mark as completion even on error
      ),
    );
  }

  /// Cleans up a temporary file if it exists.
  Future<void> _cleanupTempFile(String? filePath) async {
    if (filePath != null) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          // print('[WaveformService] Cleaned up temp file: $filePath'); // Reduce noise
        }
      } catch (e) {
        print(
          '[WaveformService] Warning: Failed to clean up temp file $filePath: $e',
        );
      }
    }
  }

  /// Finalizes the current processing step and attempts to start the next.
  void _finalizeProcessingStep() {
    _isProcessing = false;
    // print('[WaveformService] Finalized processing step. Checking queue...'); // Reduce noise
    Future.delayed(Duration.zero, _startProcessingNext);
  }

  void dispose() {
    print('[WaveformService] Disposing...');
    // _cleanupDataProcessingResources(); // No longer needed
    _updateStreamController.close();
    _processingQueue.clear();
    print('[WaveformService] Disposed.');
  }
} // End of WaveformProcessingService class

// --- Isolate Entry Point (Keep commented out or remove) ---
/*
Future<void> _processWaveformFileIsolateEntry(
    Map<String, dynamic> message,
    ) async {
  // ... (isolate logic remains here but is not called in this version)
}
*/
