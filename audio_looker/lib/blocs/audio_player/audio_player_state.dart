// lib/blocs/audio_player/audio_player_state.dart

part of 'audio_player_bloc.dart'; // Use part of directive

abstract class AudioPlayerState extends Equatable {
  const AudioPlayerState();

  @override
  List<Object?> get props => [];
}

class AudioPlayerInitial extends AudioPlayerState {}

class AudioPlayerLoading extends AudioPlayerState {
  final String? loadingSource; // Optionally track which source is loading

  const AudioPlayerLoading({this.loadingSource});

  @override
  List<Object?> get props => [loadingSource];
}

class AudioPlayerLoaded extends AudioPlayerState {
  final String currentSource; // Make source non-nullable when loaded
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<double>? waveformData;
  // *** Renamed tags to markers and use TimeMarker ***
  final List<TimeMarker> markers;

  const AudioPlayerLoaded({
    required this.currentSource,
    required this.isPlaying,
    required this.position,
    required this.duration,
    this.waveformData,
    // *** Use markers ***
    this.markers = const [],
  });

  @override
  List<Object?> get props => [
    currentSource,
    isPlaying,
    position,
    duration,
    waveformData,
    // *** Use markers ***
    markers,
  ];

  AudioPlayerLoaded copyWith({
    String? currentSource,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    List<double>? waveformData,
    bool clearWaveform = false,
    // *** Renamed tags to markers and use TimeMarker ***
    List<TimeMarker>? markers,
  }) {
    return AudioPlayerLoaded(
      currentSource: currentSource ?? this.currentSource,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      waveformData: clearWaveform ? null : (waveformData ?? this.waveformData),
      // *** Use markers ***
      markers: markers ?? this.markers,
    );
  }
}

class AudioPlayerError extends AudioPlayerState {
  final String message;
  final String? source; // Source that caused the error

  const AudioPlayerError(this.message, {this.source});

  @override
  List<Object?> get props => [message, source];
}
