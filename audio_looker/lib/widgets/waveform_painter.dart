import 'package:flutter/material.dart';
import 'package:audio_looker/services/audio_service.dart';

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double playbackProgress;
  final Color activeColor;
  final Color inactiveColor;
  final double? tagPosition;
  final List<AudioTag> tags;

  WaveformPainter({
    required this.waveformData,
    required this.playbackProgress,
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
    final spacing = size.width / (waveformData.length - 1);
    final centerY = size.height / 2;
    final maxAmplitude =
        size.height * 0.35; // Max waveform height (35% of total height)

    // Draw the waveform
    for (int i = 0; i < waveformData.length - 1; i++) {
      final x = i * spacing;
      final y1 = centerY - waveformData[i] * maxAmplitude;

      final x2 = (i + 1) * spacing;
      final y2 = centerY - waveformData[i + 1] * maxAmplitude;

      // Draw baseline (middle line)
      canvas.drawLine(
        Offset(x, centerY),
        Offset(x2, centerY),
        Paint()
          ..color = Colors.grey[300]!
          ..strokeWidth = 1,
      );

      // Draw upward part of waveform
      canvas.drawLine(
        Offset(x, centerY),
        Offset(x, y1),
        i / waveformData.length < playbackProgress ? playedPaint : wavePaint,
      );

      // Draw downward part (mirrored)
      canvas.drawLine(
        Offset(x, centerY),
        Offset(x, centerY + (centerY - y1)),
        i / waveformData.length < playbackProgress ? playedPaint : wavePaint,
      );
    }

    // Draw the progress line
    final progressX = playbackProgress * size.width;
    canvas.drawLine(
      Offset(progressX, 0),
      Offset(progressX, size.height),
      Paint()
        ..color = Colors.red
        ..strokeWidth = 2,
    );

    // Draw tag markers
    for (final tag in tags) {
      final x = tag.position * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tagPaint);

      // Draw tag indicator
      final tagRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 12, 0, 24, 20),
        const Radius.circular(4),
      );
      canvas.drawRRect(tagRect, Paint()..color = Colors.red);

      // Draw tag text
      final textSpan = TextSpan(
        text: (tags.indexOf(tag) + 1).toString(),
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
      final x = tagPosition! * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), currentTagPaint);

      // Draw tag indicator
      final tagRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 12, 0, 24, 20),
        const Radius.circular(4),
      );
      canvas.drawRRect(tagRect, Paint()..color = Colors.green);

      // Draw tag text
      final textSpan = TextSpan(
        text: "+",
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
    return oldDelegate.playbackProgress != playbackProgress ||
        oldDelegate.tagPosition != tagPosition ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.tags.length != tags.length;
  }
}
