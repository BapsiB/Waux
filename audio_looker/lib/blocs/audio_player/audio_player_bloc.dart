import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:just_audio/just_audio.dart'
    as just_audio
    show PlayerState, ProcessingState;
import 'package:audio_looker/services/audio_service.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/blocs/track_management/track_metadata_bloc.dart';

part 'audio_player_event.dart';
part 'audio_player_state.dart';

// BLoC
class AudioPlayerBloc extends Bloc<AudioPlayerEvent, AudioPlayerState> {
  final AudioService _audioService;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _waveformSubscription;
  final TrackMetadataBloc _trackMetadataBloc;
  // String? _currentSource; // Can be removed now, managed in state
  Timer? _loadingTimeout;

  AudioPlayerBloc(this._audioService, this._trackMetadataBloc)
    : super(AudioPlayerInitial()) {
    on<LoadAudio>(_onLoadAudio);
    on<PlayAudio>(_onPlayAudio);
    on<PauseAudio>(_onPauseAudio);
    on<StopAudio>(_onStopAudio);
    on<SeekAudio>(_onSeekAudio); // Make sure this is registered
    on<AddTimeMarker>(_onAddTimeMarker);
    on<UpdatePlaybackState>(_onUpdatePlaybackState);
    on<UpdatePlaybackPosition>(_onUpdatePlaybackPosition);
    on<UpdateWaveformData>(_onUpdateWaveformData);
  }

  Future<void> _onLoadAudio(
    LoadAudio event,
    Emitter<AudioPlayerState> emit,
  ) async {
    print('🔄 Bloc: Received LoadAudio event for source: ${event.track.path}');
    emit(AudioPlayerLoading());
    await _cancelSubscriptions();

    _loadingTimeout?.cancel();
    _loadingTimeout = Timer(const Duration(seconds: 20), () {
      print(
        '⏱️ Bloc: Loading timed out after 20 seconds for ${event.track.path}',
      );
      if (state is AudioPlayerLoading) {
        print('⚠️ Bloc: Forcing transition from loading state due to timeout');
        // <<< MODIFIED: Include source in timeout error >>>
        emit(
          AudioPlayerError(
            'Audio loading timed out.',
            source: event.track.path,
          ),
        );
      }
      _loadingTimeout = null;
    });

    try {
      print(
        '🔄 Bloc: Loading audio from: ${event.track.path}, isUrl: ${event.track.isUrl}',
      );
      // Wait for the audio service to potentially resolve the source (like YouTube URLs)
      // and set it in the player. loadAudio itself might handle setting the player source now.
      await _audioService.loadAudio(event.track);

      _setupSubscriptions();

      final initialDuration =
          await _audioService.durationStream.first ?? Duration.zero;
      final initialWaveform = _audioService.waveformData;
      final initialTags = _audioService.getTimeMarkersForAudio(
        event.track.path,
      );

      final loadedState = AudioPlayerLoaded(
        currentSource: event.track.path,
        isPlaying: false,
        position: Duration.zero, // Start position at 0 initially
        duration: initialDuration,
        waveformData: initialWaveform,
        markers: List<TimeMarker>.from(initialTags),
      );

      emit(loadedState);

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
    } catch (e, stackTrace) {
      print(stackTrace);
      // <<< MODIFIED: Include source in caught error >>>
      emit(
        AudioPlayerError(
          'Failed to load audio: ${e.toString()}',
          source: event.track.path,
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

  void _onAddTimeMarker(AddTimeMarker event, Emitter<AudioPlayerState> emit) {
    if (state is AudioPlayerLoaded) {
      final currentState = state as AudioPlayerLoaded;
      if (currentState.currentSource == event.source) {
        final validPosition = event.position.clamp(0.0, 1.0);

        // 1. Update in-memory store via AudioService
        _audioService.addMarker(event.source, validPosition, event.label);

        // 2. Get the updated list from AudioService
        final updatedMarkers = _audioService.getTimeMarkersForAudio(
          event.source,
        );

        // 3. Emit the updated state for immediate UI feedback
        emit(
          currentState.copyWith(markers: List<TimeMarker>.from(updatedMarkers)),
        );
        print("AudioPlayerBloc: Updated in-memory markers and emitted state.");

        // 4. Dispatch event to TrackMetadataBloc to persist the change
        try {
          // --- Use the injected _trackMetadataBloc instance ---
          _trackMetadataBloc.add(
            UpdateTrackMarkers(event.trackId, updatedMarkers),
          );
          // --- End Use injected instance ---
          print(
            "AudioPlayerBloc: Dispatched UpdateTrackMarkers to TrackMetadataBloc for track ${event.trackId}.",
          );
        } catch (e) {
          // This catch block might be less necessary if DI guarantees _trackMetadataBloc exists,
          // but good for catching potential issues during the dispatch itself.
          print(
            "AudioPlayerBloc Error: Could not dispatch UpdateTrackMarkers. Error: $e",
          );
        }
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
