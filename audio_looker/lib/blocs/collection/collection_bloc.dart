import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:path/path.dart' as pathLib;
import 'dart:async';
import 'package:audio_looker/services/audio_service.dart';

bool _isProcessingWaveforms = false;

class AddTracksFromPaths extends CollectionEvent {
  final List<String> filePaths;
  const AddTracksFromPaths(this.filePaths);

  @override
  List<Object> get props => [filePaths];
}

// Events
abstract class CollectionEvent extends Equatable {
  const CollectionEvent();

  @override
  List<Object?> get props => [];
}

class LoadCollection extends CollectionEvent {}

class AddTrackFromPath extends CollectionEvent {
  final String filePath;
  const AddTrackFromPath(this.filePath);

  @override
  List<Object> get props => [filePath];
}

class AddTrackFromUrl extends CollectionEvent {
  final String url;

  const AddTrackFromUrl(this.url);

  @override
  List<Object?> get props => [url];
}

class RemoveTrack extends CollectionEvent {
  final int trackId;

  const RemoveTrack(this.trackId);

  @override
  List<Object?> get props => [trackId];
}

class SearchCollection extends CollectionEvent {
  final String query;

  const SearchCollection(this.query);

  @override
  List<Object?> get props => [query];
}

class UpdateTrackRating extends CollectionEvent {
  final int trackId;
  final int rating;

  const UpdateTrackRating(this.trackId, this.rating);

  @override
  List<Object?> get props => [trackId, rating];
}

class UpdateTrackComment extends CollectionEvent {
  final int trackId;
  final String comment;

  const UpdateTrackComment(this.trackId, this.comment);

  @override
  List<Object?> get props => [trackId, comment];
}

class AddTrackGeneralTag extends CollectionEvent {
  final int trackId;
  final String tag;

  const AddTrackGeneralTag(this.trackId, this.tag);

  @override
  List<Object?> get props => [trackId, tag];
}

class RemoveTrackGeneralTag extends CollectionEvent {
  final int trackId;
  final String tag;

  const RemoveTrackGeneralTag(this.trackId, this.tag);

  @override
  List<Object?> get props => [trackId, tag];
}

class ImportCollectionFromFile extends CollectionEvent {
  final String path;

  const ImportCollectionFromFile(this.path);

  @override
  List<Object?> get props => [path];
}

class ExportCollectionToFile extends CollectionEvent {
  final String path;

  const ExportCollectionToFile(this.path);

  @override
  List<Object?> get props => [path];
}

// States
abstract class CollectionState extends Equatable {
  const CollectionState();

  @override
  List<Object?> get props => [];
}

class CollectionInitial extends CollectionState {}

class CollectionLoading extends CollectionState {
  final List<Track>? currentTracks; // Keep current tracks while loading

  const CollectionLoading({this.currentTracks});

  @override
  List<Object?> get props => [currentTracks];
}

class CollectionLoaded extends CollectionState {
  final List<Track> tracks;
  final String? searchQuery;

  const CollectionLoaded({required this.tracks, this.searchQuery});

  @override
  List<Object?> get props => [tracks, searchQuery];
}

class CollectionError extends CollectionState {
  final String message;
  final List<Track>? tracks; // Keep tracks on error for better UX

  const CollectionError(this.message, {this.tracks});

  @override
  List<Object?> get props => [message, tracks];
}

// BLoC
class CollectionBloc extends Bloc<CollectionEvent, CollectionState> {
  final CollectionService _collectionService;
  final AudioService _audioService = AudioService();
  bool _isProcessingWaveforms = false;
  bool _audioServiceInitialized = false;

  CollectionBloc(this._collectionService) : super(CollectionInitial()) {
    // Initialize AudioService
    _audioService.initialize();

    on<LoadCollection>(_onLoadCollection);
    on<AddTrackFromPath>(_onAddTrackFromPath);
    on<AddTrackFromUrl>(_onAddTrackFromUrl);
    on<RemoveTrack>(_onRemoveTrack);
    on<SearchCollection>(_onSearchCollection);
    on<UpdateTrackRating>(_onUpdateTrackRating);
    on<UpdateTrackComment>(_onUpdateTrackComment);
    on<AddTrackGeneralTag>(_onAddTrackGeneralTag);
    on<RemoveTrackGeneralTag>(_onRemoveTrackGeneralTag);
    on<ImportCollectionFromFile>(_onImportCollectionFromFile);
    on<ExportCollectionToFile>(_onExportCollectionToFile);
    on<AddTracksFromPaths>(_onAddTracksFromPaths);

    // Listen to loading state changes from service
    _collectionService.loadingStream.listen((isLoading) {
      if (isLoading && state is CollectionLoaded) {
        final currentState = state as CollectionLoaded;
        emit(CollectionLoading(currentTracks: currentState.tracks));
      }
    });
  }

