// profiler.dart
import 'dart:developer' as developer;

class PerformanceProfiler {
  static final Map<String, DateTime> _startTimes = {};
  static final Map<String, List<Duration>> _measurements = {};

  // Start timing an operation with a specific label
  static void start(String label) {
    _startTimes[label] = DateTime.now();
    developer.log('⏱️ START: $label', name: 'Profiler');
  }

  // End timing and log the duration
  static Duration end(String label) {
    final startTime = _startTimes[label];
    if (startTime == null) {
      developer.log('⚠️ Cannot end timing for "$label": no start time recorded', 
          name: 'Profiler');
      return Duration.zero;
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    
    if (!_measurements.containsKey(label)) {
      _measurements[label] = [];
    }
    _measurements[label]!.add(duration);
    
    developer.log('⏱️ END: $label - took ${duration.inMilliseconds}ms', 
        name: 'Profiler');
    return duration;
  }

  // Get average time for a specific operation
  static Duration getAverageTime(String label) {
    final measurements = _measurements[label];
    if (measurements == null || measurements.isEmpty) {
      return Duration.zero;
    }
    
    int totalMs = measurements.fold(0, 
        (sum, duration) => sum + duration.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ measurements.length);
  }

  // Log all recorded measurements
  static void logAllMeasurements() {
    developer.log('📊 Performance Measurements:', name: 'Profiler');
    _measurements.forEach((label, durations) {
      int totalMs = durations.fold(0, 
          (sum, duration) => sum + duration.inMilliseconds);
      double avgMs = totalMs / durations.length;
      
      developer.log('  - $label: ${durations.length} calls, avg ${avgMs.toStringAsFixed(1)}ms, '
          'min ${durations.map((d) => d.inMilliseconds).reduce((a, b) => a < b ? a : b)}ms, '
          'max ${durations.map((d) => d.inMilliseconds).reduce((a, b) => a > b ? a : b)}ms',
          name: 'Profiler');
    });
  }

  // Clear all measurements
  static void reset() {
    _startTimes.clear();
    _measurements.clear();
    developer.log('🧹 Performance measurements reset', name: 'Profiler');
  }
}