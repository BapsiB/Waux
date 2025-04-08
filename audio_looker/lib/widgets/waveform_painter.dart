import 'package:flutter/material.dart';
import 'package:audio_looker/services/audio_service.dart';
import 'dart:math' as math;

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double playbackProgress;
  final double? dragProgress;
  final Color activeColor;
  final Color inactiveColor;
  final double? tagPosition;
  final List<AudioTag> tags;

  // Cache for performance
  Path? _waveformPathInactive;
  Path? _waveformPathActive;
  List<double>? _downsampledData;
  Size? _lastSize;
  final Paint _baselinePaint =
      Paint()
        ..color = Colors.grey[300]!
        ..strokeWidth = 1;
  final Paint _playbackLinePaint =
      Paint()
        ..color = Colors.red
        ..strokeWidth = 2;
  final Paint _scrubPaint =
      Paint()
        ..color = Colors.orangeAccent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
  final Paint _tagPaint =
      Paint()
        ..color = Colors.red
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
  final Paint _currentTagPaint =
      Paint()
        ..color = Colors.green
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
  final Paint _tagRectPaint = Paint()..color = Colors.red.withOpacity(0.7);
  final Paint _newTagRectPaint = Paint()..color = Colors.green.withOpacity(0.7);

  // Constructor
  WaveformPainter({
    required this.waveformData,
    required this.playbackProgress,
    this.dragProgress,
    this.activeColor = Colors.blue,
    this.inactiveColor = Colors.grey,
    this.tagPosition,
    this.tags = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    // Keep the optimized paint objects
    final wavePaint =
        Paint()
          ..color = inactiveColor
          ..strokeWidth =
              2.5 // Adjusted stroke width slightly
          ..strokeCap =
              StrokeCap.square; // Use round caps for potentially better look

    final playedPaint =
        Paint()
          ..color = activeColor
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.square;

    final centerY = size.height / 2;
    final maxAmplitude =
        size.height * 0.4; // Slightly increase amplitude visibility

    // Keep the downsampling logic
    _updateDownsampledData(size);
    final dataToRender = _downsampledData!;
    if (dataToRender.isEmpty) return; // Check after downsampling

    final spacing =
        size.width /
        math.max(1, dataToRender.length - 1); // Ensure divisor is at least 1

    final progressPosition = (dragProgress ?? playbackProgress).clamp(0.0, 1.0);
    // Calculate split point based on the number of *segments* if using length-1 for spacing,
    // or based on *points* if using length. Let's stick to points for simplicity.
    final splitIndex = (progressPosition * dataToRender.length).floor();

    // Draw baseline first
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      _baselinePaint,
    );

    // *** Revert to canvas.drawLine ***
    for (int i = 0; i < dataToRender.length; i++) {
      final x = i * spacing;
      // Use the downsampled value, ensure it's clamped
      final amplitude = dataToRender[i].clamp(0.0, 1.0) * maxAmplitude;
      final topY = centerY - amplitude;
      final bottomY = centerY + amplitude;

      // Determine paint based on split index
      final currentPaint = i < splitIndex ? playedPaint : wavePaint;

      // Draw the vertical line representing the amplitude for this point
      canvas.drawLine(Offset(x, topY), Offset(x, bottomY), currentPaint);
    }
    // *** End reverted drawing logic ***

    // Draw progress line (keep this helper)
    _drawProgressLine(canvas, size, progressPosition);

    // Draw tags (keep this helper)
    _drawTags(canvas, size);

    // Draw current tag position (keep this helper)
    _drawCurrentTagPosition(canvas, size);
  }

  void _updateDownsampledData(Size size) {
    // Check if we need to recompute the downsampled data
    if (_downsampledData == null ||
        _lastSize == null ||
        _lastSize!.width != size.width) {
      _lastSize = size;

      // Calculate target number of points (1 point per 2 pixels)
      final targetPoints = (size.width / 2).ceil();

      // Downsample the data
      _downsampledData = _downsampleWaveform(waveformData, targetPoints);
    }
  }

  // Downsample waveform data to the target number of points
  // Uses max value in each segment to preserve peaks
  List<double> _downsampleWaveform(List<double> sourceData, int targetPoints) {
    if (sourceData.isEmpty) return [0.0];
    if (sourceData.length <= targetPoints) return List.from(sourceData);

    List<double> result = List.filled(targetPoints, 0.0);
    double ratio = sourceData.length / targetPoints;

    for (int i = 0; i < targetPoints; i++) {
      int start = (i * ratio).floor();
      int end = math.min(((i + 1) * ratio).floor(), sourceData.length);

      // Find maximum amplitude in this segment
      double maxValue = 0.0;
      for (int j = start; j < end; j++) {
        maxValue = math.max(maxValue, sourceData[j].abs());
      }

      result[i] = maxValue;
    }

    return result;
  }

  // void _createWaveformPaths(
  //   Size size,
  //   double centerY,
  //   double maxAmplitude,
  //   double spacing,
  //   int splitIndex,
  //   List<double> dataToRender,
  // ) {
  //   _waveformPathActive = Path();
  //   _waveformPathInactive = Path();

  //   for (int i = 0; i < dataToRender.length; i++) {
  //     final x = i * spacing;
  //     final amplitude = dataToRender[i].clamp(0.0, 1.0) * maxAmplitude;
  //     final topY = centerY - amplitude;
  //     final bottomY = centerY + amplitude;

  //     final currentPath =
  //         i <= splitIndex ? _waveformPathActive! : _waveformPathInactive!;

  //     // Problem Area: Creates many disconnected lines
  //     currentPath.moveTo(x, centerY); // Move to center
  //     currentPath.lineTo(x, topY); // Draw up
  //     currentPath.moveTo(x, centerY); // Move back to center
  //     currentPath.lineTo(x, bottomY); // Draw down
  //   }
  // }

  void _drawProgressLine(Canvas canvas, Size size, double progressPosition) {
    final progressX = progressPosition * size.width;

    if (dragProgress == null) {
      // Draw playback progress line
      canvas.drawLine(
        Offset(progressX, 0),
        Offset(progressX, size.height),
        _playbackLinePaint,
      );
    } else {
      // Draw scrubbing line
      canvas.drawLine(
        Offset(progressX, 0),
        Offset(progressX, size.height),
        _scrubPaint,
      );
    }
  }

  void _drawTags(Canvas canvas, Size size) {
    for (final tag in tags) {
      final x = tag.position.clamp(0.0, 1.0) * size.width;

      // Draw tag line
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _tagPaint);

      // Draw tag rectangle
      final tagRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 12, 0, 24, 20),
        const Radius.circular(4),
      );
      canvas.drawRRect(tagRect, _tagRectPaint);

      // Draw tag text
      _drawTagText(canvas, x, (tags.indexOf(tag) + 1).toString());
    }
  }

  void _drawCurrentTagPosition(Canvas canvas, Size size) {
    if (tagPosition != null) {
      final x = tagPosition!.clamp(0.0, 1.0) * size.width;

      // Draw tag line
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _currentTagPaint);

      // Draw tag rectangle
      final tagRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 12, 0, 24, 20),
        const Radius.circular(4),
      );
      canvas.drawRRect(tagRect, _newTagRectPaint);

      // Draw tag text
      _drawTagText(canvas, x, "+");
    }
  }

  void _drawTagText(Canvas canvas, double x, String text) {
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    textPainter.paint(canvas, Offset(x - textPainter.width / 2, 4));
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    // Check only critical properties that would affect appearance
    // Note: we don't need to check waveformData length anymore as we're using downsampled data
    return oldDelegate.playbackProgress != playbackProgress ||
        oldDelegate.dragProgress != dragProgress ||
        oldDelegate.tagPosition != tagPosition ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.tags.length != tags.length ||
        _didTagsChange(oldDelegate.tags) ||
        _didWaveformDataChange(oldDelegate.waveformData);
  }

  // More efficient tag change detection
  bool _didTagsChange(List<AudioTag> oldTags) {
    if (tags.length != oldTags.length) return true;

    for (int i = 0; i < tags.length; i++) {
      if (tags[i].position != oldTags[i].position) {
        return true;
      }
    }

    return false;
  }

  // Check if waveform data has changed significantly
  // Only checks a sample of points for performance
  bool _didWaveformDataChange(List<double> oldData) {
    if (waveformData.length != oldData.length) return true;

    // Sample check - only check a few points
    // Using prime number steps to get better coverage
    const sampleStep = 17;
    for (int i = 0; i < waveformData.length; i += sampleStep) {
      if (i < waveformData.length && i < oldData.length) {
        if ((waveformData[i] - oldData[i]).abs() > 0.01) {
          return true;
        }
      }
    }

    return false;
  }
}