  Future<void> _ensureAudioServiceInitialized() async {
    if (!_audioServiceInitialized) {
      print('AUDIO: Initializing AudioService');
      await _audioService.initialize();
      _audioServiceInitialized = true;
      print('AUDIO: AudioService initialization complete');
    }
  }

  // Make sure to dispose resources when bloc is closed
  @override
  Future<void> close() async {
    if (_audioServiceInitialized) {
      await _audioService.dispose();
    }
    return super.close();
  }

  Future<void> _onLoadCollection(
    LoadCollection event,
    Emitter<CollectionState> emit,
  ) async {
    emit(CollectionLoading());

    try {
      final tracks = await _collectionService.getAllTracks();
      emit(CollectionLoaded(tracks: tracks));
    } catch (e) {
      emit(CollectionError(e.toString()));
    }
  }

  // Replace your _onAddTracksFromPaths method
  Future<void> _onAddTracksFromPaths(
    AddTracksFromPaths event,
    Emitter<CollectionState> emit,
  ) async {
    print("BATCH: Processing ${event.filePaths.length} files");
    List<Track>? currentTracks;

    if (state is CollectionLoaded) {
      currentTracks = (state as CollectionLoaded).tracks;
      emit(CollectionLoading(currentTracks: currentTracks));
    } else {
      emit(CollectionLoading());
    }

    try {
      // Step 1: Add all tracks without waveform data (fast operation)
      for (final filePath in event.filePaths) {
        try {
          final filename = pathLib.basename(filePath);
          final title = pathLib.basenameWithoutExtension(filePath);

          final track = Track(
            title: title,
            artist: 'Unknown',
            album: 'Unknown',
            path: filePath,
            isUrl: false,
            duration: 0,
            waveformData: null,
            rating: 0,
            comment: '',
            generalTags: [],
          );

          await _collectionService.addTrack(track);
          print('BATCH: Added track: $title (without waveform data)');
        } catch (e) {
          print('BATCH ERROR: Failed to add file $filePath: $e');
        }
      }

      // Step 2: Update UI immediately to show tracks
      print("BATCH: Updating UI with added tracks");
      final tracks = await _collectionService.getAllTracks();
      emit(CollectionLoaded(tracks: tracks));

      // Step 3: Start background processing only if not already in progress
      print("BATCH: Checking if waveform processing can start");
      if (!_isProcessingWaveforms) {
        print("BATCH: Starting background waveform extraction");
        _startBackgroundWaveformExtraction(event.filePaths);
      } else {
        print("BATCH: Waveform processing already in progress, skipping");
      }
    } catch (e) {
      print('BATCH ERROR: Exception in _onAddTracksFromPaths: $e');
      _collectionService.setLoading(false);
      emit(CollectionError(e.toString(), tracks: currentTracks));
    }
  }

  // Replace your background processing method
  Future<void> _startBackgroundWaveformExtraction(
    List<String> filePaths,
  ) async {
    if (_isProcessingWaveforms) {
      print('WAVEFORM: Already processing waveforms, skipping');
      return;
    }

    _isProcessingWaveforms = true;
    print('WAVEFORM: Starting extraction for ${filePaths.length} files');

    try {
      // Ensure AudioService is initialized
      await _ensureAudioServiceInitialized();

      // Process one file at a time
      for (int i = 0; i < filePaths.length; i++) {
        final filePath = filePaths[i];
        final fileName = pathLib.basename(filePath);
        print(
          'WAVEFORM: Processing file ${i + 1}/${filePaths.length}: $fileName',
        );

        try {
          // Find track ID
          final trackId = await _getTrackIdByPath(filePath);
          if (trackId != null) {
            print('WAVEFORM: Found track ID: $trackId for file: $fileName');

            // Extract waveform
            final success = await _extractWaveformData(trackId, filePath);
            print(
              'WAVEFORM: Extraction ${success ? "succeeded" : "failed"} for $fileName',
            );

            // Update UI after each file
            if (state is CollectionLoaded) {
              print('WAVEFORM: Updating UI after processing file ${i + 1}');
              final tracks = await _collectionService.getAllTracks();
              emit(CollectionLoaded(tracks: tracks));
            }
          } else {
            print('WAVEFORM: Could not find track ID for $fileName');
          }
        } catch (e) {
          print('WAVEFORM ERROR: Exception processing $fileName: $e');
        }

        // Pause briefly between files
        await Future.delayed(const Duration(milliseconds: 500));
      }

      print('WAVEFORM: Completed extraction for all files');
    } catch (e) {
      print('WAVEFORM ERROR: Exception in background extraction: $e');
    } finally {
      _isProcessingWaveforms = false;
    }
  }
  // Simplified waveform extraction method
  // Replace the _extractWaveformData method in your collection_bloc.dart

