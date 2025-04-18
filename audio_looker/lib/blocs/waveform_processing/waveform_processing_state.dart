import 'package:equatable/equatable.dart';

abstract class WaveformProcessingState extends Equatable {
  const WaveformProcessingState();

  @override
  List<Object> get props => [];
}

class WaveformProcessingInitial extends WaveformProcessingState {}

class WaveformProcessingInProgress extends WaveformProcessingState {
  final int processedTracks;
  final int totalTracks;

  const WaveformProcessingInProgress(this.processedTracks, this.totalTracks);

  double get progress => totalTracks > 0 ? processedTracks / totalTracks : 0.0;

  @override
  List<Object> get props => [processedTracks, totalTracks];
}

class WaveformProcessingComplete extends WaveformProcessingState {
  // Optional: Could add final counts if needed
  // final int totalProcessed;
  // final int totalFailed;
  // const WaveformProcessingComplete(this.totalProcessed, this.totalFailed);
}

// Optional: For handling overall batch errors, though per-track errors might be sufficient
// class WaveformProcessingFailure extends WaveformProcessingState {
//   final String message;
//   const WaveformProcessingFailure(this.message);
//   @override
//   List<Object> get props => [message];
// }
