import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:just_audio/just_audio.dart'
    as just_audio
    show PlayerState, ProcessingState;
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
  final bool playWhenReady;
  final double? initialSeekRatio; // <<< CHANGED: Duration? to double?

  const LoadAudio({
    required this.source,
    required this.isUrl,
    this.playWhenReady = false,
    this.initialSeekRatio, // <<< CHANGED
  });

  @override
  // <<< CHANGED prop name for clarity
  List<Object?> get props => [source, isUrl, playWhenReady, initialSeekRatio];
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
  final double position; // Store as fraction 0.0-1.0
  final String label;

  const AddAudioTag({
    required this.source,
    required this.position,
    required this.label,
  });

  @override
  List<Object?> get props => [source, position, label];
}

// Rating event (If managed here, otherwise remove)
// class UpdateTrackRating extends AudioPlayerEvent { ... }

// Notes event (If managed here, otherwise remove)
// class UpdateTrackNotes extends AudioPlayerEvent { ... }

// General tags events (If managed here, otherwise remove)
// class AddTrackGeneralTag extends AudioPlayerEvent { ... }
// class RemoveTrackGeneralTag extends AudioPlayerEvent { ... }

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
  final String? currentSource; // *** ADDED: Track the loaded source ***
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<double>? waveformData;
  final List<AudioTag> tags; // Time-based tags

  const AudioPlayerLoaded({
    this.currentSource, // *** ADDED ***
    required this.isPlaying,
    required this.position,
    required this.duration,
    this.waveformData,
    this.tags = const [],
  });

  @override
  List<Object?> get props => [
    currentSource, // *** ADDED ***
    isPlaying,
    position,
    duration,
    waveformData,
    tags,
  ];

  AudioPlayerLoaded copyWith({
    String? currentSource, // *** ADDED ***
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    // Use List<double>? to allow clearing waveform
    List<double>? waveformData,
    bool clearWaveform = false, // Add flag to explicitly clear
    List<AudioTag>? tags,
  }) {
    return AudioPlayerLoaded(
      currentSource: currentSource ?? this.currentSource, // *** ADDED ***
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      // Handle waveform update/clearance
      waveformData: clearWaveform ? null : (waveformData ?? this.waveformData),
      tags: tags ?? this.tags,
    );
  }
}

class AudioPlayerError extends AudioPlayerState {
  final String message;
  final String? source; // <<< ADDED: Optional source of the error

  const AudioPlayerError(
    this.message, {
    this.source,
  }); // <<< MODIFIED: Add optional source parameter

  @override
  List<Object?> get props => [message, source]; // <<< MODIFIED: Include source in props
}

// BLoC
class AudioPlayerBloc extends Bloc<AudioPlayerEvent, AudioPlayerState> {
  final AudioService _audioService;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _waveformSubscription;
  // String? _currentSource; // Can be removed now, managed in state
  Timer? _loadingTimeout;

  AudioPlayerBloc(this._audioService) : super(AudioPlayerInitial()) {
    on<LoadAudio>(_onLoadAudio);
    on<PlayAudio>(_onPlayAudio);
    on<PauseAudio>(_onPauseAudio);
    on<StopAudio>(_onStopAudio);
    on<SeekAudio>(_onSeekAudio); // Make sure this is registered
    on<AddAudioTag>(_onAddAudioTag);
    on<UpdatePlaybackState>(_onUpdatePlaybackState);
    on<UpdatePlaybackPosition>(_onUpdatePlaybackPosition);
    on<UpdateWaveformData>(_onUpdateWaveformData);
  }