  Future<bool> _extractWaveformData(int trackId, String filePath) async {
    print(
      'EXTRACT: Starting for track $trackId: ${pathLib.basename(filePath)}',
    );

    try {
      // Create a completer for managing the async process
      final completer = Completer<bool>();

      // Set a timeout
      final timeoutTimer = Timer(const Duration(seconds: 120), () {
        if (!completer.isCompleted) {
          print('EXTRACT: Timed out after 120 seconds for track $trackId');
          completer.complete(false);
        }
      });

      // Clear any previous waveform data
      _audioService.waveformStream.drain().catchError((_) {});

      // Add a listener BEFORE loading the audio
      late StreamSubscription subscription;
      subscription = _audioService.waveformStream.listen(
        (data) async {
          print('EXTRACT: Received waveform data with ${data.length} points');

          if (!completer.isCompleted) {
            // Cancel the subscription first
            await subscription.cancel();

            // Update the track with the waveform data
            try {
              await _updateTrackWithWaveform(trackId, data);
              timeoutTimer.cancel();
              completer.complete(true);
            } catch (e) {
              print('EXTRACT ERROR: Failed to update track: $e');
              timeoutTimer.cancel();
              completer.complete(false);
            }
          }
        },
        onError: (e) async {
          print('EXTRACT ERROR: Error in waveform stream: $e');
          if (!completer.isCompleted) {
            await subscription.cancel();
            timeoutTimer.cancel();
            completer.complete(false);
          }
        },
        onDone: () {
          print('EXTRACT: Waveform stream closed');
        },
      );

      // Process the file after listener is set up
      print('EXTRACT: Loading audio file for track $trackId');
      await _audioService.loadAudio(filePath, isUrl: false);

      // Wait for completion
      final result = await completer.future;
      timeoutTimer.cancel();

      if (!result) {
        // If the normal approach didn't work, try to access waveform data directly
        print('EXTRACT: Trying direct waveform access...');
        final directWaveformData = _audioService.waveformData;

        if (directWaveformData != null && directWaveformData.isNotEmpty) {
          print(
            'EXTRACT: Found waveform data directly with ${directWaveformData.length} points',
          );
          await _updateTrackWithWaveform(trackId, directWaveformData);
          return true;
        } else {
          print('EXTRACT: No waveform data available directly');
        }
      }

      print('EXTRACT: Completed with result: $result for track $trackId');
      return result;
    } catch (e) {
      print('EXTRACT ERROR: Exception for track $trackId: $e');
      return false;
    }
  }

  Future<void> _updateTrackWithWaveform(
    int trackId,
    List<double> waveformData,
  ) async {
    print('UPDATE: Saving waveform data for track $trackId');
    final track = await _collectionService.getTrack(trackId);
    if (track != null) {
      final updatedTrack = track.copyWith(waveformData: waveformData);
      await _collectionService.updateTrack(updatedTrack);
      print('UPDATE: Successfully saved waveform data for track $trackId');
    } else {
      print('UPDATE ERROR: Track $trackId not found');
      throw Exception('Track not found');
    }
  }

  Future<void> _processWaveformForTrack(int trackId, String filePath) async {
    try {
      // Use a completer to handle timeout
      final completer = Completer<void>();

      // Set timeout
      Timer(const Duration(seconds: 60), () {
        if (!completer.isCompleted) {
          print('Waveform extraction timed out for $filePath');
          completer.complete();
        }
      });

      // Load the audio file in AudioService
      await _audioService.loadAudio(filePath, isUrl: false);

      // Listen for waveform data
      List<double>? waveformData;
      final subscription = _audioService.waveformStream.listen(
        (data) {
          if (!completer.isCompleted) {
            waveformData = data;
            completer.complete();
          }
        },
        onError: (e) {
          if (!completer.isCompleted) {
            print('Error from waveform stream: $e');
            completer.complete();
          }
        },
      );

      // Wait for completion (either data received or timeout)
      await completer.future;
      await subscription.cancel();

      // Update track with waveform data if we got it
      if (waveformData != null) {
        final track = await _collectionService.getTrack(trackId);
        if (track != null) {
          final updatedTrack = track.copyWith(waveformData: waveformData);
          await _collectionService.updateTrack(updatedTrack);
          print('Updated waveform data for track $trackId');
        }
      }
    } catch (e) {
      print('Error processing waveform for track $trackId: $e');
    }
  }

