// lib/blocs/audio_player/audio_player_event.dart

part of 'audio_player_bloc.dart'; // Use part of directive

abstract class AudioPlayerEvent extends Equatable {
  const AudioPlayerEvent();

  @override
  List<Object?> get props => [];
}

class LoadAudio extends AudioPlayerEvent {
  final bool playWhenReady;
  final double? initialSeekRatio;
  final Track track;

  const LoadAudio({
    required this.track,
    this.playWhenReady = false,
    this.initialSeekRatio,
  });

  @override
  List<Object?> get props => [track, playWhenReady, initialSeekRatio];
}

class PlayAudio extends AudioPlayerEvent {}

class PauseAudio extends AudioPlayerEvent {}

class StopAudio extends AudioPlayerEvent {}

class SeekAudio extends AudioPlayerEvent {
  final Duration position;

  const SeekAudio({required this.position});

  @override
  List<Object?> get props => [position];
}

class SetVolume extends AudioPlayerEvent {
  final double volume;

  const SetVolume(this.volume);

  @override
  List<Object?> get props => [volume];
}

class _UpdateVolume extends AudioPlayerEvent {
  final double volume;
  const _UpdateVolume(this.volume);
  @override
  List<Object> get props => [volume];
}

// *** Renamed AddAudioTag to AddTimeMarker ***
class AddTimeMarker extends AudioPlayerEvent {
  // --- >>> ADDED trackId <<< ---
  final int trackId;
  // --- >>> END ADDED <<< ---
  final String source;
  final double position; // Position fraction (0.0-1.0)
  final String label;

  const AddTimeMarker({
    // --- >>> ADDED trackId <<< ---
    required this.trackId,
    // --- >>> END ADDED <<< ---
    required this.source,
    required this.position,
    required this.label,
  });

  @override
  List<Object?> get props => [trackId, source, position, label]; // Add trackId to props
}

// Internal events for stream updates
class UpdatePlaybackState extends AudioPlayerEvent {
  final just_audio.PlayerState playerState;

  const UpdatePlaybackState(this.playerState);

  @override
  List<Object?> get props => [playerState];
}

class UpdatePlaybackPosition extends AudioPlayerEvent {
  final Duration position;

  const UpdatePlaybackPosition(this.position);

  @override
  List<Object?> get props => [position];
}

class UpdateWaveformData extends AudioPlayerEvent {
  final List<double> waveformData;

  const UpdateWaveformData(this.waveformData);

  @override
  List<Object?> get props => [waveformData];
}

/// Event to load the shuffle preference from storage.
class LoadShufflePreference extends AudioPlayerEvent {}

/// Event to toggle the shuffle state (on/off).
class ToggleShuffle extends AudioPlayerEvent {}

/// Internal event to update the shuffle state after loading preference.
class _UpdateShuffleState extends AudioPlayerEvent {
  final bool isShuffleActive;
  const _UpdateShuffleState(this.isShuffleActive);
  @override
  List<Object> get props => [isShuffleActive];
}

class UpdateDuration extends AudioPlayerEvent {
  final Duration? duration;

  const UpdateDuration(this.duration);

  @override
  List<Object?> get props => [duration];
}

class HandleAudioProcessingState extends AudioPlayerEvent {
  // *** Use the alias from the main BLoC file ***
  final just_audio.ProcessingState processingState;

  const HandleAudioProcessingState(this.processingState);

  @override
  List<Object?> get props => [processingState];
}

class HandleStreamError extends AudioPlayerEvent {
  final Object error;
  final String streamName;

  const HandleStreamError(this.error, this.streamName);

  @override
  List<Object?> get props => [error, streamName];
}
