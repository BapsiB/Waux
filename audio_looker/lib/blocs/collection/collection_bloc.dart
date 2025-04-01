import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_looker/services/collection_service.dart';

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

  CollectionBloc(this._collectionService) : super(CollectionInitial()) {
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

    // Listen to loading state changes from service
    _collectionService.loadingStream.listen((isLoading) {
      if (isLoading && state is CollectionLoaded) {
        final currentState = state as CollectionLoaded;
        emit(CollectionLoading(currentTracks: currentState.tracks));
      }
    });
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
        final tracks = await _collectionService.getAllTracks();
        emit(CollectionLoaded(tracks: tracks));
      } catch (e) {
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
        final tracks = await _collectionService.getAllTracks();
        emit(CollectionLoaded(tracks: tracks));
      } catch (e) {
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
        final tracks = await _collectionService.getAllTracks();
        emit(CollectionLoaded(tracks: tracks));
      } catch (e) {
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
        final tracks = await _collectionService.getAllTracks();
        emit(CollectionLoaded(tracks: tracks));
      } catch (e) {
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