  Future<void> _onAddTrackFromPath(
    AddTrackFromPath event,
    Emitter<CollectionState> emit,
  ) async {
    List<Track>? currentTracks;

    if (state is CollectionLoaded) {
      currentTracks = (state as CollectionLoaded).tracks;
      emit(CollectionLoading(currentTracks: currentTracks));
    } else {
      emit(CollectionLoading());
    }

    try {
      await _collectionService.addLocalFile(event.filePath);
      final tracks = await _collectionService.getAllTracks();
      emit(CollectionLoaded(tracks: tracks));
    } catch (e) {
      emit(CollectionError(e.toString(), tracks: currentTracks));
    }
  }

  Future<void> _extractAndUpdateWaveform(int trackId, String filePath) async {
    print('Extracting waveform for track $trackId at $filePath');

    try {
      // Load audio and wait for waveform with timeout protection
      await _audioService.loadAudio(filePath, isUrl: false);

      List<double>? waveformData;
      bool hasData = false;

      // Set up a timeout for waveform extraction
      Timer? timeoutTimer;
      final completer = Completer<void>();

      // Create timeout timer
      timeoutTimer = Timer(const Duration(seconds: 60), () {
        if (!completer.isCompleted) {
          print('Waveform extraction timed out for track $trackId');
          completer.complete();
        }
      });

      // Subscribe to waveform stream with timeout
      final subscription = _audioService.waveformStream.listen(
        (data) {
          if (!hasData && !completer.isCompleted) {
            waveformData = data;
            hasData = true;
            timeoutTimer?.cancel();
            completer.complete();
          }
        },
        onError: (e) {
          if (!completer.isCompleted) {
            print('Error in waveform stream for $trackId: $e');
            timeoutTimer?.cancel();
            completer.complete();
          }
        },
      );

      // Wait for completion
      await completer.future;
      await subscription.cancel();

      // Update the track if we got waveform data
      if (waveformData != null) {
        final track = await _collectionService.getTrack(trackId);
        if (track != null) {
          final updatedTrack = track.copyWith(waveformData: waveformData);
          await _collectionService.updateTrack(updatedTrack);
          print('Updated waveform data for track $trackId');
        }
      } else {
        print('No waveform data generated for track $trackId');
      }
    } catch (e) {
      print('Error extracting waveform for track $trackId: $e');
    }
  }

  // Helper method to find track by path (unchanged)
  Future<int?> _getTrackIdByPath(String path) async {
    try {
      final tracks = await _collectionService.getAllTracks();
      final matchingTracks = tracks.where((t) => t.path == path).toList();
      if (matchingTracks.isNotEmpty) {
        return matchingTracks.first.id;
      }
      return null;
    } catch (e) {
      print('ERROR: Error finding track by path: $e');
      return null;
    }
  }

  Future<void> _onAddTrackFromUrl(
    AddTrackFromUrl event,
    Emitter<CollectionState> emit,
  ) async {
    List<Track>? currentTracks;

    if (state is CollectionLoaded) {
      currentTracks = (state as CollectionLoaded).tracks;
      emit(CollectionLoading(currentTracks: currentTracks));
    } else {
      emit(CollectionLoading());
    }

    try {
      await _collectionService.addUrl(event.url);
      final tracks = await _collectionService.getAllTracks();
      emit(CollectionLoaded(tracks: tracks));
    } catch (e) {
      emit(CollectionError(e.toString(), tracks: currentTracks));
    }
  }

