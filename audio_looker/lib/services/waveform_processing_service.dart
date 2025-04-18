// lib/services/waveform_processing_service.dart

import 'dart:async';
import 'dart:isolate';
import 'dart:collection'; // For Queue
import 'dart:io'; // Needed for Directory/File access within static methods if used directly
import 'package:path/path.dart' as pathLib;

// Import path_provider for getTemporaryDirectory used in static method
import 'package:path_provider/path_provider.dart';
// Import ffmpeg_kit_flutter for FFmpegKit/ReturnCode used in static method
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';

import 'package:flutter/services.dart';
// import '../models/track.dart'; // Adjust path as needed

// Import the AudioService to call the static method
import 'audio_service.dart'; // Adjust path as needed

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
  // Using a Map to easily store path along with ID
  final Queue<Map<String, String>> _processingQueue = Queue();
  bool _isProcessing = false;
  ReceivePort? _receivePort;
  Isolate? _isolate; // For simplicity, start with one isolate at a time

  // StreamController to broadcast updates to listeners (e.g., WaveformProcessingBloc)
  // Using broadcast so multiple listeners could potentially attach (though likely just one BLoC)
  final _updateStreamController =
      StreamController<WaveformProcessingUpdate>.broadcast();

  // Public stream for BLoCs or other parts of the app to listen to
  Stream<WaveformProcessingUpdate> get updates =>
      _updateStreamController.stream;

  // --- Public Methods ---

  /// Adds a list of tracks to the processing queue.
  /// Requires track ID and file path.
  void addTracksToQueue(List<Map<String, String>> tracks) {
    _processingQueue.addAll(tracks);
    print(
      '[WaveformService] Added ${tracks.length} tracks. Queue size: ${_processingQueue.length}',
    );
    _startProcessingNext();
  }

  // --- Internal Methods ---

  Future<void> _startProcessingNext() async {
    // Make async
    if (_isProcessing || _processingQueue.isEmpty) {
      if (_processingQueue.isEmpty) {
        print('[WaveformService] Queue empty, processing finished for now.');
      }
      return;
    }
    _isProcessing = true;
    // ReceivePort? receivePort; // Define later if needed for isolate communication

    final trackInfo = _processingQueue.removeFirst();
    final trackId = trackInfo['id']!;
    final filePath = trackInfo['path']!;
    String? ffmpegOutputFile; // Path to the file FFmpeg creates

    try {
      print(
        '[WaveformService] Starting FFmpeg extraction for track: $trackId ($filePath)',
      );

      // --- Execute FFmpeg in the MAIN isolate ---
      final Directory tempDir = await getTemporaryDirectory();
      ffmpegOutputFile =
          '${tempDir.path}/waveform_data_$trackId.txt'; // Unique name per track

      // Ensure output dir exists
      final outputDir = Directory(pathLib.dirname(ffmpegOutputFile));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final session = await FFmpegKit.execute(
        '-y -i "$filePath" -ac 1 -filter:a aresample=8000 -map 0:a -c:a pcm_s16le -f data "$ffmpegOutputFile"',
      );
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        print(
          '[WaveformService] FFmpeg success for $trackId. Spawning isolate for processing.',
        );
        // --- FFmpeg Success: Spawn Isolate to Process Data File ---

        ReceivePort receivePort =
            ReceivePort(); // Create receive port for this isolate
        _receivePort = receivePort; // Store it for cleanup

        final isolateData = {
          'sendPort': receivePort.sendPort,
          'trackId': trackId,
          // Pass the path to the FFmpeg output file, NOT the original audio file path
          'dataFilePath': ffmpegOutputFile,
        };

        _isolate = await Isolate.spawn(
          _processWaveformFileIsolateEntry, // Use a new entry point
          isolateData,
        );

        receivePort.listen((message) {
          _handleIsolateResult(message as Map<String, dynamic>);
          _cleanUpAfterProcessing(); // Clean up port/isolate
          _startProcessingNext(); // Process next item
        });
        // --- End Isolate Spawning ---
      } else {
        // --- FFmpeg Failure ---
        print(
          '[WaveformService] FFmpeg failed for $trackId. Code: ${returnCode?.getValue()}',
        );
        final logs = await session.getLogsAsString();
        print("[WaveformService] FFmpeg Logs:\n$logs");

        // Clean up potentially created (but empty/invalid) output file
        if (ffmpegOutputFile != null) {
          final file = File(ffmpegOutputFile);
          if (await file.exists()) await file.delete();
        }

        _handleIsolateResult({
          // Report failure back
          'status': 'error',
          'trackId': trackId,
          'error': 'FFmpeg extraction failed (Code: ${returnCode?.getValue()})',
        });
        _isProcessing = false; // Reset flag
        _startProcessingNext(); // Try next item
      }
    } catch (error, stackTrace) {
      print(
        '[WaveformService] Error during FFmpeg execution/Isolate setup: $error\n$stackTrace',
      );
      // Clean up temp file if path exists
      if (ffmpegOutputFile != null) {
        try {
          final file = File(ffmpegOutputFile);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      _handleIsolateResult({
        'status': 'error',
        'trackId': trackId,
        'error': 'WaveformService error: ${error.toString()}',
      });
      _isProcessing = false; // Reset flag
      _cleanUpAfterProcessing(); // Clean up any potential isolate/port
      _startProcessingNext(); // Attempt next item
    }
  }

  /// Handles messages received from the isolate.
  void _handleIsolateResult(Map<String, dynamic> result) {
    final trackId = result['trackId'] as String;
    final status = result['status'] as String;
    if (status == 'success') {
      final waveformData = (result['waveformData'] as List?)?.cast<double>();
      _updateStreamController.add(
        WaveformProcessingUpdate(
          trackId: trackId,
          waveformData: waveformData,
          isCompletionUpdate: true,
        ),
      );
    } else {
      final errorMsg =
          result['error'] as String? ?? 'Unknown error from isolate';
      _updateStreamController.add(
        WaveformProcessingUpdate(
          trackId: trackId,
          error: errorMsg,
          isCompletionUpdate: true,
        ),
      );
    }
  }

  static Future<void> _processWaveformFileIsolateEntry(
    Map<String, dynamic> message,
  ) async {
    final SendPort sendPort = message['sendPort'] as SendPort;
    final String trackId = message['trackId'] as String;
    final String dataFilePath =
        message['dataFilePath'] as String; // Path to the FFmpeg output

    // NO Platform channels needed here!

    try {
      print('[Isolate $trackId] Processing data file: $dataFilePath');
      // Call the static helper from AudioService (or move the logic here)
      final List<double>? waveformData =
          await AudioService.processWaveformBytesFromFile(dataFilePath);

      // Clean up the data file *after* processing
      try {
        final file = File(dataFilePath);
        if (await file.exists()) {
          await file.delete();
          print('[Isolate $trackId] Deleted temp data file: $dataFilePath');
        }
      } catch (e) {
        print(
          '[Isolate $trackId] Warning: Failed to delete temp data file $dataFilePath: $e',
        );
      }

      if (waveformData != null) {
        print('[Isolate $trackId] Processing successful. Sending data back.');
        sendPort.send({
          'status': 'success',
          'trackId': trackId,
          'waveformData': waveformData,
        });
      } else {
        print(
          '[Isolate $trackId] Processing failed (returned null). Sending error back.',
        );
        sendPort.send({
          'status': 'error',
          'trackId': trackId,
          'error': 'Waveform data processing failed.',
        });
      }
    } catch (e, stackTrace) {
      print(
        '[Isolate $trackId] Unexpected error during data processing: $e\n$stackTrace',
      );
      // Attempt cleanup even on error
      try {
        File(dataFilePath).deleteSync();
      } catch (_) {}
      sendPort.send({
        'status': 'error',
        'trackId': trackId,
        'error': 'Isolate processing error: ${e.toString()}',
      });
    }
  }

  void _cleanUpAfterProcessing() {
    _receivePort?.close();
    _receivePort = null;
    _isolate = null;
    _isProcessing = false;
    print('[WaveformService] Cleaned up resources.');
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _updateStreamController.close();
    print('[WaveformService] Disposed.');
  }
}

