// lib/services/waveform_processing_service.dart

import 'dart:async';
import 'dart:isolate';
import 'dart:collection'; // For Queue
import 'dart:io'; // Needed for Directory/File access
import 'dart:math'; // Required for pow, round, max, min
import 'package:path/path.dart' as pathLib;

// Import path_provider for getTemporaryDirectory
import 'package:path_provider/path_provider.dart';
// Import ffmpeg_kit_flutter and ffprobe_kit_flutter
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:ffmpeg_kit_flutter/media_information.dart';
import 'package:ffmpeg_kit_flutter/media_information_session.dart'; // Ensure this import is present

// Import the AudioService to call the static method - needed for the isolate entry point
import 'audio_service.dart'; // Adjust path as needed - needed if _processWaveformFileIsolateEntry uses it

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

  // Isolate/Port for DATA processing (parsing the text file)
  ReceivePort? _dataProcessingReceivePort;
  Isolate? _dataProcessingIsolate;

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

  // --- Internal Methods ---

  Future<void> _startProcessingNext() async {
    if (_isProcessing || _processingQueue.isEmpty) {
      if (_processingQueue.isEmpty) {
        print('[WaveformService] Queue empty, processing finished for now.');
      }
      return;
    }
    _isProcessing = true;

    final trackInfo = _processingQueue.removeFirst();
    final trackId = trackInfo['id']!;
    final inputFilePath = trackInfo['path']!;
    String? ffmpegOutputFile; // For the astats output

    try {
      print(
        '[WaveformService] Step 1: Getting media info for track: $trackId ($inputFilePath)',
      );

      // --- Step 1: Get Media Information (Duration) using FFprobeKit ---
      final MediaInformationSession sessionInfo =
          await FFprobeKit.getMediaInformation(inputFilePath);
      final MediaInformation? mediaInfo = sessionInfo.getMediaInformation();
      final String? durationString = mediaInfo?.getDuration();

      if (durationString == null) {
        throw Exception('Could not get duration from media information.');
      }
      final double durationSeconds = double.tryParse(durationString) ?? 0.0;
      if (durationSeconds <= 0) {
        throw Exception(
          'Invalid duration ($durationSeconds) obtained from media information.',
        );
      }
      print(
        '[WaveformService] Duration found: ${durationSeconds.toStringAsFixed(2)}s',
      );

      // --- Step 2: Calculate Target Sample Rate for ~1024 points ---
      const int desiredPoints = 1024;
      const int fixedSamplesPerSegment =
          200; // Keep analysis window size fixed (e.g., 200 samples)
      final double targetTotalSamples =
          (desiredPoints * fixedSamplesPerSegment).toDouble();
      int targetSampleRate = (targetTotalSamples / durationSeconds).round();
      targetSampleRate = targetSampleRate.clamp(500, 48000); // Clamp rate

      print(
        '[WaveformService] Calculated targetSampleRate: $targetSampleRate Hz for ~1024 points with fixed segment size $fixedSamplesPerSegment',
      );

      // --- Step 3: Prepare and Run FFmpeg with calculated sample rate ---
      final Directory tempDir = await getTemporaryDirectory();
      ffmpegOutputFile = '${tempDir.path}/waveform_data_$trackId.txt';

      final outputDir = Directory(pathLib.dirname(ffmpegOutputFile));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final String ffmpegCommand =
          '-i "$inputFilePath" '
          '-af "aresample=$targetSampleRate,asetnsamples=$fixedSamplesPerSegment,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.Peak_level:file=\'$ffmpegOutputFile\'" '
          '-f null -';

      print(
        '[WaveformService] Step 3: Executing FFmpeg command: $ffmpegCommand',
      );
      final sessionExec = await FFmpegKit.execute(ffmpegCommand);
      final returnCode = await sessionExec.getReturnCode();
      final ffmpegReturnCodeValue = returnCode?.getValue();

      if (ReturnCode.isSuccess(returnCode)) {
        print(
          '[WaveformService] FFmpeg astats SUCCESS for $trackId. Spawning data processing isolate.',
        );
        // *** Call the method defined below ***
        _spawnDataProcessingIsolate(trackId, ffmpegOutputFile);
      } else {
        // --- FFmpeg Failure ---
        print(
          '[WaveformService] FFmpeg astats FAILED for $trackId. Code: $ffmpegReturnCodeValue',
        );
        final logs = await sessionExec.getLogsAsString();
        print("[WaveformService] FFmpeg Logs:\n$logs");
        _cleanupTempFile(ffmpegOutputFile);
        _reportError(
          trackId,
          'FFmpeg processing failed (Code: $ffmpegReturnCodeValue)',
        );
        _finalizeProcessingStep();
      }
    } catch (error, stackTrace) {
      // Catch errors from ffprobe or ffmpeg setup/execution
      print(
        '[WaveformService] Error during processing for $trackId: $error\n$stackTrace',
      );
      _cleanupTempFile(ffmpegOutputFile);
      _reportError(trackId, 'WaveformService error: ${error.toString()}');
      _finalizeProcessingStep();
    }
  }

  // --- Helper Methods (Now explicitly included) ---

  /// Spawns the isolate to process the text data file generated by FFmpeg.
  void _spawnDataProcessingIsolate(String trackId, String dataFilePath) {
    _cleanupDataProcessingResources(); // Clean up previous ones if any
    _dataProcessingReceivePort = ReceivePort();

    final isolateData = {
      'sendPort': _dataProcessingReceivePort!.sendPort,
      'trackId': trackId,
      'dataFilePath': dataFilePath, // Path to the TEXT file
    };

    print(
      '[WaveformService] Spawning data processing isolate for $trackId with file: $dataFilePath',
    );
    Isolate.spawn(
          _processWaveformFileIsolateEntry, // Static function defined below
          isolateData,
          onError: _dataProcessingReceivePort!.sendPort,
          onExit: _dataProcessingReceivePort!.sendPort,
        )
        .then((isolate) {
          _dataProcessingIsolate = isolate;
          print(
            '[WaveformService] Data processing isolate spawned for $trackId.',
          );
        })
        .catchError((error, stackTrace) {
          print(
            '[WaveformService] Failed to spawn data processing isolate for $trackId: $error\n$stackTrace',
          );
          _cleanupTempFile(dataFilePath);
          _reportError(trackId, 'Failed to start data processing.');
          _finalizeProcessingStep();
        });

    _dataProcessingReceivePort!.listen((message) {
      if (message is Map<String, dynamic>) {
        _handleDataProcessingIsolateResult(message);
      } else {
        print(
          '[WaveformService] Received unexpected message from data isolate for $trackId: $message',
        );
        _reportError(
          trackId,
          'Unexpected result from data processing isolate.',
        );
      }
      _cleanupDataProcessingResources();
      _finalizeProcessingStep();
    });
  }

  /// Handles messages received from the DATA PROCESSING isolate.
  void _handleDataProcessingIsolateResult(Map<String, dynamic> result) {
    final trackId = result['trackId'] as String;
    final status = result['status'] as String?;

    print(
      '[WaveformService] Received result from DATA processing isolate for $trackId: Status=$status',
    );

    if (status == 'success') {
      final waveformData = (result['waveformData'] as List?)?.cast<double>();
      _updateStreamController.add(
        WaveformProcessingUpdate(
          trackId: trackId,
          waveformData: waveformData,
          isCompletionUpdate: true,
        ),
      );
      print('[WaveformService] Data processing SUCCESS for $trackId.');
    } else {
      final errorMsg =
          result['error'] as String? ??
          'Unknown error from data processing isolate';
      _reportError(trackId, errorMsg);
      print('[WaveformService] Data processing FAILED for $trackId: $errorMsg');
    }
  }

  /// Reports an error via the stream controller.
  void _reportError(String trackId, String errorMsg) {
    _updateStreamController.add(
      WaveformProcessingUpdate(
        trackId: trackId,
        error: errorMsg,
        isCompletionUpdate: true,
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
          print('[WaveformService] Cleaned up temp file: $filePath');
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
    print('[WaveformService] Finalized processing step. Checking queue...');
    _startProcessingNext();
  }

  /// Cleans up resources associated with the data processing isolate.
  void _cleanupDataProcessingResources() {
    try {
      _dataProcessingReceivePort?.close();
      print('[WaveformService] Data processing receive port closed.');
    } catch (e) {
      print('[WaveformService] Error closing data processing receive port: $e');
    }
    try {
      _dataProcessingIsolate?.kill(priority: Isolate.immediate);
      print('[WaveformService] Data processing isolate killed.');
    } catch (e) {
      print('[WaveformService] Error killing data processing isolate: $e');
    }
    _dataProcessingReceivePort = null;
    _dataProcessingIsolate = null;
    print('[WaveformService] Cleaned up data processing resources.');
  }

  void dispose() {
    print('[WaveformService] Disposing...');
    _cleanupDataProcessingResources(); // Clean up active resources
    _updateStreamController.close();
    _processingQueue.clear();
    print('[WaveformService] Disposed.');
  }
} // End of WaveformProcessingService class

// --- Static Isolate Entry Point (defined outside the class) ---

/// Isolate entry point for processing the waveform data file (PARSING TEXT NOW).
Future<void> _processWaveformFileIsolateEntry(
  Map<String, dynamic> message,
) async {
  final SendPort sendPort = message['sendPort'] as SendPort;
  final String trackId = message['trackId'] as String;
  final String dataFilePath =
      message['dataFilePath'] as String; // This is now a TEXT file path

  List<double> waveformData = [];
  // Regex to find the peak level value (e.g., lavfi.astats.Overall.Peak_level=-12.345)
  final RegExp peakLevelRegex = RegExp(
    r"lavfi\.astats\.Overall\.Peak_level=([-\d\.]+|inf|-inf)",
  );

  try {
    print('[Data Isolate $trackId] Parsing astats data file: $dataFilePath');
    final file = File(dataFilePath);

    if (!await file.exists()) {
      print(
        '[Data Isolate $trackId] Error: astats data file not found at: $dataFilePath',
      );
      throw Exception('FFmpeg output file not found.');
    }

    // *** CORRECTED CODE HERE: await the Future, then use standard for loop ***
    final List<String> lines =
        await file.readAsLines(); // Get the list of lines
    for (String line in lines) {
      // Iterate over the list
      // --- Loop body remains the same ---
      final match = peakLevelRegex.firstMatch(line);
      if (match != null) {
        final String dbValueString = match.group(1)!;
        double dbValue;

        // Handle negative infinity (silence)
        if (dbValueString == '-inf' || dbValueString == 'inf') {
          dbValue = -120.0; // Treat silence as very low dB
        } else {
          dbValue = double.tryParse(dbValueString) ?? -120.0;
        }

        // Convert dBFS to linear amplitude (0.0 to 1.0)
        double clampedDb = dbValue.clamp(-60.0, 0.0);
        double linearValue = pow(10, clampedDb / 20).toDouble();

        waveformData.add(linearValue);
      }
      // --- End of loop body ---
    }

    print('[Data Isolate $trackId] Parsed ${waveformData.length} data points.');

    // Clean up the temporary text data file *inside the isolate*
    try {
      await file.delete();
      print('[Data Isolate $trackId] Deleted astats data file: $dataFilePath');
    } catch (e) {
      print(
        '[Data Isolate $trackId] Warning: Failed to delete astats data file $dataFilePath: $e',
      );
    }

    if (waveformData.isNotEmpty) {
      print('[Data Isolate $trackId] Parsing successful. Sending data back.');
      sendPort.send({
        'status': 'success',
        'trackId': trackId,
        'waveformData': waveformData,
      });
    } else {
      print(
        '[Data Isolate $trackId] Processing failed (no data points parsed). Sending error back.',
      );
      sendPort.send({
        'status': 'error',
        'trackId': trackId,
        'error':
            'Waveform data processing failed (no points parsed from FFmpeg output).',
      });
    }
  } catch (e, stackTrace) {
    print(
      '[Data Isolate $trackId] Unexpected error during astats data processing: $e\n$stackTrace',
    );
    // Attempt cleanup even on unexpected error
    try {
      final file = File(dataFilePath);
      if (await file.exists()) {
        await file.delete();
        print(
          '[Data Isolate $trackId] Deleted astats data file after error: $dataFilePath',
        );
      }
    } catch (_) {}

    sendPort.send({
      'status': 'error',
      'trackId': trackId,
      'error': 'Isolate data processing error: ${e.toString()}',
    });
  }
}
