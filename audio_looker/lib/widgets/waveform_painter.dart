import 'package:flutter/material.dart';
import 'package:audio_looker/services/audio_service.dart'; // Assuming AudioTag is here or imported

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double playbackProgress;
  final double? dragProgress; // Represents drag position (0.0 to 1.0)
  final Color activeColor;
  final Color inactiveColor;
  final double? tagPosition;
  final List<AudioTag> tags;

  WaveformPainter({
    required this.waveformData,
    required this.playbackProgress,
    this.dragProgress, // Include in constructor
    this.activeColor = Colors.blue,
    this.inactiveColor = Colors.grey,
    this.tagPosition,
    this.tags = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Waveform paint setup
    final wavePaint =
        Paint()
          ..color = inactiveColor
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

    // Played part paint setup
    final playedPaint =
        Paint()
          ..color = activeColor
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

    // Scrubbing line paint setup (for drag visualization)
    final scrubPaint =
        Paint()
          ..color =
              Colors
                  .orangeAccent // Or another distinct color
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;

    // Tag markers paint
    final tagPaint =
        Paint()
          ..color = Colors.red
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;

    // Current tag position paint (when adding a new tag)
    final currentTagPaint =
        Paint()
          ..color = Colors.green
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;

    // Calculate spacing
    if (waveformData.isEmpty) return; // Prevent division by zero if empty

    final spacing = size.width / (waveformData.length - 1);
    final centerY = size.height / 2;
    final maxAmplitude =
        size.height * 0.35; // Max waveform height (35% of total height)

    // --- Draw the waveform bars ---
    for (int i = 0; i < waveformData.length - 1; i++) {
      final x = i * spacing;
      final amplitude = waveformData[i].clamp(0.0, 1.0);
      final y1 = centerY - amplitude * maxAmplitude;

      final x2 = (i + 1) * spacing;

      // Draw baseline (middle line) - Drawn first so waveform lines are on top
      canvas.drawLine(
        Offset(x, centerY),
        Offset(x2, centerY),
        Paint()
          ..color = Colors.grey[300]!
          ..strokeWidth = 1,
      );

      // Determine paint based on playback progress *or* drag progress if dragging
      final currentProgress =
          dragProgress ?? playbackProgress; // Use drag if available
      final Paint currentPaint =
          i / waveformData.length < currentProgress ? playedPaint : wavePaint;

      // Draw upward part of waveform
      canvas.drawLine(Offset(x, centerY), Offset(x, y1), currentPaint);

      // Draw downward part (mirrored)
      canvas.drawLine(
        Offset(x, centerY),
        Offset(x, centerY + (centerY - y1)), // Mirror the amplitude
        currentPaint,
      );
    }

    // --- Draw Progress/Scrub Lines ---

    // Draw the regular playback progress line (red) *ONLY* if NOT dragging
    if (dragProgress == null) {
      final progressX = playbackProgress.clamp(0.0, 1.0) * size.width;
      canvas.drawLine(
        Offset(progressX, 0),
        Offset(progressX, size.height),
        Paint()
          ..color =
              Colors
                  .red // Playback color
          ..strokeWidth = 2,
      );
    }

    // Draw the scrubbing line (orange) *ONLY* if dragging
    if (dragProgress != null) {
      final dragX = dragProgress!.clamp(0.0, 1.0) * size.width;
      canvas.drawLine(
        Offset(dragX, 0),
        Offset(dragX, size.height),
        scrubPaint, // Use the distinct scrub paint
      );
    }

    // --- Draw Tag Markers (Unaffected by drag state) ---
    for (final tag in tags) {
      final x = tag.position.clamp(0.0, 1.0) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tagPaint);

      // Draw tag indicator (optional visual enhancement)
      final tagRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 12, 0, 24, 20), // Adjust size/position as needed
        const Radius.circular(4),
      );
      canvas.drawRRect(tagRect, Paint()..color = Colors.red.withOpacity(0.7));

      // Draw tag text (e.g., index number)
      final textSpan = TextSpan(
        text: (tags.indexOf(tag) + 1).toString(), // Example: show tag index
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

    // Draw current tag position marker (when adding new tag)
    if (tagPosition != null) {
      final x = tagPosition!.clamp(0.0, 1.0) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), currentTagPaint);

      // Draw tag indicator
      final tagRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 12, 0, 24, 20),
        const Radius.circular(4),
      );
      canvas.drawRRect(tagRect, Paint()..color = Colors.green.withOpacity(0.7));

      // Draw tag text
      final textSpan = TextSpan(
        text: "+", // Indicate adding
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
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    // Check if any relevant property has changed
    return oldDelegate.playbackProgress != playbackProgress ||
        oldDelegate.dragProgress != dragProgress || // Check dragProgress
        oldDelegate.tagPosition != tagPosition ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        // More robust check for list changes
        !listEquals(oldDelegate.waveformData, waveformData) ||
        !listEquals(oldDelegate.tags, tags);
  }
}

// Helper function to compare lists (requires foundation import)
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
