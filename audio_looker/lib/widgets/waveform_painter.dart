import 'package:flutter/material.dart';
import 'package:audio_looker/services/audio_service.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double playbackProgress;
  final double? dragProgress;
  final Color activeColor;
  final Color inactiveColor;
  final List<TimeMarker> markers;
  // REMOVED: hoveredMarker parameter
  final Offset? hoverPosition; // ADDED: Current hover position from parent

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
  final Paint _hoveredMarkerPaint =
      Paint()
        ..color = Colors.purple
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
  // ADDED: Paint for label background
  final Paint _labelBackgroundPaint = Paint()..style = PaintingStyle.fill;

  // Constructor updated
  WaveformPainter({
    required this.waveformData,
    required this.playbackProgress,
    this.dragProgress,
    this.activeColor = Colors.blue,
    this.inactiveColor = Colors.grey,
    this.markers = const [],
    // REMOVED: this.hoveredMarker,
    this.hoverPosition, // ADDED
  });

  // --- Define Layout Constants (adjust as needed) ---
  static const double playIconSize = 18.0;
  static const double markerBarWidth = 2.0; // Width of the main vertical bar
  static const double hoverBarWidth = 3.0; // Width when hovered
  static const double labelPaddingHorizontal = 6.0;
  static const double labelPaddingVertical = 3.0;
  static const double labelFontSize = 11.0;
  static const double labelMaxWidth = 100.0;
  static const double elementSpacing = 4.0; // Space between icon, bar, label bg
  static const double hoverHitTolerance =
      10.0; // Pixel tolerance for hover detection

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    // ... (Optimized paints, downsampling, baseline drawing - remain the same) ...
    final wavePaint =
        Paint()
          ..color = inactiveColor
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.square;
    final playedPaint =
        Paint()
          ..color = activeColor
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.square;
    final centerY = size.height / 2;
    final maxAmplitude = size.height * 0.4;

    _updateDownsampledData(size);
    final dataToRender = _downsampledData!;
    if (dataToRender.isEmpty) return;

    final spacing = size.width / math.max(1, dataToRender.length - 1);
    final progressPosition = (dragProgress ?? playbackProgress).clamp(0.0, 1.0);
    final splitIndex = (progressPosition * dataToRender.length).floor();

    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      _baselinePaint,
    );

    for (int i = 0; i < dataToRender.length; i++) {
      final x = i * spacing;
      final amplitude = dataToRender[i].clamp(0.0, 1.0) * maxAmplitude;
      final topY = centerY - amplitude;
      final bottomY = centerY + amplitude;
      final currentPaint = i < splitIndex ? playedPaint : wavePaint;
      canvas.drawLine(Offset(x, topY), Offset(x, bottomY), currentPaint);
    }
    // --- End Waveform Drawing ---

    // --- Determine Hovered Marker ---
    TimeMarker? currentlyHoveredMarker;
    if (hoverPosition != null) {
      for (final marker in markers) {
        final markerX = marker.position.clamp(0.0, 1.0) * size.width;
        // Check if hover position is horizontally close to the marker line
        if ((hoverPosition!.dx - markerX).abs() < hoverHitTolerance) {
          currentlyHoveredMarker = marker;
          break; // Found the first hovered marker
        }
      }
    }
    // --- End Determine Hovered Marker ---

    // --- Draw Markers (with hover effects) ---
    _drawMarkers(canvas, size, 10, currentlyHoveredMarker);

    // --- Draw Progress Line ---
    _drawProgressLine(canvas, size, progressPosition);
  }

  void _drawMarkers(
    Canvas canvas,
    Size size,
    double centerY,
    TimeMarker? currentlyHoveredMarker,
  ) {
    for (final marker in markers) {
      final x = marker.position.clamp(0.0, 1.0) * size.width;
      final bool isHovered = marker == currentlyHoveredMarker;

      final Paint currentBarPaint =
          isHovered ? _hoveredMarkerPaint : _markerPaint;
      final double currentBarW = isHovered ? hoverBarWidth : markerBarWidth;

      // --- Prepare Label ---
      final labelStyle = TextStyle(
        color: isHovered ? Colors.white : Colors.black87, // Adjust colors
        fontSize: labelFontSize,
        fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
      );
      final textSpan = TextSpan(text: marker.label, style: labelStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        maxLines: 1,
        ellipsis: '...',
      );
      textPainter.layout(maxWidth: labelMaxWidth);
      final labelHeight = textPainter.height;
      final labelWidth = textPainter.width;
      final backgroundHeight = labelHeight + (labelPaddingVertical * 2);

      // --- Calculate Layout ---
      // Start drawing from the left edge of the play icon (if hovered)
      double currentX = x;
      if (isHovered) {
        currentX -=
            (playIconSize +
                elementSpacing); // Start left of bar for hover layout
      } else {
        currentX +=
            currentBarW / 2 +
            elementSpacing; // Start right of bar for non-hover layout
      }
      double playIconLeft = 0; // Keep track for hit testing if needed

      // --- Draw Elements ---

      // 1. Draw Play Icon (if hovered)
      if (isHovered) {
        playIconLeft = currentX;
        _drawIcon(
          canvas,
          Icons.play_arrow,
          Offset(playIconLeft, centerY - playIconSize / 2),
          playIconSize,
          currentBarPaint.color.withOpacity(0.85),
        );
        currentX += playIconSize + elementSpacing;
      }

      // 2. Draw Marker Bar
      // Center the bar at the original 'x' position
      final barLeft = x - currentBarW / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), currentBarPaint);
      // We'll draw background relative to label position later, but bar is at 'x'

      // 3. Calculate Label & Background Position
      // For non-hover, label starts right of bar 'x'. For hover, it starts right of icon
      double labelBgLeft;
      if (isHovered) {
        labelBgLeft = x + currentBarW / 2 + elementSpacing;
      } else {
        // Non-hovered: label starts right of the bar at 'x'
        labelBgLeft = x + currentBarW / 2 + elementSpacing;
      }
      final labelBgTop = centerY - backgroundHeight / 2;
      final labelBgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          labelBgLeft,
          labelBgTop,
          labelWidth + (labelPaddingHorizontal * 2),
          backgroundHeight,
        ),
        const Radius.circular(4),
      );

      // 4. Draw Label Background
      // Use a color matching the bar, potentially with some opacity
      _labelBackgroundPaint.color = currentBarPaint.color.withOpacity(
        0.85,
      ); // Match bar color
      canvas.drawRRect(labelBgRect, _labelBackgroundPaint);

      // 5. Draw Label Text (on top of background)
      final textOffsetX = labelBgLeft + labelPaddingHorizontal;
      final textOffsetY =
          centerY - labelHeight / 2; // Use calculated labelHeight
      textPainter.paint(canvas, Offset(textOffsetX, textOffsetY));
    }
  }

  void _paintMarkerLabel(
    Canvas canvas,
    Size size,
    double x,
    double centerY,
    String text,
    bool isHovered,
  ) {
    final labelStyle = TextStyle(
      // Use a less prominent color for the non-hovered label
      color: Colors.grey[700], // Or adjust color as needed
      fontSize: 11, // Smaller font size for the persistent label
      fontWeight: FontWeight.normal,
      // Consider adding a subtle background or outline for readability if needed
      // background: Paint()..color = Colors.white.withOpacity(0.7),
    );

    final textSpan = TextSpan(text: text, style: labelStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      maxLines: 1, // Ensure label stays on one line
      ellipsis: '...', // Add ellipsis if text overflows
    );

    textPainter.layout(
      maxWidth: 100,
    ); // Limit label width to prevent excessive overlap

    // Position the text to the right of the marker line
    final double textOffsetX = x + 6; // Offset from the line 'x'
    // Center the text vertically
    final double textOffsetY = centerY - (textPainter.height / 2);

    // Ensure text doesn't draw off the right edge of the canvas
    if (textOffsetX + textPainter.width <= size.width) {
      textPainter.paint(canvas, Offset(textOffsetX, textOffsetY));
    } else {
      // Optional: Handle cases where text might go off-screen
      // Could draw aligned to the right edge, or just not draw if no space
      // Example: Draw aligned right if it would overflow
      // textPainter.paint(canvas, Offset(size.width - textPainter.width - 2, textOffsetY));
    }
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

  // --- Helper to Draw Icon ---
  void _drawIcon(
    Canvas canvas,
    IconData icon,
    Offset offset,
    double size,
    Color color,
  ) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(fontFamily: icon.fontFamily, fontSize: size),
          )
          ..pushStyle(ui.TextStyle(color: color))
          ..addText(String.fromCharCode(icon.codePoint));
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: size));
    canvas.drawParagraph(paragraph, offset);
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    // Include hoverPosition in comparison
    return oldDelegate.playbackProgress != playbackProgress ||
        oldDelegate.dragProgress != dragProgress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        // REMOVED: oldDelegate.hoveredMarker != hoveredMarker ||
        oldDelegate.hoverPosition != hoverPosition || // ADDED
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
