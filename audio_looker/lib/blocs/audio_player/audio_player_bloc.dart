import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:just_audio/just_audio.dart' as just_audio show PlayerState;
import 'package:audio_looker/services/audio_service.dart';

// Events
abstract class AudioPlayerEvent extends Equatable {
  const AudioPlayerEvent();

  @override
  List<Object?> get props => [];
}

class LoadAudio extends AudioPlayerEvent {
  final String source;
  final bool isUrl;

  const LoadAudio({required this.source, required this.isUrl});

  @override
  List<Object?> get props => [source, isUrl];
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

class AddAudioTag extends AudioPlayerEvent {
  final String source;
  final double position;
  final String label;

  const AddAudioTag({
    required this.source,
    required this.position,
    required this.label,
  });

  @override
  List<Object?> get props => [source, position, label];
}

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

// States
abstract class AudioPlayerState extends Equatable {
  const AudioPlayerState();

  @override
  List<Object?> get props => [];
}

class AudioPlayerInitial extends AudioPlayerState {}

class AudioPlayerLoading extends AudioPlayerState {}

class AudioPlayerLoaded extends AudioPlayerState {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<double>? waveformData;
  final List<AudioTag> tags;

  const AudioPlayerLoaded({
    required this.isPlaying,
    required this.position,
    required this.duration,
    this.waveformData,
    this.tags = const [],
  });

  @override
  List<Object?> get props => [
    isPlaying,
    position,
    duration,
    waveformData,
    tags,
  ];

  AudioPlayerLoaded copyWith({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    List<double>? waveformData,
    List<AudioTag>? tags,
  }) {
    return AudioPlayerLoaded(
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      waveformData: waveformData ?? this.waveformData,
      tags: tags ?? this.tags,
    );
  }
}

class AudioPlayerError extends AudioPlayerState {
  final String message;

  const AudioPlayerError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class AudioPlayerBloc extends Bloc<AudioPlayerEvent, AudioPlayerState> {
  final AudioService _audioService;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _waveformSubscription;
  String? _currentSource;

  AudioPlayerBloc(this._audioService) : super(AudioPlayerInitial()) {
    on<LoadAudio>(_onLoadAudio);
    on<PlayAudio>(_onPlayAudio);
    on<PauseAudio>(_onPauseAudio);
    on<StopAudio>(_onStopAudio);
    on<SeekAudio>(_onSeekAudio);
    on<AddAudioTag>(_onAddAudioTag);
    on<UpdatePlaybackState>(_onUpdatePlaybackState);
    on<UpdatePlaybackPosition>(_onUpdatePlaybackPosition);
    on<UpdateWaveformData>(_onUpdateWaveformData);
  }

  Future<void> _onLoadAudio(
    LoadAudio event,
    Emitter<AudioPlayerState> emit,
  ) async {
    emit(AudioPlayerLoading());

    try {
      // Clean up previous subscriptions
      await _cancelSubscriptions();

      // Load the audio
      await _audioService.loadAudio(event.source, isUrl: event.isUrl);
      _currentSource = event.source;

      // Set up new subscriptions
      _positionSubscription = _audioService.positionStream.listen((position) {
        add(UpdatePlaybackPosition(position));
      });

      _stateSubscription = _audioService.playerStateStream.listen((state) {
        add(UpdatePlaybackState(state));
      });

      _durationSubscription = _audioService.durationStream.listen((duration) {
        if (duration != null && state is AudioPlayerLoaded) {
          emit((state as AudioPlayerLoaded).copyWith(duration: duration));
        }
      });

      _waveformSubscription = _audioService.waveformStream.listen((
        waveformData,
      ) {
        add(UpdateWaveformData(waveformData));
      });

      // Initial state
      final tagsList =
          _currentSource != null
              ? _audioService.getTagsForAudio(_currentSource!)
              : [];
      final List<AudioTag> tags = List<AudioTag>.from(tagsList);

      emit(
        AudioPlayerLoaded(
          isPlaying: false,
          position: Duration.zero,
          duration: Duration.zero,
          waveformData: _audioService.waveformData,
          tags: tags,
        ),
      );
    } catch (e) {
      emit(AudioPlayerError(e.toString()));
    }
  }

  void _onPlayAudio(PlayAudio event, Emitter<AudioPlayerState> emit) {
    _audioService.play();
  }

  void _onPauseAudio(PauseAudio event, Emitter<AudioPlayerState> emit) {
    _audioService.pause();
  }

  void _onStopAudio(StopAudio event, Emitter<AudioPlayerState> emit) {
    _audioService.stop();
  }

  void _onSeekAudio(SeekAudio event, Emitter<AudioPlayerState> emit) {
    _audioService.seekTo(event.position);
  }

  void _onAddAudioTag(AddAudioTag event, Emitter<AudioPlayerState> emit) {
    if (state is AudioPlayerLoaded) {
      _audioService.addTag(event.source, event.position, event.label);

      // Update tags in state
      final tagsList = _audioService.getTagsForAudio(event.source);
      final List<AudioTag> tags = List<AudioTag>.from(tagsList);
      emit((state as AudioPlayerLoaded).copyWith(tags: tags));
    }
  }

  void _onUpdatePlaybackState(
    UpdatePlaybackState event,
    Emitter<AudioPlayerState> emit,
  ) {
    if (state is AudioPlayerLoaded) {
      final isPlaying = event.playerState.playing;
      emit((state as AudioPlayerLoaded).copyWith(isPlaying: isPlaying));
    }
  }

  void _onUpdatePlaybackPosition(
    UpdatePlaybackPosition event,
    Emitter<AudioPlayerState> emit,
  ) {
    if (state is AudioPlayerLoaded) {
      emit((state as AudioPlayerLoaded).copyWith(position: event.position));
    }
  }

  void _onUpdateWaveformData(
    UpdateWaveformData event,
    Emitter<AudioPlayerState> emit,
  ) {
    if (state is AudioPlayerLoaded) {
      emit(
        (state as AudioPlayerLoaded).copyWith(waveformData: event.waveformData),
      );
    }
  }

  Future<void> _cancelSubscriptions() async {
    await _positionSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _waveformSubscription?.cancel();
  }

  @override
  Future<void> close() async {
    await _cancelSubscriptions();
    return super.close();
  }
}