// --- Isolate Entry Point ---

// Future<void> _calculateWaveformIsolateEntry(
//   Map<String, dynamic> message,
// ) async {
//   final SendPort sendPort = message['sendPort'] as SendPort;
//   final String trackId = message['trackId'] as String;
//   final String filePath = message['filePath'] as String;
//   final String tempPath =
//       message['tempPath'] as String; // <<< RECEIVE temp path string
//   // <<< RECEIVE token

//   // <<< INITIALIZE BackgroundIsolateBinaryMessenger >>>
//   // BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
//   // print('[Isolate $trackId] BackgroundIsolateBinaryMessenger initialized.');
//   // <<< END INITIALIZATION >>>

//   // Ensure necessary plugins are initialized for the isolate if needed
//   // WidgetsFlutterBinding.ensureInitialized(); // Usually not needed/allowed in isolates
//   // Might need specific initialization for plugins like ffmpeg if they require it per-isolate

//   try {
//     print(
//       '[Isolate $trackId] Calling AudioService.extractAndProcessWaveform for $filePath...',
//     );
//     // final tempDir = await getTemporaryDirectory();
//     // This call should now succeed because path_provider can communicate
//     final List<double>? waveformData =
//         await AudioService.extractAndProcessWaveform(filePath, tempPath);

//     if (waveformData != null) {
//       print('[Isolate $trackId] Calculation successful. Sending data back.');
//       sendPort.send({
//         'status': 'success',
//         'trackId': trackId,
//         'waveformData': waveformData,
//       });
//     } else {
//       print(
//         '[Isolate $trackId] Calculation failed (returned null). Sending error back.',
//       );
//       sendPort.send({
//         'status': 'error',
//         'trackId': trackId,
//         'error': 'Waveform extraction failed or produced no data.',
//       });
//     }
//   } catch (e, stackTrace) {
//     print(
//       '[Isolate $trackId] Unexpected error during waveform calculation call: $e\n$stackTrace',
//     );
//     sendPort.send({
//       'status': 'error',
//       'trackId': trackId,
//       'error': 'Isolate unexpected error: ${e.toString()}',
//     });
//   }
// }