  Future<void> _onLoadAudio(
    LoadAudio event,
    Emitter<AudioPlayerState> emit,
  ) async {
    print('🔄 Bloc: Received LoadAudio event for source: ${event.source}');
    emit(AudioPlayerLoading());
    await _cancelSubscriptions();
    bool playWhenReady = event.playWhenReady;

    _loadingTimeout?.cancel();
    _loadingTimeout = Timer(const Duration(seconds: 20), () {
      print('⏱️ Bloc: Loading timed out after 20 seconds for ${event.source}');
      if (state is AudioPlayerLoading) {
        print('⚠️ Bloc: Forcing transition from loading state due to timeout');
        // <<< MODIFIED: Include source in timeout error >>>
        emit(
          AudioPlayerError('Audio loading timed out.', source: event.source),
        );
      }
      _loadingTimeout = null;
    });

    try {
      print(
        '🔄 Bloc: Loading audio from: ${event.source}, isUrl: ${event.isUrl}',
      );
      // Wait for the audio service to potentially resolve the source (like YouTube URLs)
      // and set it in the player. loadAudio itself might handle setting the player source now.
      await _audioService.loadAudio(event.source, isUrl: event.isUrl);
      print('✅ Bloc: Successfully initiated audio loading for ${event.source}');

      print('🔄 Bloc: Setting up stream subscriptions for ${event.source}');
      _setupSubscriptions();

      final initialDuration =
          await _audioService.durationStream.first ?? Duration.zero;
      final initialWaveform = _audioService.waveformData;
      final initialTags = _audioService.getTagsForAudio(event.source);

      print('🔄 Bloc: Emitting initial loaded state for ${event.source}');
      final loadedState = AudioPlayerLoaded(
        currentSource: event.source,
        isPlaying: false,
        position: Duration.zero, // Start position at 0 initially
        duration: initialDuration,
        waveformData: initialWaveform,
        tags: List<AudioTag>.from(initialTags),
      );

      print('🔄 Bloc: Emitting initial loaded state for ${event.source}');
      emit(loadedState);
      print(
        '✅ Bloc: Successfully emitted initial loaded state for ${event.source}',
      );

      if (event.initialSeekRatio != null && initialDuration > Duration.zero) {
        final seekPosition = initialDuration * event.initialSeekRatio!;
        print(
          '🔄 Bloc: Applying initial seek ratio ${event.initialSeekRatio} -> position: $seekPosition',
        );
        add(SeekAudio(position: seekPosition)); // Dispatch Seek event
        // Give the seek a moment to process before potentially playing
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Check the flag *after* emitting the loaded state
      if (event.playWhenReady) {
        print('▶️ Bloc: playWhenReady is true, calling _audioService.play()');
        _audioService.play(); // Request playback
      }

      _loadingTimeout?.cancel();
      _loadingTimeout = null;
      print('✅ Bloc: Loading process completed for ${event.source}');
    } catch (e, stackTrace) {
      print('❌ Bloc: Error loading audio for ${event.source}: $e');
      print(stackTrace);
      // <<< MODIFIED: Include source in caught error >>>
      emit(
        AudioPlayerError(
          'Failed to load audio: ${e.toString()}',
          source: event.source,
        ),
      );
      _loadingTimeout?.cancel();
      _loadingTimeout = null;
    }
  }

  void _setupSubscriptions() {
    // Position stream
    _positionSubscription = _audioService.positionStream.listen((position) {
      // Only add event if the state is currently loaded
      if (state is AudioPlayerLoaded) {
        add(UpdatePlaybackPosition(position));
      }
    }, onError: (error) => print('❌ Bloc: Error in position stream: $error'));

    // Player state stream
    _stateSubscription = _audioService.playerStateStream.listen(
      (playerState) {
        // Only add event if the state is currently loaded
        if (state is AudioPlayerLoaded) {
          add(UpdatePlaybackState(playerState));
        }
      },
      onError: (error) => print('❌ Bloc: Error in player state stream: $error'),
    );

    // Duration stream
    _durationSubscription = _audioService.durationStream.listen((duration) {
      if (duration != null && state is AudioPlayerLoaded) {
        // Update duration directly if state is loaded
        emit((state as AudioPlayerLoaded).copyWith(duration: duration));
      }
    }, onError: (error) => print('❌ Bloc: Error in duration stream: $error'));

    // Waveform stream
    _waveformSubscription = _audioService.waveformStream.listen(
      (waveformData) {
        print('✅ Bloc: Received waveform data: ${waveformData.length} points');
        // Only add event if the state is currently loaded
        if (state is AudioPlayerLoaded) {
          add(UpdateWaveformData(waveformData));
        }
      },
      onError: (error) {
        print('❌ Bloc: Error in waveform stream: $error');
        // Attempt to update with cached waveform on error if available
        if (state is AudioPlayerLoaded && _audioService.waveformData != null) {
          add(UpdateWaveformData(_audioService.waveformData!));
        }
      },
    );
  }

  void _onPlayAudio(PlayAudio event, Emitter<AudioPlayerState> emit) {
    print(
      "AudioPlayerBloc: Received PlayAudio. Current state: ${state.runtimeType}",
    ); // <-- ADD THIS
    if (state is AudioPlayerLoaded) {
      print("AudioPlayerBloc: Calling _audioService.play()"); // <-- ADD THIS
      _audioService.play();
      // State update will come from the playerStateStream listener
    } else {
      print("AudioPlayerBloc: Cannot play, state is not AudioPlayerLoaded.");
    }
  }

  void _onPauseAudio(PauseAudio event, Emitter<AudioPlayerState> emit) {
    if (state is AudioPlayerLoaded) {
      _audioService.pause();
      // State update will come from the playerStateStream listener
    }
  }

  void _onStopAudio(StopAudio event, Emitter<AudioPlayerState> emit) {
    if (state is AudioPlayerLoaded) {
      _audioService.stop();
      // Update state immediately to reflect stop (position 0, not playing)
      emit(
        (state as AudioPlayerLoaded).copyWith(
          isPlaying: false,
          position: Duration.zero,
        ),
      );
    }
  }

  // --- Modified Seek Handler ---
  void _onSeekAudio(SeekAudio event, Emitter<AudioPlayerState> emit) {
    if (state is AudioPlayerLoaded) {
      final currentState = state as AudioPlayerLoaded;
      // Ensure seek position is valid
      final validPosition =
          event.position.inMilliseconds < 0
              ? Duration.zero
              : event.position > currentState.duration
              ? currentState.duration
              : event.position;

      print("Bloc: Seeking to ${validPosition.inMilliseconds}ms");
      _audioService.seekTo(validPosition);

      // *** Immediately update the state's position ***
      // This makes the UI reflect the seek target instantly.
      emit(currentState.copyWith(position: validPosition));
    }
  }
  // --- End Modified Seek Handler ---

  void _onAddAudioTag(AddAudioTag event, Emitter<AudioPlayerState> emit) {
    if (state is AudioPlayerLoaded) {
      final currentState = state as AudioPlayerLoaded;
      // Add tag only if the source matches the currently loaded source
      if (currentState.currentSource == event.source) {
        // Ensure position is valid (0.0 to 1.0)
        final validPosition = event.position.clamp(0.0, 1.0);
        _audioService.addTag(event.source, validPosition, event.label);

        // Update tags in state
        final tagsList = _audioService.getTagsForAudio(event.source);
        emit(currentState.copyWith(tags: List<AudioTag>.from(tagsList)));
      } else {
        print(
          "Bloc Warning: Cannot add tag. Source mismatch. Current: ${currentState.currentSource}, Requested: ${event.source}",
        );
      }
    } else {
      print("Bloc Warning: Cannot add tag. Player not loaded.");
    }
  }

  void _onUpdatePlaybackState(
    UpdatePlaybackState event,
    Emitter<AudioPlayerState> emit,
  ) {
    if (state is AudioPlayerLoaded) {
      final currentState = state as AudioPlayerLoaded;
      final isPlaying = event.playerState.playing;
      final processingState = event.playerState.processingState;

      // Update playing status
      AudioPlayerLoaded newState = currentState.copyWith(isPlaying: isPlaying);

      // If processing state is completed, ensure isPlaying is false and position might be duration
      if (processingState == just_audio.ProcessingState.completed) {
        newState = newState.copyWith(
          isPlaying: false,
          // Optionally set position to duration on completion, or keep last known position
          position: newState.duration, // Set position to end when completed
        );
        print("Bloc: Playback completed. Setting position to duration.");
      }

      // Only emit if the playing state actually changed or completed
      if (newState.isPlaying != currentState.isPlaying ||
          processingState == just_audio.ProcessingState.completed) {
        emit(newState);
      }
    }
  }

  void _onUpdatePlaybackPosition(
    UpdatePlaybackPosition event,
    Emitter<AudioPlayerState> emit,
  ) {
    if (state is AudioPlayerLoaded) {
      // Only emit if the position actually changed significantly
      // (avoids excessive updates for minor fluctuations)
      final currentState = state as AudioPlayerLoaded;
      if ((currentState.position - event.position).abs() >
          const Duration(milliseconds: 50)) {
        // Adjust threshold if needed
        emit(currentState.copyWith(position: event.position));
      }
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
    print("Bloc: Cancelling audio stream subscriptions");
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await _durationSubscription?.cancel();
    _durationSubscription = null;
    await _waveformSubscription?.cancel();
    _waveformSubscription = null;
    print("Bloc: Subscriptions cancelled");
  }

  @override
  Future<void> close() async {
    print("Bloc: Closing AudioPlayerBloc");
    await _cancelSubscriptions();
    // Don't dispose the shared AudioService here, manage its lifecycle elsewhere
    // await _audioService.dispose();
    _loadingTimeout?.cancel(); // Ensure timer is cancelled on close
    print("Bloc: AudioPlayerBloc closed");
    return super.close();
  }
}