  Future<void> _onRemoveTrack(
    RemoveTrack event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentTracks = (state as CollectionLoaded).tracks;
      emit(CollectionLoading(currentTracks: currentTracks));

      try {
        await _collectionService.deleteTrack(event.trackId);
        final tracks = await _collectionService.getAllTracks();
        emit(CollectionLoaded(tracks: tracks));
      } catch (e) {
        emit(CollectionError(e.toString(), tracks: currentTracks));
      }
    }
  }

  Future<void> _onSearchCollection(
    SearchCollection event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentTracks = (state as CollectionLoaded).tracks;
      emit(CollectionLoading(currentTracks: currentTracks));

      try {
        final tracks =
            event.query.isEmpty
                ? await _collectionService.getAllTracks()
                : await _collectionService.searchTracks(event.query);

        emit(
          CollectionLoaded(
            tracks: tracks,
            searchQuery: event.query.isEmpty ? null : event.query,
          ),
        );
      } catch (e) {
        emit(CollectionError(e.toString(), tracks: currentTracks));
      }
    }
  }

  Future<void> _onUpdateTrackRating(
    UpdateTrackRating event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentTracks = (state as CollectionLoaded).tracks;
      try {
        await _collectionService.updateRating(event.trackId, event.rating);

        // Update the track in the current state
        final updatedTracks =
            currentTracks.map((track) {
              if (track.id == event.trackId) {
                return track.copyWith(rating: event.rating);
              }
              return track;
            }).toList();

        emit(CollectionLoaded(tracks: updatedTracks));
      } catch (e) {
        print('Error updating rating: $e');
        emit(CollectionError(e.toString(), tracks: currentTracks));
      }
    }
  }

  Future<void> _onUpdateTrackComment(
    UpdateTrackComment event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentTracks = (state as CollectionLoaded).tracks;
      try {
        await _collectionService.updateComment(event.trackId, event.comment);

        // Update the track in the current state
        final updatedTracks =
            currentTracks.map((track) {
              if (track.id == event.trackId) {
                return track.copyWith(comment: event.comment);
              }
              return track;
            }).toList();

        emit(CollectionLoaded(tracks: updatedTracks));
      } catch (e) {
        print('Error updating comment: $e');
        emit(CollectionError(e.toString(), tracks: currentTracks));
      }
    }
  }

  Future<void> _onAddTrackGeneralTag(
    AddTrackGeneralTag event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentTracks = (state as CollectionLoaded).tracks;
      try {
        await _collectionService.addGeneralTag(event.trackId, event.tag);

        // Update the track in the current state
        final updatedTracks =
            currentTracks.map((track) {
              if (track.id == event.trackId) {
                List<String> newTags = List<String>.from(track.generalTags);
                if (!newTags.contains(event.tag)) {
                  newTags.add(event.tag);
                }
                return track.copyWith(generalTags: newTags);
              }
              return track;
            }).toList();

        emit(CollectionLoaded(tracks: updatedTracks));
      } catch (e) {
        print('Error adding general tag: $e');
        emit(CollectionError(e.toString(), tracks: currentTracks));
      }
    }
  }

  Future<void> _onRemoveTrackGeneralTag(
    RemoveTrackGeneralTag event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentTracks = (state as CollectionLoaded).tracks;
      try {
        await _collectionService.removeGeneralTag(event.trackId, event.tag);

        // Update the track in the current state
        final updatedTracks =
            currentTracks.map((track) {
              if (track.id == event.trackId) {
                List<String> newTags = List<String>.from(track.generalTags);
                newTags.remove(event.tag);
                return track.copyWith(generalTags: newTags);
              }
              return track;
            }).toList();

        emit(CollectionLoaded(tracks: updatedTracks));
      } catch (e) {
        print('Error removing general tag: $e');
        emit(CollectionError(e.toString(), tracks: currentTracks));
      }
    }
  }

  Future<void> _onImportCollectionFromFile(
    ImportCollectionFromFile event,
    Emitter<CollectionState> emit,
  ) async {
    List<Track>? currentTracks;

    if (state is CollectionLoaded) {
      currentTracks = (state as CollectionLoaded).tracks;
    }

    emit(CollectionLoading(currentTracks: currentTracks));

    try {
      await _collectionService.importFromFile(event.path);
      final tracks = await _collectionService.getAllTracks();
      emit(CollectionLoaded(tracks: tracks));
    } catch (e) {
      emit(CollectionError(e.toString(), tracks: currentTracks));
    }
  }

  Future<void> _onExportCollectionToFile(
    ExportCollectionToFile event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      final currentTracks = (state as CollectionLoaded).tracks;

      try {
        await _collectionService.exportToFile(event.path);
        // State doesn't change after export
      } catch (e) {
        emit(CollectionError(e.toString(), tracks: currentTracks));
      }
    }
  }
}
