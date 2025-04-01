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

class CollectionLoading extends CollectionState {}

class CollectionLoaded extends CollectionState {
  final List<Track> tracks;
  final String? searchQuery;

  const CollectionLoaded({required this.tracks, this.searchQuery});

  @override
  List<Object?> get props => [tracks, searchQuery];
}

class CollectionError extends CollectionState {
  final String message;

  const CollectionError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class CollectionBloc extends Bloc<CollectionEvent, CollectionState> {
  final CollectionService _collectionService;

  CollectionBloc(this._collectionService) : super(CollectionInitial()) {
    on<LoadCollection>(_onLoadCollection);
    on<AddTrackFromPath>(_onAddTrackFromPath); // Changed from AddTrackFromFile
    on<AddTrackFromUrl>(_onAddTrackFromUrl);
    on<RemoveTrack>(_onRemoveTrack);
    on<SearchCollection>(_onSearchCollection);
    on<ImportCollectionFromFile>(_onImportCollectionFromFile);
    on<ExportCollectionToFile>(_onExportCollectionToFile);
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
    // Renamed from _onAddTrackFromFile
    AddTrackFromPath event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      try {
        emit(CollectionLoading());

        // Update this line to use the path instead of File object
        await _collectionService.addLocalFile(
          event.filePath,
        ); // Assuming you'll update CollectionService too

        final tracks = await _collectionService.getAllTracks();
        emit(CollectionLoaded(tracks: tracks));
      } catch (e) {
        emit(CollectionError(e.toString()));
      }
    }
  }

  Future<void> _onAddTrackFromUrl(
    AddTrackFromUrl event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      try {
        // Mark loading state while keeping current tracks
        emit(CollectionLoading());

        // Add track
        await _collectionService.addUrl(event.url);

        // Reload all tracks
        final tracks = await _collectionService.getAllTracks();
        emit(CollectionLoaded(tracks: tracks));
      } catch (e) {
        emit(CollectionError(e.toString()));
      }
    }
  }

  Future<void> _onRemoveTrack(
    RemoveTrack event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      try {
        // Mark loading state while keeping current tracks
        emit(CollectionLoading());

        // Remove track
        await _collectionService.deleteTrack(event.trackId);

        // Reload all tracks
        final tracks = await _collectionService.getAllTracks();
        emit(CollectionLoaded(tracks: tracks));
      } catch (e) {
        emit(CollectionError(e.toString()));
      }
    }
  }

  Future<void> _onSearchCollection(
    SearchCollection event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      try {
        emit(CollectionLoading());

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
        emit(CollectionError(e.toString()));
      }
    }
  }

  Future<void> _onImportCollectionFromFile(
    ImportCollectionFromFile event,
    Emitter<CollectionState> emit,
  ) async {
    try {
      emit(CollectionLoading());

      await _collectionService.importFromFile(event.path);

      final tracks = await _collectionService.getAllTracks();
      emit(CollectionLoaded(tracks: tracks));
    } catch (e) {
      emit(CollectionError(e.toString()));
    }
  }

  Future<void> _onExportCollectionToFile(
    ExportCollectionToFile event,
    Emitter<CollectionState> emit,
  ) async {
    if (state is CollectionLoaded) {
      try {
        await _collectionService.exportToFile(event.path);
        // State doesn't change after export
      } catch (e) {
        emit(CollectionError(e.toString()));
      }
    }
  }
}
