// lib/services/waveform_processing_service.dart

import 'dart:async';
import 'dart:isolate';
import 'dart:collection'; // For Queue
import 'dart:io'; // Needed for Directory/File access within static methods if used directly

// Import path_provider for getTemporaryDirectory used in static method
import 'package:path_provider/path_provider.dart';
// Import ffmpeg_kit_flutter for FFmpegKit/ReturnCode used in static method
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';

// TODO: Import your Track model if needed elsewhere in this file
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
    // Example track map: {'id': track.id, 'path': track.filePath}
    _processingQueue.addAll(tracks);
    print(
      '[WaveformService] Added ${tracks.length} tracks. Queue size: ${_processingQueue.length}',
    );
    _startProcessingNext(); // Attempt to start processing if not already active
  }

  // --- Internal Methods ---

  /// Checks the queue and starts processing the next item if available and idle.
  void _startProcessingNext() {
    if (_isProcessing || _processingQueue.isEmpty) {
      // Already processing or queue is empty
      if (_processingQueue.isEmpty) {
        print('[WaveformService] Queue empty, processing finished for now.');
        // Optionally send a "batch finished" signal if needed, though the BLoC can track this
      }
      return;
    }

    _isProcessing = true;
    _receivePort = ReceivePort();
    final trackInfo = _processingQueue.removeFirst();
    final trackId = trackInfo['id']!;
    final filePath = trackInfo['path']!;

    print(
      '[WaveformService] Starting processing for track: $trackId ($filePath)',
    );

    // Data to send to the isolate
    final isolateData = {
      'sendPort': _receivePort!.sendPort,
      'trackId': trackId,
      'filePath': filePath,
    };

    Isolate.spawn(_calculateWaveformIsolateEntry, isolateData)
        .then((isolate) {
          _isolate = isolate;
        })
        .catchError((error) {
          print('[WaveformService] Error spawning isolate: $error');
          // Handle the error by sending an update
          _handleIsolateResult({
            'status': 'error', // Use 'error' status
            'trackId': trackId,
            'error': 'Failed to spawn isolate: $error',
          });
          _cleanUpAfterProcessing(); // Ensure cleanup even on spawn error
          _startProcessingNext(); // Try next item
        });

    // Listen for messages from the isolate
    _receivePort!.listen((message) {
      _handleIsolateResult(message as Map<String, dynamic>);
      _cleanUpAfterProcessing(); // Clean up after receiving result
      _startProcessingNext(); // Process the next item in the queue
    });
  }

  /// Handles messages received from the isolate.
  void _handleIsolateResult(Map<String, dynamic> result) {
    final trackId = result['trackId'] as String;
    final status = result['status'] as String; // 'success' or 'error'

    print('[WaveformService] Received result for $trackId: $status');

    if (status == 'success') {
      // Waveform data should be present on success
      final waveformData = (result['waveformData'] as List?)?.cast<double>();
      _updateStreamController.add(
        WaveformProcessingUpdate(
          trackId: trackId,
          waveformData: waveformData, // Should not be null on success status
          isCompletionUpdate: true,
        ),
      );
    } else {
      // status == 'error'
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

  /// Cleans up resources associated with the completed isolate.
  void _cleanUpAfterProcessing() {
    _receivePort?.close();
    _receivePort = null;
    // _isolate?.kill(); // Killing might be too abrupt, isolates exit when done.
    _isolate = null;
    _isProcessing = false;
    print('[WaveformService] Cleaned up resources.');
  }

  /// Call this when the application is closing or the service is no longer needed.
  void dispose() {
    _isolate?.kill(
      priority: Isolate.immediate,
    ); // Ensure isolate is killed on dispose
    _receivePort?.close();
    _updateStreamController.close();
    print('[WaveformService] Disposed.');
  }
}

// --- Isolate Entry Point ---

/// Top-level or static function to be executed in the isolate.
/// It receives necessary data via the 'message' parameter.
Future<void> _calculateWaveformIsolateEntry(
  Map<String, dynamic> message,
) async {
  final SendPort sendPort = message['sendPort'] as SendPort;
  final String trackId = message['trackId'] as String;
  final String filePath = message['filePath'] as String;

  // Ensure necessary plugins are initialized for the isolate if needed
  // WidgetsFlutterBinding.ensureInitialized(); // Usually not needed/allowed in isolates
  // Might need specific initialization for plugins like ffmpeg if they require it per-isolate

  try {
    // Call the new static waveform extraction method from AudioService
    print(
      '[Isolate $trackId] Calling AudioService.extractAndProcessWaveform for $filePath...',
    );
    final List<double>? waveformData =
        await AudioService.extractAndProcessWaveform(filePath);

    if (waveformData != null) {
      print('[Isolate $trackId] Calculation successful. Sending data back.');
      // Send success result back to the main isolate
      sendPort.send({
        'status': 'success',
        'trackId': trackId,
        'waveformData': waveformData,
      });
    } else {
      print(
        '[Isolate $trackId] Calculation failed (returned null). Sending error back.',
      );
      // Send error result back to the main isolate
      sendPort.send({
        'status': 'error',
        'trackId': trackId,
        'error': 'Waveform extraction failed or produced no data.',
      });
    }
  } catch (e, stackTrace) {
    // Catch potential synchronous errors or unexpected exceptions
    print(
      '[Isolate $trackId] Unexpected error during waveform calculation call: $e\n$stackTrace',
    );
    // Send error back to the main isolate
    sendPort.send({
      'status': 'error',
      'trackId': trackId,
      'error': 'Isolate unexpected error: ${e.toString()}',
    });
  }
}
