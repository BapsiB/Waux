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

// --- Internal Events (used by the Bloc listening to the Service) ---

/// Internal event to update overall progress.
class _WaveformProcessingProgressUpdated extends WaveformProcessingEvent {
  final int processedTracks;
  final int totalTracks;

  const _WaveformProcessingProgressUpdated(
    this.processedTracks,
    this.totalTracks,
  );

  @override
  List<Object> get props => [processedTracks, totalTracks];
}

/// Internal event when a single track's waveform is successfully processed.
class _WaveformProcessingTrackCompleted extends WaveformProcessingEvent {
  final String trackId;
  final List<double> waveformData; // Use List<double> or appropriate type

  const _WaveformProcessingTrackCompleted(this.trackId, this.waveformData);

  @override
  List<Object> get props => [trackId, waveformData];
}

/// Internal event when processing fails for a single track.
class _WaveformProcessingTrackFailed extends WaveformProcessingEvent {
  final String trackId;
  final String error;

  const _WaveformProcessingTrackFailed(this.trackId, this.error);

  @override
  List<Object> get props => [trackId, error];
}
