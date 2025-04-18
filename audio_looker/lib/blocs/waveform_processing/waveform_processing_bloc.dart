// lib/blocs/waveform_processing/waveform_processing_bloc.dart

import 'dart:async';

import 'package:bloc/bloc.dart';

// Import related events, states, service, and other BLoCs
import 'waveform_processing_event.dart';
import 'waveform_processing_state.dart';
import '../../services/waveform_processing_service.dart';
import '../track_management/track_data_bloc.dart';
// import '../track_management/track_data_event.dart'; // For UpdateTrackWaveform

// part 'waveform_processing_event.dart';
// part 'waveform_processing_state.dart';

class WaveformProcessingBloc
    extends Bloc<WaveformProcessingEvent, WaveformProcessingState> {
  final WaveformProcessingService _waveformProcessingService;
  final TrackDataBloc
  _trackDataBloc; // To dispatch updates for individual tracks
  StreamSubscription<WaveformProcessingUpdate>? _serviceSubscription;
  StreamSubscription<TrackDataState>? _trackDataSubscription;

  // Internal tracking for progress
  int _totalTracksInBatch = 0;
  int _processedTracksInBatch = 0;

  WaveformProcessingBloc({
    required WaveformProcessingService waveformProcessingService,
    required TrackDataBloc trackDataBloc,
  }) : _waveformProcessingService = waveformProcessingService,
       _trackDataBloc = trackDataBloc,
       super(WaveformProcessingInitial()) {
    // Register event handlers
    on<WaveformProcessingBatchStarted>(_onBatchStarted);
    on<WaveformProcessingTrackCompleted>(_onTrackCompleted);
    on<WaveformProcessingTrackFailed>(_onTrackFailed);
    // Note: We don't directly handle WaveformProcessingBatchFinished yet,
    // completion is determined by comparing processed vs total count.

    _trackDataSubscription = _trackDataBloc.stream.listen((trackDataState) {
      // Listen for the specific state emitted by TrackDataBloc
      if (trackDataState is TrackDataProcessingNeeded &&
          trackDataState.addedTracks.isNotEmpty) {
        print(
          '[WaveformBloc] Detected TrackDataProcessingNeeded state with ${trackDataState.addedTracks.length} tracks.',
        );

        // Extract the necessary info (IDs) from the state
        // Note: We assume TrackDataBloc already added tracks to the service queue
        final List<String> trackIds =
            trackDataState.addedTracks
                .where((track) => track.id != null)
                .map((track) => track.id!.toString())
                .toList();

        final int totalTracks = trackIds.length; // Get count from the list

        if (totalTracks > 0) {
          // Dispatch the BatchStarted event *to this BLoC*
          add(
            WaveformProcessingBatchStarted(
              trackIds: trackIds,
              totalTracks: totalTracks,
            ),
          );
          print('[WaveformBloc] Dispatched WaveformProcessingBatchStarted.');

          // *** IMPORTANT: Trigger reload in TrackDataBloc *after* starting processing ***
          // This ensures the UI eventually settles back to TrackDataLoaded
          _trackDataBloc.add(ReloadDataPreservingFilters());
          print(
            '[WaveformBloc] Dispatched ReloadDataPreservingFilters to TrackDataBloc.',
          );
        } else {
          print(
            '[WaveformBloc] TrackDataProcessingNeeded state had no valid track IDs. Reloading TrackDataBloc.',
          );
          // If no tracks need processing based on the state event, still reload TrackDataBloc
          _trackDataBloc.add(ReloadDataPreservingFilters());
        }
      }
    });

    // Listen to updates from the service
    _serviceSubscription = _waveformProcessingService.updates.listen(
      (update) {
        // Process updates from the service and add corresponding BLoC events
        if (update.isCompletionUpdate) {
          if (update.error == null && update.waveformData != null) {
            // Success
            add(
              WaveformProcessingTrackCompleted(
                update.trackId,
                update.waveformData!,
              ),
            );
          } else {
            // Failure
            add(
              WaveformProcessingTrackFailed(
                update.trackId,
                update.error ?? 'Unknown processing error',
              ),
            );
          }
        }
        // Ignore non-completion updates for now (e.g., progress per file)
      },
      onError: (error) {
        // Handle potential errors from the service stream itself
        print('Error in WaveformProcessingService stream: $error');
        // Optionally emit a general failure state here
        // emit(WaveformProcessingFailure("Service stream error: $error"));
      },
    );
  }

  /// Handler for when a new batch processing request starts.
  void _onBatchStarted(
    WaveformProcessingBatchStarted event,
    Emitter<WaveformProcessingState> emit,
  ) {
    if (event.totalTracks > 0) {
      _totalTracksInBatch = event.totalTracks;
      _processedTracksInBatch = 0;
      print('[WaveformBloc] Batch started. Total tracks: $_totalTracksInBatch');
      emit(
        WaveformProcessingInProgress(
          _processedTracksInBatch,
          _totalTracksInBatch,
        ),
      );
    } else {
      print(
        '[WaveformBloc] Batch started with 0 tracks. Finishing immediately.',
      );
      _totalTracksInBatch = 0;
      _processedTracksInBatch = 0;
      emit(WaveformProcessingComplete()); // Nothing to process
    }
  }

  /// Handler for when a single track completes successfully.
  void _onTrackCompleted(
    WaveformProcessingTrackCompleted event,
    Emitter<WaveformProcessingState> emit,
  ) {
    // Dispatch update to TrackDataBloc so the UI can update the specific track
    _trackDataBloc.add(
      UpdateTrackWaveform(
        trackId: event.trackId,
        waveformData: event.waveformData,
      ),
    );

    _processedTracksInBatch++;
    print(
      '[WaveformBloc] Track completed: ${event.trackId}. Progress: $_processedTracksInBatch/$_totalTracksInBatch',
    );

    if (_processedTracksInBatch >= _totalTracksInBatch) {
      print('[WaveformBloc] Batch finished.');
      emit(WaveformProcessingComplete());
    } else {
      // Only emit InProgress if the batch hasn't finished
      emit(
        WaveformProcessingInProgress(
          _processedTracksInBatch,
          _totalTracksInBatch,
        ),
      );
    }
  }

  /// Handler for when a single track fails processing.
  void _onTrackFailed(
    WaveformProcessingTrackFailed event,
    Emitter<WaveformProcessingState> emit,
  ) {
    // Log the error, could potentially dispatch an event to TrackDataBloc
    // to mark the track as failed if needed in the UI.
    print(
      '[WaveformBloc] Track failed: ${event.trackId}. Error: ${event.error}',
    );

    _processedTracksInBatch++;
    print(
      '[WaveformBloc] Failed track counted. Progress: $_processedTracksInBatch/$_totalTracksInBatch',
    );

    if (_processedTracksInBatch >= _totalTracksInBatch) {
      print('[WaveformBloc] Batch finished (with failures).');
      emit(WaveformProcessingComplete());
    } else {
      // Only emit InProgress if the batch hasn't finished
      emit(
        WaveformProcessingInProgress(
          _processedTracksInBatch,
          _totalTracksInBatch,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    print('[WaveformBloc] Closing BLoC and cancelling service subscription.');
    _serviceSubscription
        ?.cancel(); // Cancel the subscription to the service stream
    _trackDataSubscription?.cancel();
    return super.close();
  }
}
