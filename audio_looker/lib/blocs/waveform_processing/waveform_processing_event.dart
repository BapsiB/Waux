// lib/blocs/waveform_processing/waveform_processing_event.dart

import 'package:equatable/equatable.dart';

abstract class WaveformProcessingEvent extends Equatable {
  const WaveformProcessingEvent();

  @override
  List<Object> get props => [];
}

// --- Public Events ---

/// Dispatched when a new batch of tracks needs waveform processing.
class WaveformProcessingBatchStarted extends WaveformProcessingEvent {
  final List<String> trackIds; // Or List<Track> if needed by the service later
  final int totalTracks;

  const WaveformProcessingBatchStarted({
    required this.trackIds,
    required this.totalTracks,
  });

  @override
  List<Object> get props => [trackIds, totalTracks];
}

/// Dispatched when the current batch processing is complete.
class WaveformProcessingBatchFinished extends WaveformProcessingEvent {}

// --- Internal Events (Now Public for BLoC usage) ---

/// Event to update overall progress (still typically added internally by BLoC).
class WaveformProcessingProgressUpdated extends WaveformProcessingEvent {
  // Renamed
  final int processedTracks;
  final int totalTracks;

  const WaveformProcessingProgressUpdated(
    this.processedTracks,
    this.totalTracks,
  );

  @override
  List<Object> get props => [processedTracks, totalTracks];
}

/// Event when a single track's waveform is successfully processed (added internally by BLoC).
class WaveformProcessingTrackCompleted extends WaveformProcessingEvent {
  // Renamed
  final String trackId;
  final List<double> waveformData; // Use List<double> or appropriate type

  const WaveformProcessingTrackCompleted(this.trackId, this.waveformData);

  @override
  List<Object> get props => [trackId, waveformData];
}

/// Event when processing fails for a single track (added internally by BLoC).
class WaveformProcessingTrackFailed extends WaveformProcessingEvent {
  // Renamed
  final String trackId;
  final String error;

  const WaveformProcessingTrackFailed(this.trackId, this.error);

  @override
  List<Object> get props => [trackId, error];
}
