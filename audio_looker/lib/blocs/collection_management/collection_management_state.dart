// lib/blocs/collection_management/collection_management_state.dart

part of 'collection_management_bloc.dart';

abstract class CollectionManagementState extends Equatable {
  final List<CollectionDefinition> availableCollections;
  final CollectionDefinition? activeCollectionDefinition;

  const CollectionManagementState({
    this.availableCollections = const [],
    this.activeCollectionDefinition,
  });

  @override
  List<Object?> get props => [availableCollections, activeCollectionDefinition];
}

/// Initial state before definitions are loaded.
class CollectionManagementInitial extends CollectionManagementState {}

/// State indicating collection definitions are being loaded or switched.
class CollectionManagementLoading extends CollectionManagementState {
  const CollectionManagementLoading({
    super.availableCollections,
    super.activeCollectionDefinition,
  });
}

/// State representing successfully loaded collection definitions and the active one.
class CollectionManagementLoaded extends CollectionManagementState {
  const CollectionManagementLoaded({
    required super.availableCollections,
    required super.activeCollectionDefinition,
  });
}

/// State indicating an error occurred during collection management operations.
class CollectionManagementError extends CollectionManagementState {
  final String message;

  const CollectionManagementError(
    this.message, {
    super.availableCollections,
    super.activeCollectionDefinition,
  });

  @override
  List<Object?> get props => [
    message,
    availableCollections,
    activeCollectionDefinition,
  ];
}
