// lib/blocs/collection_management/collection_management_event.dart

part of 'collection_management_bloc.dart';

abstract class CollectionManagementEvent extends Equatable {
  const CollectionManagementEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load the list of all available collection definitions.
class LoadCollectionList extends CollectionManagementEvent {}

/// Event to switch the active collection.
class SwitchCollection extends CollectionManagementEvent {
  final String collectionId;
  const SwitchCollection(this.collectionId);
  @override
  List<Object> get props => [collectionId];
}

/// Event to create a new shared collection definition and its initial DB.
class CreateSharedCollection extends CollectionManagementEvent {
  final String name;
  final String rootPath; // Root directory for the shared collection
  const CreateSharedCollection({required this.name, required this.rootPath});
  @override
  List<Object> get props => [name, rootPath];
}

/// Event to create a new local collection definition and its initial DB.
class CreateLocalCollection extends CollectionManagementEvent {
  final String name;
  const CreateLocalCollection(this.name);
  @override
  List<Object> get props => [name];
}

/// Event to add an existing shared collection definition (DB file must exist).
class AddExistingSharedCollection extends CollectionManagementEvent {
  final String name;
  final String rootPath; // Root directory containing the DB
  final String dbPath; // Full path to the existing DB file

  const AddExistingSharedCollection({
    required this.name,
    required this.rootPath,
    required this.dbPath,
  });

  @override
  List<Object> get props => [name, rootPath, dbPath];
}

/// Event to delete a collection definition (does not delete DB file).
class DeleteCollection extends CollectionManagementEvent {
  final String collectionId;
  const DeleteCollection(this.collectionId);
  @override
  List<Object> get props => [collectionId];
}
