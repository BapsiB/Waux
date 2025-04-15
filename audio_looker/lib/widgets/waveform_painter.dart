import 'package:flutter/material.dart';
import 'package:audio_looker/services/audio_service.dart';
import 'dart:math' as math;

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double playbackProgress;
  final double? dragProgress;
  final Color activeColor;
  final Color inactiveColor;
  final List<TimeMarker> markers;
  // *** ADDED: Hovered marker for highlighting ***
  final TimeMarker? hoveredMarker;

  // Cache & Paints (minor adjustments for hover)
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
  final Paint _markerPaint =
      Paint()
        ..color = Colors.blue
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
  // *** ADDED: Paint for hovered marker ***
  final Paint _hoveredMarkerPaint =
      Paint()
        ..color = Colors.purple
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round; // Thicker, different color
  final Paint _markerRectPaint = Paint()..color = Colors.blue.withOpacity(0.7);
  // *** ADDED: Paint for hovered marker rect ***
  final Paint _hoveredMarkerRectPaint =
      Paint()..color = Colors.purple.withOpacity(0.8);

  // Constructor
  WaveformPainter({
    required this.waveformData,
    required this.playbackProgress,
    this.dragProgress,
    this.activeColor = Colors.blue,
    this.inactiveColor = Colors.grey,
    this.markers = const [],
    this.hoveredMarker,
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

    // Draw progress line (keep this helper)
    _drawProgressLine(canvas, size, progressPosition);

    _drawMarkers(canvas, size);

    // Draw current tag position (keep this helper)
    // _drawCurrentTagPosition(canvas, size);
  }

  void _drawMarkers(Canvas canvas, Size size) {
    for (final marker in markers) {
      final x = marker.position.clamp(0.0, 1.0) * size.width;
      // *** Check if this marker is hovered ***
      final bool isHovered = hoveredMarker == marker;

      // *** Select paint based on hover state ***
      final Paint currentMarkerPaint =
          isHovered ? _hoveredMarkerPaint : _markerPaint;
      final Paint currentRectPaint =
          isHovered ? _hoveredMarkerRectPaint : _markerRectPaint;
      final double rectWidth =
          isHovered ? 28 : 24; // Slightly wider when hovered
      final double rectHeight =
          isHovered ? 22 : 20; // Slightly taller when hovered

      // Draw marker line
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), currentMarkerPaint);

      // Draw marker rectangle
      final markerRect = RRect.fromRectAndRadius(
        // Adjust position based on new width/height to keep it centered
        Rect.fromLTWH(x - rectWidth / 2, 0, rectWidth, rectHeight),
        const Radius.circular(4),
      );
      canvas.drawRRect(markerRect, currentRectPaint);

      // Draw marker text (first character)
      _drawMarkerText(canvas, x, marker.label, isHovered);
    }
  }

  // Updated text drawing to optionally make hovered text bolder
  void _drawMarkerText(Canvas canvas, double x, String text, bool isHovered) {
    final textSpan = TextSpan(
      text:
          text.isNotEmpty
              ? text.characters.first
              : '?', // Show first char or '?'
      style: TextStyle(
        color: Colors.white,
        fontSize: isHovered ? 13 : 12, // Slightly larger when hovered
        fontWeight:
            isHovered
                ? FontWeight.bold
                : FontWeight.normal, // Bolder when hovered
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout();
    // Adjust vertical position slightly to center in rect
    textPainter.paint(
      canvas,
      Offset(x - textPainter.width / 2, isHovered ? 3 : 4),
    );
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

  // void _drawCurrentTagPosition(Canvas canvas, Size size) {
  //   if (tagPosition != null) {
  //     final x = tagPosition!.clamp(0.0, 1.0) * size.width;

  //     // Draw tag line
  //     canvas.drawLine(Offset(x, 0), Offset(x, size.height), _currentTagPaint);

  //     // Draw tag rectangle
  //     final tagRect = RRect.fromRectAndRadius(
  //       Rect.fromLTWH(x - 12, 0, 24, 20),
  //       const Radius.circular(4),
  //     );
  //     canvas.drawRRect(tagRect, _newTagRectPaint);

  //     // Draw tag text
  //     _drawTagText(canvas, x, "+");
  //   }
  // }

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
    // *** Include hoveredMarker in comparison ***
    return oldDelegate.playbackProgress != playbackProgress ||
        oldDelegate.dragProgress != dragProgress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.hoveredMarker !=
            hoveredMarker || // Check if hovered marker changed
        !listEquals(oldDelegate.markers, markers) ||
        _didWaveformDataChange(oldDelegate.waveformData);
  }

  bool listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // // More efficient tag change detection
  // bool _didTagsChange(List<TimeMarker> oldTags) {
  //   if (tags.length != oldTags.length) return true;

  //   for (int i = 0; i < tags.length; i++) {
  //     if (tags[i].position != oldTags[i].position) {
  //       return true;
  //     }
  //   }

  //   return false;
  // }

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
