import 'package:flutter/material.dart';
import 'package:audio_looker/services/audio_service.dart'; // Make sure this path is correct
import 'dart:math' as math;
import 'dart:ui' as ui; // Required for canvas.drawParagraph

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double playbackProgress;
  final double? dragProgress;
  final Color activeColor;
  final Color inactiveColor;
  final List<TimeMarker> markers;
  final Offset? hoverPosition; // Current hover position from parent widget

  // Cache & Paints
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
  final Paint _labelBackgroundPaint = Paint()..style = PaintingStyle.fill;

  // --- Layout Constants ---
  static const double playIconSize = 18.0;
  static const double markerBarWidth = 2.0;
  static const double hoverBarWidth = 3.0;
  static const double labelPaddingHorizontal = 6.0;
  static const double labelPaddingVertical = 3.0;
  static const double labelFontSize = 11.0;
  static const double labelMaxWidth = 100.0;
  static const double elementSpacing = 4.0;
  static const double labelTopOffset =
      2.0; // How far from the top edge the label appears
  static const double hoverVerticalTolerance = labelPaddingVertical + 8.0;
  static const double hoverHitTolerance = 10.0;

  // Constructor
  WaveformPainter({
    required this.waveformData,
    required this.playbackProgress,
    this.dragProgress,
    this.activeColor = Colors.blue,
    this.inactiveColor = Colors.grey,
    this.markers = const [],
    this.hoverPosition,
  });

  // --- Helper to calculate marker layout and bounds ---
  static ({Rect playIconBounds, Rect labelBounds, Rect fullHoverArea})
  calculateMarkerLayout(TimeMarker marker, Size size, bool isHovered) {
    final x = marker.position.clamp(0.0, 1.0) * size.width;
    final double currentBarW = isHovered ? hoverBarWidth : markerBarWidth;

    // Prepare Label Painter
    final labelStyle = TextStyle(
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
    final backgroundWidth = labelWidth + (labelPaddingHorizontal * 2);
    final backgroundHeight = labelHeight + (labelPaddingVertical * 2);

    // Calculate Label & Background Bounds (Right of 'x', near the top)
    // MODIFIED: Position label to the right of the bar
    final double labelBgLeft = x + currentBarW / 2 + elementSpacing;
    final double labelBgTop = labelTopOffset; // Keep near the top
    final labelBounds = Rect.fromLTWH(
      labelBgLeft,
      labelBgTop,
      backgroundWidth,
      backgroundHeight,
    );

    // Calculate Play Icon Bounds (Left of 'x', vertically aligned with label)
    Rect playIconBounds = Rect.zero;
    if (isHovered) {
      final double iconLeft =
          x - (currentBarW / 2 + elementSpacing + playIconSize);
      final double iconTop = labelBgTop + (backgroundHeight - playIconSize) / 2;
      playIconBounds = Rect.fromLTWH(
        iconLeft,
        iconTop,
        playIconSize,
        playIconSize,
      );
    }

    // Calculate Full Hover Area
    Rect fullHoverArea = labelBounds;
    if (isHovered) {
      fullHoverArea = playIconBounds.expandToInclude(labelBounds);
    }
    // Expand slightly for easier hover targeting
    fullHoverArea = Rect.fromLTRB(
      fullHoverArea.left - elementSpacing,
      math.max(0, fullHoverArea.top - labelPaddingVertical),
      fullHoverArea.right + elementSpacing,
      math.min(size.height, fullHoverArea.bottom + labelPaddingVertical),
    );

    return (
      playIconBounds: playIconBounds,
      labelBounds: labelBounds,
      fullHoverArea: fullHoverArea,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    // --- Setup ---
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

    // --- Draw Baseline & Waveform ---
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

    // --- Determine Hovered Marker ---
    TimeMarker? currentlyHoveredMarker;
    if (hoverPosition != null) {
      for (final marker in markers.reversed) {
        final hoverLayout = calculateMarkerLayout(marker, size, true);
        if (hoverLayout.fullHoverArea.contains(hoverPosition!)) {
          currentlyHoveredMarker = marker;
          break;
        }
      }
      // Fallback proximity check
      if (currentlyHoveredMarker == null) {
        for (final marker in markers) {
          final markerX = marker.position.clamp(0.0, 1.0) * size.width;
          if ((hoverPosition!.dx - markerX).abs() < hoverHitTolerance &&
              hoverPosition!.dy >= 0 &&
              hoverPosition!.dy <= size.height) {
            currentlyHoveredMarker = marker;
            break;
          }
        }
      }
    }
    // --- End Determine Hovered Marker ---

    // --- Draw Markers ---
    _drawMarkers(canvas, size, currentlyHoveredMarker);

    // --- Draw Progress Line ---
    _drawProgressLine(canvas, size, progressPosition);
  }

  // --- Draw Markers Implementation ---
  void _drawMarkers(
    Canvas canvas,
    Size size,
    TimeMarker? currentlyHoveredMarker,
  ) {
    for (final marker in markers) {
      final x = marker.position.clamp(0.0, 1.0) * size.width;
      final bool isHovered = marker == currentlyHoveredMarker;

      final Paint currentBarPaint =
          isHovered ? _hoveredMarkerPaint : _markerPaint;
      // final double currentBarW = isHovered ? hoverBarWidth : markerBarWidth; // Not needed directly for drawing now

      // Calculate layout using the static helper
      final layout = calculateMarkerLayout(marker, size, isHovered);

      // --- Draw Elements ---

      // 1. Draw Marker Bar
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), currentBarPaint);

      // 2. Draw Label Background (On top, to the right)
      _labelBackgroundPaint.color = currentBarPaint.color.withOpacity(0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(layout.labelBounds, const Radius.circular(4)),
        _labelBackgroundPaint,
      );

      // 3. Draw Label Text
      final labelStyle = TextStyle(
        color: isHovered ? Colors.white : Colors.black87,
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
      final textOffsetX = layout.labelBounds.left + labelPaddingHorizontal;
      final textOffsetY =
          layout.labelBounds.top +
          (layout.labelBounds.height - textPainter.height) / 2;
      textPainter.paint(canvas, Offset(textOffsetX, textOffsetY));

      // 4. Draw Play Icon (if hovered, to the left)
      if (isHovered) {
        _drawIcon(
          canvas,
          Icons.play_arrow,
          layout.playIconBounds.topLeft,
          playIconSize,
          currentBarPaint.color.withOpacity(0.85),
        );
      }
    }
  }

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

  // --- Data Processing and Helpers ---

  void _updateDownsampledData(Size size) {
    if (_downsampledData == null ||
        _lastSize == null ||
        _lastSize!.width != size.width) {
      _lastSize = size;
      final targetPoints = (size.width / 2).ceil();
      _downsampledData = _downsampleWaveform(waveformData, targetPoints);
    }
  }

  List<double> _downsampleWaveform(List<double> sourceData, int targetPoints) {
    if (sourceData.isEmpty) return [0.0];
    if (targetPoints <= 0) return [0.0];
    if (sourceData.length <= targetPoints) return List.from(sourceData);

    List<double> result = List.filled(targetPoints, 0.0);
    double ratio = sourceData.length / targetPoints;

    for (int i = 0; i < targetPoints; i++) {
      int start = (i * ratio).floor();
      int end = math.min(((i + 1) * ratio).floor(), sourceData.length);
      if (start >= end) {
        if (start < sourceData.length)
          result[i] = sourceData[start].abs();
        else
          result[i] = 0.0;
        continue;
      }
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
    final paintToUse =
        (dragProgress == null) ? _playbackLinePaint : _scrubPaint;
    canvas.drawLine(
      Offset(progressX, 0),
      Offset(progressX, size.height),
      paintToUse,
    );
  }

  // --- shouldRepaint ---
  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.playbackProgress != playbackProgress ||
        oldDelegate.dragProgress != dragProgress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.hoverPosition != hoverPosition ||
        !listEquals(oldDelegate.markers, markers) ||
        _didWaveformDataChange(oldDelegate.waveformData);
  }

  // --- List Equality Helper ---
  bool listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    if (identical(a, b)) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // --- Waveform Data Change Detection Helper ---
  bool _didWaveformDataChange(List<double> oldData) {
    if (waveformData.length != oldData.length) return true;
    if (waveformData.isEmpty) return false;

    const sampleStep = 17;
    for (int i = 0; i < waveformData.length; i += sampleStep) {
      if (i < oldData.length) {
        if ((waveformData[i] - oldData[i]).abs() > 0.001) return true;
      } else {
        return true;
      }
    }
    if ((waveformData.last - oldData.last).abs() > 0.001) return true;
    return false;
  }
} // End WaveformPainter class
