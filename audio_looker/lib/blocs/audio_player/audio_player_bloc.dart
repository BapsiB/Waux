import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:just_audio/just_audio.dart'
    as just_audio
    show PlayerState, ProcessingState;
import 'package:waux/services/audio_service.dart';
import 'package:waux/services/collection_service.dart';
import 'package:waux/blocs/track_management/track_metadata_bloc.dart';
import 'package:just_audio/just_audio.dart';

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
  StreamSubscription? _volumeSubscription;
  Timer? _loadingTimeout;

  AudioPlayerBloc(this._audioService, this._trackMetadataBloc)
    : super(AudioPlayerInitial()) {
    on<LoadAudio>(_onLoadAudio);
    on<PlayAudio>(_onPlayAudio);
    on<PauseAudio>(_onPauseAudio);
    on<StopAudio>(_onStopAudio);
    on<SeekAudio>(_onSeekAudio);
    on<SetVolume>(_onSetVolume);
    on<AddTimeMarker>(_onAddTimeMarker);
    on<UpdatePlaybackState>(_onUpdatePlaybackState);
    on<UpdatePlaybackPosition>(_onUpdatePlaybackPosition);
    on<UpdateWaveformData>(_onUpdateWaveformData);
    on<LoadShufflePreference>(_onLoadShufflePreference); // Register handler
    on<ToggleShuffle>(_onToggleShuffle); // Register handler
    on<_UpdateShuffleState>(_onUpdateShuffleState); // Register handler
    on<_UpdateVolume>(_onUpdateVolume);
  }

  Future<void> _onLoadShufflePreference(
    LoadShufflePreference event,
    Emitter<AudioPlayerState> emit,
  ) async {
    final bool shufflePref = await _audioService.loadShufflePreference();
    print("Bloc: Loaded shuffle preference: $shufflePref");
    // Use the internal event to update state without triggering side effects
    add(_UpdateShuffleState(shufflePref));
  }

  Future<void> _onToggleShuffle(
    ToggleShuffle event,
    Emitter<AudioPlayerState> emit,
  ) async {
    if (state is AudioPlayerLoaded) {
      final currentState = state as AudioPlayerLoaded;
      final newShuffleState = !currentState.isShuffleActive;
      await _audioService.saveShufflePreference(newShuffleState);
      print("Bloc: Toggled shuffle to: $newShuffleState and saved.");
      emit(currentState.copyWith(isShuffleActive: newShuffleState));
    } else {
      // Handle toggling when player isn't loaded? Maybe load pref and toggle.
      final currentPref = await _audioService.loadShufflePreference();
      final newShuffleState = !currentPref;
      await _audioService.saveShufflePreference(newShuffleState);
      print(
        "Bloc: Toggled shuffle preference (player not loaded) to: $newShuffleState",
      );
      // No state to emit if not loaded, preference is just saved.
    }
  }

  void _onUpdateShuffleState(
    // Handler for internal state update
    _UpdateShuffleState event,
    Emitter<AudioPlayerState> emit,
  ) {
    if (state is AudioPlayerLoaded) {
      final currentState = state as AudioPlayerLoaded;
      // Only emit if the state actually changes
      if (currentState.isShuffleActive != event.isShuffleActive) {
        emit(currentState.copyWith(isShuffleActive: event.isShuffleActive));
        print(
          "Bloc: Internal shuffle state updated to ${event.isShuffleActive}",
        );
      }
    }
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
      /* ... timeout logic ... */
    });

    try {
      // --- Track data already contains the potentially stored duration ---
      final Track track = event.track;
      int initialDurationMs =
          track.duration; // <<< Get duration from track object

      print('🔄 Bloc: Loading audio service for: ${track.path}');
      await _audioService.loadAudio(
        track,
      ); // Load waveform, markers, prepare player
      _setupSubscriptions();

      final initialWaveform = _audioService.waveformData;
      final initialMarkers = _audioService.getTimeMarkersForAudio(track.path);

      final currentShuffleState =
          state is AudioPlayerLoaded
              ? (state as AudioPlayerLoaded).isShuffleActive
              : await _audioService.loadShufflePreference();

      final currentVolume = _audioService.currentVolume;

      final loadedState = AudioPlayerLoaded(
        currentSource: track.path,
        isPlaying: false,
        position: Duration.zero,
        duration: Duration(milliseconds: initialDurationMs),
        waveformData: initialWaveform,
        markers: List<TimeMarker>.from(initialMarkers),
        isShuffleActive: currentShuffleState,
        volume: currentVolume,
      );
      emit(loadedState);
      print(
        "Bloc: Emitted initial loaded state with duration: $initialDurationMs ms",
      );

      // --- Check if duration needs fetching/updating in the background ---
      if (initialDurationMs <= 0 && track.id != null) {
        // <<< Check if duration is invalid
        print(
          "Bloc: Duration is 0 or missing for track ${track.id}. Fetching in background...",
        );
        // Don't await this, let it run in the background
        _fetchDurationInBackground(track.path, track.isUrl)
            .then((fetchedDurationMs) {
              if (fetchedDurationMs > 0) {
                print(
                  "Bloc: Background fetch complete for track ${track.id}. Got ${fetchedDurationMs}ms. Dispatching update.",
                );
                // Dispatch event to TrackMetadataBloc to save the fetched duration
                _trackMetadataBloc.add(
                  UpdateTrackDuration(track.id!, fetchedDurationMs),
                );
              } else {
                print(
                  "Bloc: Background fetch failed or returned 0 duration for track ${track.id}.",
                );
              }
            })
            .catchError((error) {
              print(
                "Bloc: Error during background duration fetch for track ${track.id}: $error",
              );
            });
      }
      // --- End background duration fetch ---

      // --- Handle initial seek and playWhenReady as before ---
      if (event.initialSeekRatio != null && initialDurationMs > 0) {
        final seekPosition =
            Duration(milliseconds: initialDurationMs) * event.initialSeekRatio!;
        print(
          '🔄 Bloc: Applying initial seek ratio ${event.initialSeekRatio} -> position: $seekPosition',
        );
        add(SeekAudio(position: seekPosition));
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (event.playWhenReady) {
        print('▶️ Bloc: playWhenReady is true, calling _audioService.play()');
        _audioService.play();
      }

      _loadingTimeout?.cancel();
      _loadingTimeout = null;
    } catch (e, stackTrace) {
      // ... (error handling) ...
      print(stackTrace);
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

    _volumeSubscription = _audioService.volumeStream.listen((volume) {
      add(_UpdateVolume(volume)); // Dispatch internal event
    }, onError: (error) => print('❌ Bloc: Error in volume stream: $error'));
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

  void _onSetVolume(SetVolume event, Emitter<AudioPlayerState> emit) {
    final clampedVolume = event.volume.clamp(0.0, 1.0);
    _audioService.setVolume(clampedVolume);
    // State update will come from the volumeStream listener via _onUpdateVolume
  }

  Future<int> _fetchDurationInBackground(String path, bool isUrl) async {
    final player = AudioPlayer();
    int durationMs = 0;
    try {
      print("AudioPlayerBloc: Fetching duration in background for $path");
      Duration? duration =
          isUrl ? await player.setUrl(path) : await player.setFilePath(path);
      durationMs = duration?.inMilliseconds ?? 0;
    } catch (e) {
      print(
        "AudioPlayerBloc: Error fetching background duration for $path: $e",
      );
      durationMs = 0;
    } finally {
      await player.dispose();
    }
    print(
      "AudioPlayerBloc: Background duration fetched for $path: $durationMs ms",
    );
    return durationMs;
  }

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

  void _onUpdateVolume(_UpdateVolume event, Emitter<AudioPlayerState> emit) {
    if (state is AudioPlayerLoaded) {
      final currentState = state as AudioPlayerLoaded;
      // Only emit if volume changed
      if (currentState.volume != event.volume) {
        emit(currentState.copyWith(volume: event.volume));
      }
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
    await _volumeSubscription?.cancel(); // <<< Cancel volume subscription
    _volumeSubscription = null;
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
