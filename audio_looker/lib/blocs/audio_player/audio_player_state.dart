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
  final List<TimeMarker> markers;
  final bool isShuffleActive;
  final double volume; // <<< ADDED volume field

  const AudioPlayerLoaded({
    required this.currentSource,
    required this.isPlaying,
    required this.position,
    required this.duration,
    this.waveformData,
    this.markers = const [],
    this.isShuffleActive = false,
    this.volume = 1.0, // <<< ADDED default volume
  });

  @override
  List<Object?> get props => [
    currentSource,
    isPlaying,
    position,
    duration,
    waveformData,
    markers,
    isShuffleActive,
    volume, // <<< ADDED to props
  ];

  AudioPlayerLoaded copyWith({
    String? currentSource,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    List<double>? waveformData,
    bool clearWaveform = false,
    List<TimeMarker>? markers,
    bool? isShuffleActive,
    double? volume, // <<< ADDED to copyWith
  }) {
    return AudioPlayerLoaded(
      currentSource: currentSource ?? this.currentSource,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      waveformData: clearWaveform ? null : (waveformData ?? this.waveformData),
      markers: markers ?? this.markers,
      isShuffleActive: isShuffleActive ?? this.isShuffleActive,
      volume: volume ?? this.volume, // <<< ADDED logic
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
