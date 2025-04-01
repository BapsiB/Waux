import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final Color activeColor;
  final Color inactiveColor;
  final double playbackProgress;
  
  WaveformPainter({
    required this.waveformData,
    required this.activeColor,
    required this.inactiveColor,
    required this.playbackProgress,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;
    
    final paint = Paint()
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    
    final centerY = size.height / 2;
    final width = size.width;
    final barWidth = width / waveformData.length;
    final progressX = width * playbackProgress;
    
    // Draw each bar of the waveform
    for (int i = 0; i < waveformData.length; i++) {
      final x = i * barWidth;
      final amplitude = waveformData[i];
      
      // Scale the amplitude to fit within the available height
      // Reserve some padding at top and bottom
      final maxHeight = size.height * 0.8;
      final barHeight = amplitude * maxHeight;
      
      // Determine if this bar is before or after the playback position
      paint.color = x < progressX ? activeColor : inactiveColor;
      
      // Draw the bar as a vertical line
      canvas.drawLine(
        Offset(x + barWidth / 2, centerY - barHeight / 2),
        Offset(x + barWidth / 2, centerY + barHeight / 2),
        paint,
      );
    }
    
    // Draw playback position line
    paint
      ..color = Colors.white
      ..strokeWidth = 2.0;
    
    canvas.drawLine(
      Offset(progressX, 0),
      Offset(progressX, size.height),
      paint,
    );
    
    // Draw a handle at the playback position for better visibility
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(progressX, size.height / 2),
      5.0,
      paint,
    );
  }
  
  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.playbackProgress != playbackProgress ||
        oldDelegate.waveformData != waveformData ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}